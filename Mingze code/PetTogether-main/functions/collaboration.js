import { createHash } from "node:crypto";

import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { onDocumentWritten } from "firebase-functions/v2/firestore";

const taskActions = new Set([
  "taskCreated",
  "taskRequested",
  "taskClaimed",
  "taskAccepted",
  "taskDeclined",
  "taskCancelled",
  "taskCompleted",
]);
const taskStates = new Set(["unclaimed", "claimed", "completed"]);
const taskCategories = new Set([
  "feeding",
  "walking",
  "medication",
  "grooming",
  "other",
]);
const taskPriorities = new Set(["normal", "urgent"]);

export function createCollaborationEventFunctions(db) {
  return {
    recordTaskCollaborationEvent: onDocumentWritten(
      {
        document: "households/{householdID}/tasks/{taskID}",
        retry: true,
      },
      (event) => appendTaskCollaborationEventAt(db, {
        householdID: event.params.householdID,
        taskID: event.params.taskID,
        previousTaskData: event.data?.before.exists
          ? event.data.before.data()
          : null,
        taskData: event.data?.after.exists
          ? event.data.after.data()
          : null,
      }),
    ),
  };
}

export async function appendTaskCollaborationEventAt(db, {
  householdID,
  taskID,
  previousTaskData = null,
  taskData,
}) {
  if (taskData == null || taskData.lastCollaborationAction == null) {
    return { created: false, skippedLegacy: true };
  }
  if (previousTaskData != null && sameMarker(previousTaskData, taskData)) {
    return { created: false, skippedLegacy: true };
  }
  const event = eventFromTask(taskID, taskData);
  const eventID = collaborationEventID({
    sourceID: taskID,
    sourceRevision: event.sourceRevision,
    action: event.action,
  });
  const reference = db.collection("households").doc(householdID)
    .collection("collaborationEvents").doc(eventID);
  return db.runTransaction(async (transaction) => {
    const existing = await transaction.get(reference);
    if (existing.exists) {
      if (!sameEvent(existing.data(), event)) {
        throw new Error("Collaboration event replay conflicts with stored history.");
      }
      return { eventID, created: false, skippedLegacy: false };
    }
    transaction.create(reference, {
      ...event,
      recordedAt: FieldValue.serverTimestamp(),
    });
    return { eventID, created: true, skippedLegacy: false };
  });
}

function sameMarker(before, after) {
  return [
    "lastCollaborationAction",
    "lastCollaborationActorID",
    "lastCollaborationActorName",
    "lastCollaborationTargetID",
    "lastCollaborationTargetName",
    "lastCollaborationRequestID",
    "lastCollaborationAt",
  ].every((key) => {
    const left = before?.[key];
    const right = after?.[key];
    if (left instanceof Timestamp || right instanceof Timestamp) {
      return left instanceof Timestamp && right instanceof Timestamp &&
        left.isEqual(right);
    }
    return left === right;
  });
}

export function collaborationEventID({ sourceID, sourceRevision, action }) {
  return createHash("sha256")
    .update(`tasks/${sourceID}|${sourceRevision}|${action}`)
    .digest("hex");
}

function eventFromTask(taskID, data) {
  const sourceID = validID(taskID, "task");
  const sourceRevision = data.revision;
  const action = data.lastCollaborationAction;
  const actorID = validID(data.lastCollaborationActorID, "actor");
  const actorName = validText(data.lastCollaborationActorName, 50, "actor");
  const targetMemberID = optionalID(data.lastCollaborationTargetID, "target");
  const targetMemberName = optionalText(
    data.lastCollaborationTargetName,
    50,
    "target",
  );
  const requestID = optionalID(data.lastCollaborationRequestID, "request");
  const assignmentMode = data.assignmentMode == null
    ? null
    : data.assignmentMode;
  const stateAfter = data.status;
  if (!Number.isInteger(sourceRevision) || sourceRevision < 0 ||
      !taskActions.has(action) || !taskStates.has(stateAfter) ||
      !(data.lastCollaborationAt instanceof Timestamp) ||
      (targetMemberID == null) !== (targetMemberName == null) ||
      (assignmentMode != null && assignmentMode !== "direct" &&
        assignmentMode !== "open") ||
      !actionMatchesState(action, stateAfter)) {
    throw new Error("The task collaboration marker is malformed.");
  }
  if (!taskCategories.has(data.category) ||
      !taskPriorities.has(data.priority) ||
      !(data.dueTime instanceof Timestamp)) {
    throw new Error("The task snapshot is malformed.");
  }
  const taskTitle = validText(data.title, 120, "task");
  return {
    schemaVersion: 1,
    sourceType: "task",
    sourceID,
    sourceRevision,
    action,
    actorID,
    actorName,
    targetMemberID,
    targetMemberName,
    requestID,
    assignmentMode,
    petID: validID(data.petID, "pet"),
    petName: validText(data.petName, 60, "pet"),
    taskTitle: data.category === "medication" ? "Medication care" : taskTitle,
    taskCategory: data.category,
    taskPriority: data.priority,
    taskDueTime: data.dueTime,
    stateAfter,
    occurredAt: data.lastCollaborationAt,
  };
}

function actionMatchesState(action, state) {
  if (action === "taskCompleted") return state === "completed";
  if (["taskClaimed", "taskAccepted"]
    .includes(action)) return state === "claimed";
  return state === "unclaimed";
}

function sameEvent(stored, expected) {
  return Object.entries(expected).every(([key, value]) => {
    const existing = stored?.[key];
    if (value instanceof Timestamp) {
      return existing instanceof Timestamp && existing.isEqual(value);
    }
    return existing === value;
  });
}

function validID(value, label) {
  if (typeof value !== "string" || value.length === 0 ||
      value.length > 128 || value.includes("/")) {
    throw new Error(`The ${label} ID is malformed.`);
  }
  return value;
}

function optionalID(value, label) {
  return value == null ? null : validID(value, label);
}

function validText(value, maximum, label) {
  if (typeof value !== "string" || value.trim().length === 0 ||
      value.length > maximum) {
    throw new Error(`The ${label} snapshot is malformed.`);
  }
  return value;
}

function optionalText(value, maximum, label) {
  return value == null ? null : validText(value, maximum, label);
}
