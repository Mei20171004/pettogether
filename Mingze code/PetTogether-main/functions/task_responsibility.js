import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import {
  boundedID,
  digest,
  eventReference,
  exactObject,
  fingerprint,
  lt5CallableOptions,
  mutationID,
  positiveRevision,
  readReceipt,
  receiptPayload,
  receiptReference,
  stale,
  validName,
  v2Event,
} from "./lt5_common.js";

const actions = new Set([
  "release",
  "requestReassign",
  "requestTakeover",
  "acceptTransfer",
  "declineTransfer",
  "cancelTransfer",
  "complete",
]);
const categories = new Set([
  "feeding",
  "walking",
  "medication",
  "grooming",
  "other",
]);
const priorities = new Set(["normal", "urgent"]);

export function createTaskResponsibilityCallables(db) {
  return {
    mutateTaskResponsibility: onCall(
      lt5CallableOptions,
      (request) => mutateTaskResponsibilityAt(db, request),
    ),
  };
}

export async function mutateTaskResponsibilityAt(db, request) {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in before changing responsibility.");
  }
  const input = parseInput(request.data);
  const household = db.collection("households").doc(input.householdID);
  const taskReference = household.collection("tasks").doc(input.taskID);
  const actorReference = household.collection("members").doc(uid);
  const stateReference = household.collection("taskResponsibilityState")
    .doc(input.taskID);
  const receipt = receiptReference(
    household,
    "taskResponsibilityReceipts",
    uid,
    input.clientMutationID,
  );
  const expectedFingerprint = fingerprint(input);

  return db.runTransaction(async (transaction) => {
    const [householdSnapshot, actorSnapshot, taskSnapshot, stateSnapshot,
      receiptSnapshot, pendingTransfersSnapshot] = await Promise.all([
      transaction.get(household),
      transaction.get(actorReference),
      transaction.get(taskReference),
      transaction.get(stateReference),
      transaction.get(receipt),
      transaction.get(
        household.collection("taskResponsibilityTransfers")
          .where("status", "==", "pending"),
      ),
    ]);
    const prior = readReceipt(receiptSnapshot, expectedFingerprint, input.action);
    if (prior != null) return { ...prior, existing: true };
    if (!householdSnapshot.exists || !actorSnapshot.exists) {
      throw new HttpsError("permission-denied", "Household membership is required.");
    }
    if (!taskSnapshot.exists) {
      throw new HttpsError("not-found", "The care task no longer exists.");
    }

    const actorName = validName(actorSnapshot.data()?.displayName, "caregiver");
    const task = canonicalClaimedTask(taskSnapshot.id, taskSnapshot.data());
    if (task.revision !== input.expectedTaskRevision) {
      stale(taskResultDetails(task, stateSnapshot));
    }

    let pending = null;
    const matchingPendingTransfers = pendingTransfersSnapshot.docs.filter(
      (document) => document.data()?.taskID === input.taskID,
    );
    if (stateSnapshot.exists) {
      const pointer = canonicalPointer(input.taskID, stateSnapshot.data());
      if (matchingPendingTransfers.length !== 1 ||
          matchingPendingTransfers[0].id !== pointer.transferID) {
        throw malformedState();
      }
      const transferSnapshot = await transaction.get(
        household.collection("taskResponsibilityTransfers").doc(pointer.transferID),
      );
      if (!transferSnapshot.exists) {
        throw malformedState();
      }
      pending = canonicalTransfer(transferSnapshot.id, transferSnapshot.data());
      if (pending.status !== "pending" || pending.taskID !== input.taskID ||
          pending.id !== pointer.transferID ||
          pending.taskRevisionAtProposal !== pointer.taskRevisionAtProposal ||
          pending.createdAt.toMillis() !== pointer.createdAt.toMillis()) {
        throw malformedState();
      }
    } else if (matchingPendingTransfers.length > 0) {
      throw malformedState();
    }

    let result;
    switch (input.action) {
      case "release":
        result = release({
          transaction,
          household,
          taskReference,
          task,
          uid,
          actorName,
          pending,
        });
        break;
      case "requestReassign":
      case "requestTakeover":
        result = await requestTransfer({
          transaction,
          household,
          task,
          uid,
          actorName,
          input,
          pending,
        });
        break;
      case "acceptTransfer":
      case "declineTransfer":
      case "cancelTransfer":
        result = resolveTransfer({
          transaction,
          household,
          taskReference,
          stateReference,
          task,
          pending,
          uid,
          actorName,
          input,
        });
        break;
      case "complete":
        result = complete({
          transaction,
          household,
          taskReference,
          stateReference,
          task,
          pending,
          uid,
          actorName,
        });
        break;
      default:
        throw new HttpsError("invalid-argument", "The action is invalid.");
    }

    transaction.create(receipt, receiptPayload({
      uid,
      expectedFingerprint,
      action: input.action,
      result,
    }));
    return { ...result, existing: false };
  });
}

function release({
  transaction,
  household,
  taskReference,
  task,
  uid,
  actorName,
  pending,
}) {
  if (task.assigneeID !== uid) throw wrongActor();
  if (pending != null) {
    throw new HttpsError(
      "failed-precondition",
      "Resolve the pending responsibility request first.",
    );
  }
  const nextRevision = task.revision + 1;
  transaction.update(taskReference, {
    status: "unclaimed",
    assigneeID: null,
    assigneeName: null,
    claimedAt: null,
    revision: nextRevision,
  });
  const action = "taskReleased";
  transaction.create(
    eventReference(household, `tasks/${task.id}`, nextRevision, action),
    taskEvent({
      task,
      sourceType: "task",
      sourceID: task.id,
      sourceRevision: nextRevision,
      action,
      actorID: uid,
      actorName,
      responsibilityFromID: task.assigneeID,
      responsibilityFromName: task.assigneeName,
      stateAfter: "unclaimed",
    }),
  );
  return taskResult({
    taskID: task.id,
    taskRevision: nextRevision,
    taskStatus: "unclaimed",
    assigneeID: null,
  });
}

async function requestTransfer({
  transaction,
  household,
  task,
  uid,
  actorName,
  input,
  pending,
}) {
  if (pending != null) {
    throw new HttpsError(
      "failed-precondition",
      "A responsibility request is already pending.",
    );
  }
  let kind;
  let requestedByID;
  let requestedByName;
  let consentByID;
  let consentByName;
  let responsibilityToID;
  let responsibilityToName;
  if (input.action === "requestReassign") {
    if (task.assigneeID !== uid) throw wrongActor();
    if (input.targetMemberID === uid) {
      throw new HttpsError("invalid-argument", "Choose another caregiver.");
    }
    const target = await transaction.get(
      household.collection("members").doc(input.targetMemberID),
    );
    if (!target.exists) {
      throw new HttpsError("failed-precondition", "The selected caregiver is unavailable.");
    }
    kind = "reassign";
    requestedByID = uid;
    requestedByName = actorName;
    consentByID = input.targetMemberID;
    consentByName = validName(target.data()?.displayName, "recipient");
    responsibilityToID = consentByID;
    responsibilityToName = consentByName;
  } else {
    if (task.assigneeID === uid) {
      throw new HttpsError("invalid-argument", "The current caregiver cannot request takeover.");
    }
    const assignee = await transaction.get(
      household.collection("members").doc(task.assigneeID),
    );
    if (!assignee.exists) {
      throw new HttpsError("failed-precondition", "The current caregiver is unavailable.");
    }
    kind = "takeover";
    requestedByID = uid;
    requestedByName = actorName;
    consentByID = task.assigneeID;
    consentByName = validName(assignee.data()?.displayName, "assignee");
    responsibilityToID = uid;
    responsibilityToName = actorName;
  }

  const transferID = `tr_${digest(`${uid}:${input.clientMutationID}`)}`;
  const transferReference = household.collection("taskResponsibilityTransfers")
    .doc(transferID);
  const transferSnapshot = await transaction.get(transferReference);
  if (transferSnapshot.exists) {
    throw new HttpsError("already-exists", "This responsibility request already exists.");
  }
  const serverTime = FieldValue.serverTimestamp();
  const transfer = {
    schemaVersion: 1,
    id: transferID,
    taskID: task.id,
    kind,
    status: "pending",
    requestedByID,
    requestedByName,
    consentByID,
    consentByName,
    responsibilityFromID: task.assigneeID,
    responsibilityFromName: task.assigneeName,
    responsibilityToID,
    responsibilityToName,
    taskRevisionAtProposal: task.revision,
    createdAt: serverTime,
    resolvedByID: null,
    resolvedByName: null,
    resolvedAt: null,
    resultingTaskRevision: null,
    revision: 1,
  };
  transaction.create(transferReference, transfer);
  transaction.create(household.collection("taskResponsibilityState").doc(task.id), {
    schemaVersion: 1,
    taskID: task.id,
    transferID,
    taskRevisionAtProposal: task.revision,
    createdAt: serverTime,
  });
  const eventAction = kind === "reassign"
    ? "taskReassignRequested"
    : "taskTakeoverRequested";
  transaction.create(
    eventReference(
      household,
      `taskResponsibilityTransfers/${transferID}`,
      1,
      eventAction,
    ),
    taskEvent({
      task,
      sourceType: "taskResponsibilityTransfer",
      sourceID: transferID,
      sourceRevision: 1,
      action: eventAction,
      actorID: uid,
      actorName,
      responsibilityFromID: task.assigneeID,
      responsibilityFromName: task.assigneeName,
      responsibilityToID,
      responsibilityToName,
      requestID: transferID,
      stateAfter: "claimed",
    }),
  );
  return taskResult({
    taskID: task.id,
    taskRevision: task.revision,
    taskStatus: "claimed",
    assigneeID: task.assigneeID,
    transferID,
    transferRevision: 1,
    transferStatus: "pending",
  });
}

function resolveTransfer({
  transaction,
  household,
  taskReference,
  stateReference,
  task,
  pending,
  uid,
  actorName,
  input,
}) {
  if (pending == null || pending.id !== input.transferID) {
    throw new HttpsError("failed-precondition", "The responsibility request is no longer pending.");
  }
  if (pending.revision !== input.expectedTransferRevision) {
    stale({
      taskID: task.id,
      taskRevision: task.revision,
      transferID: pending.id,
      transferRevision: pending.revision,
      transferStatus: pending.status,
    });
  }
  if (pending.taskRevisionAtProposal !== task.revision ||
      pending.responsibilityFromID !== task.assigneeID) {
    throw malformedState();
  }
  if (input.action === "acceptTransfer" || input.action === "declineTransfer") {
    if (pending.consentByID !== uid) throw wrongActor();
  } else if (pending.requestedByID !== uid) {
    throw wrongActor();
  }

  let status;
  let action;
  let nextTaskRevision = task.revision;
  let assigneeID = task.assigneeID;
  if (input.action === "acceptTransfer") {
    status = "accepted";
    action = pending.kind === "reassign" ? "taskReassigned" : "taskTakenOver";
    nextTaskRevision += 1;
    assigneeID = pending.responsibilityToID;
    transaction.update(taskReference, {
      assigneeID,
      assigneeName: pending.responsibilityToName,
      claimedAt: FieldValue.serverTimestamp(),
      revision: nextTaskRevision,
    });
  } else if (input.action === "declineTransfer") {
    status = "declined";
    action = "taskTransferDeclined";
  } else {
    status = "cancelled";
    action = "taskTransferCancelled";
  }

  transaction.update(
    household.collection("taskResponsibilityTransfers").doc(pending.id),
    {
      status,
      resolvedByID: uid,
      resolvedByName: actorName,
      resolvedAt: FieldValue.serverTimestamp(),
      resultingTaskRevision: status === "accepted" ? nextTaskRevision : null,
      revision: 2,
    },
  );
  transaction.delete(stateReference);
  transaction.create(
    eventReference(
      household,
      `taskResponsibilityTransfers/${pending.id}`,
      2,
      action,
    ),
    taskEvent({
      task,
      sourceType: "taskResponsibilityTransfer",
      sourceID: pending.id,
      sourceRevision: 2,
      action,
      actorID: uid,
      actorName,
      responsibilityFromID: pending.responsibilityFromID,
      responsibilityFromName: pending.responsibilityFromName,
      responsibilityToID: pending.responsibilityToID,
      responsibilityToName: pending.responsibilityToName,
      requestID: pending.id,
      stateAfter: "claimed",
    }),
  );
  return taskResult({
    taskID: task.id,
    taskRevision: nextTaskRevision,
    taskStatus: "claimed",
    assigneeID,
    transferID: pending.id,
    transferRevision: 2,
    transferStatus: status,
  });
}

function complete({
  transaction,
  household,
  taskReference,
  stateReference,
  task,
  pending,
  uid,
  actorName,
}) {
  if (task.assigneeID !== uid) throw wrongActor();
  const nextTaskRevision = task.revision + 1;
  const serverTime = FieldValue.serverTimestamp();
  transaction.update(taskReference, {
    status: "completed",
    completedByID: uid,
    completedBy: actorName,
    completedAt: serverTime,
    lastCollaborationAction: "taskCompleted",
    lastCollaborationActorID: uid,
    lastCollaborationActorName: actorName,
    lastCollaborationTargetID: null,
    lastCollaborationTargetName: null,
    lastCollaborationRequestID: null,
    lastCollaborationAt: serverTime,
    revision: nextTaskRevision,
  });
  let transferID = null;
  let transferRevision = null;
  let transferStatus = null;
  if (pending != null) {
    if (pending.taskRevisionAtProposal !== task.revision ||
        pending.responsibilityFromID !== task.assigneeID) {
      throw malformedState();
    }
    transferID = pending.id;
    transferRevision = 2;
    transferStatus = "superseded";
    transaction.update(
      household.collection("taskResponsibilityTransfers").doc(pending.id),
      {
        status: transferStatus,
        resolvedByID: uid,
        resolvedByName: actorName,
        resolvedAt: serverTime,
        resultingTaskRevision: nextTaskRevision,
        revision: transferRevision,
      },
    );
    transaction.delete(stateReference);
    const action = "taskTransferSuperseded";
    transaction.create(
      eventReference(
        household,
        `taskResponsibilityTransfers/${pending.id}`,
        transferRevision,
        action,
      ),
      taskEvent({
        task,
        sourceType: "taskResponsibilityTransfer",
        sourceID: pending.id,
        sourceRevision: transferRevision,
        action,
        actorID: uid,
        actorName,
        responsibilityFromID: pending.responsibilityFromID,
        responsibilityFromName: pending.responsibilityFromName,
        responsibilityToID: pending.responsibilityToID,
        responsibilityToName: pending.responsibilityToName,
        requestID: pending.id,
        stateAfter: "completed",
      }),
    );
  }
  return taskResult({
    taskID: task.id,
    taskRevision: nextTaskRevision,
    taskStatus: "completed",
    assigneeID: task.assigneeID,
    transferID,
    transferRevision,
    transferStatus,
  });
}

function parseInput(data) {
  if (data == null || typeof data !== "object" || Array.isArray(data)) {
    throw new HttpsError("invalid-argument", "A structured request is required.");
  }
  const action = data.action;
  if (!actions.has(action)) {
    throw new HttpsError("invalid-argument", "The action is invalid.");
  }
  const common = new Set([
    "householdID",
    "taskID",
    "action",
    "expectedTaskRevision",
    "clientMutationID",
  ]);
  if (action === "requestReassign") common.add("targetMemberID");
  if (["acceptTransfer", "declineTransfer", "cancelTransfer"].includes(action)) {
    common.add("transferID");
    common.add("expectedTransferRevision");
  }
  exactObject(data, common);
  return {
    householdID: boundedID(data.householdID, "householdID"),
    taskID: boundedID(data.taskID, "taskID"),
    action,
    expectedTaskRevision: positiveRevision(
      data.expectedTaskRevision,
      "expectedTaskRevision",
      { allowZero: true },
    ),
    targetMemberID: action === "requestReassign"
      ? boundedID(data.targetMemberID, "targetMemberID")
      : null,
    transferID: common.has("transferID")
      ? boundedID(data.transferID, "transferID")
      : null,
    expectedTransferRevision: common.has("expectedTransferRevision")
      ? positiveRevision(data.expectedTransferRevision, "expectedTransferRevision")
      : null,
    clientMutationID: mutationID(data.clientMutationID),
  };
}

function canonicalClaimedTask(taskID, data) {
  const nullableKeys = [
    "routineID",
    "assignmentRequestID",
    "assignmentMode",
    "requestedByID",
    "requestedByName",
    "requestedToID",
    "requestedToName",
    "assignmentRequestedAt",
    "assigneeID",
    "assigneeName",
    "claimedAt",
    "completedByID",
    "completedBy",
    "completedAt",
  ];
  if (data?.id !== taskID || data?.status !== "claimed" ||
      !Number.isInteger(data?.revision) || data.revision < 0 ||
      typeof data?.title !== "string" || data.title.trim().length === 0 ||
      data.title.length > 120 || !categories.has(data?.category) ||
      !priorities.has(data?.priority) || !(data?.dueTime instanceof Timestamp) ||
      typeof data?.petID !== "string" || data.petID.length === 0 ||
      typeof data?.petName !== "string" || data.petName.trim().length === 0 ||
      typeof data?.createdByID !== "string" ||
      nullableKeys.some((key) => !Object.hasOwn(data, key)) ||
      data.assignmentRequestID != null || data.assignmentMode != null ||
      data.requestedByID != null || data.requestedByName != null ||
      data.requestedToID != null || data.requestedToName != null ||
      data.assignmentRequestedAt != null ||
      !storedID(data.petID) || !storedText(data.petName, 60) ||
      !storedID(data.assigneeID) || !storedText(data.assigneeName, 50) ||
      !(data.claimedAt instanceof Timestamp) || data.completedByID != null ||
      data.completedBy != null || data.completedAt != null) {
    throw new HttpsError(
      "failed-precondition",
      "This task needs canonical repair before responsibility can change.",
    );
  }
  return { id: taskID, ...data };
}

export function canonicalPointer(taskID, data) {
  const keys = new Set([
    "schemaVersion",
    "taskID",
    "transferID",
    "taskRevisionAtProposal",
    "createdAt",
  ]);
  if (data == null || Object.keys(data).length !== keys.size ||
      Object.keys(data).some((key) => !keys.has(key)) ||
      data.schemaVersion !== 1 || data.taskID !== taskID ||
      typeof data.transferID !== "string" || data.transferID.length === 0 ||
      data.transferID.length > 128 || data.transferID.includes("/") ||
      !Number.isInteger(data.taskRevisionAtProposal) ||
      !(data.createdAt instanceof Timestamp)) {
    throw malformedState();
  }
  return data;
}

export function canonicalTransfer(transferID, data) {
  const keys = new Set([
    "schemaVersion", "id", "taskID", "kind", "status",
    "requestedByID", "requestedByName", "consentByID", "consentByName",
    "responsibilityFromID", "responsibilityFromName",
    "responsibilityToID", "responsibilityToName", "taskRevisionAtProposal",
    "createdAt", "resolvedByID", "resolvedByName", "resolvedAt",
    "resultingTaskRevision", "revision",
  ]);
  const roleSemantics = data?.kind === "reassign"
    ? data.requestedByID === data.responsibilityFromID &&
      data.requestedByName === data.responsibilityFromName &&
      data.consentByID === data.responsibilityToID &&
      data.consentByName === data.responsibilityToName
    : data?.kind === "takeover" &&
      data.requestedByID === data.responsibilityToID &&
      data.requestedByName === data.responsibilityToName &&
      data.consentByID === data.responsibilityFromID &&
      data.consentByName === data.responsibilityFromName;
  if (data == null || Object.keys(data).length !== keys.size ||
      Object.keys(data).some((key) => !keys.has(key)) ||
      data.schemaVersion !== 1 || data.id !== transferID || !storedID(transferID) ||
      !["reassign", "takeover"].includes(data.kind) ||
      !["pending", "accepted", "declined", "cancelled", "superseded"].includes(data.status) ||
      !Number.isInteger(data.taskRevisionAtProposal) || data.taskRevisionAtProposal < 0 ||
      !Number.isInteger(data.revision) || !(data.createdAt instanceof Timestamp) ||
      !storedID(data.taskID) ||
      ["requestedByID", "consentByID", "responsibilityFromID",
        "responsibilityToID"].some((key) => !storedID(data[key])) ||
      ["requestedByName", "consentByName", "responsibilityFromName",
        "responsibilityToName"].some((key) => !storedText(data[key], 50)) ||
      data.responsibilityFromID === data.responsibilityToID || !roleSemantics ||
      (data.status === "pending" &&
        (data.revision !== 1 || data.resolvedByID != null ||
          data.resolvedByName != null || data.resolvedAt != null ||
          data.resultingTaskRevision != null)) ||
      (data.status !== "pending" &&
        (data.revision !== 2 || !storedID(data.resolvedByID) ||
          !storedText(data.resolvedByName, 50) ||
          !(data.resolvedAt instanceof Timestamp))) ||
      (["accepted", "superseded"].includes(data.status) &&
        (!Number.isInteger(data.resultingTaskRevision) ||
          data.resultingTaskRevision !== data.taskRevisionAtProposal + 1)) ||
      (["declined", "cancelled"].includes(data.status) &&
        data.resultingTaskRevision != null) ||
      (["accepted", "declined"].includes(data.status) &&
        data.resolvedByID !== data.consentByID) ||
      (data.status === "cancelled" &&
        data.resolvedByID !== data.requestedByID) ||
      (data.status === "superseded" &&
        data.resolvedByID !== data.responsibilityFromID)) {
    throw malformedState();
  }
  return data;
}

function taskEvent({ task, ...fields }) {
  return v2Event({
    ...fields,
    petID: task.petID,
    petName: task.petName,
    taskTitle: task.category === "medication" ? "Medication care" : task.title,
    taskCategory: task.category,
    taskPriority: task.priority,
    taskDueTime: task.dueTime,
  });
}

function taskResult({
  taskID,
  taskRevision,
  taskStatus,
  assigneeID,
  transferID = null,
  transferRevision = null,
  transferStatus = null,
}) {
  return {
    taskID,
    taskRevision,
    taskStatus,
    assigneeID,
    transferID,
    transferRevision,
    transferStatus,
  };
}

function taskResultDetails(task, stateSnapshot) {
  return {
    taskID: task.id,
    taskRevision: task.revision,
    taskStatus: task.status,
    assigneeID: task.assigneeID,
    transferID: stateSnapshot.exists ? stateSnapshot.data()?.transferID ?? null : null,
  };
}

function wrongActor() {
  return new HttpsError("permission-denied", "This member cannot perform that action.");
}

function malformedState() {
  return new HttpsError(
    "failed-precondition",
    "The responsibility state is inconsistent and must be reviewed.",
  );
}

function storedID(value) {
  return typeof value === "string" && value.length > 0 &&
    value.length <= 128 && !value.includes("/");
}

function storedText(value, maximum) {
  return typeof value === "string" && value.trim().length > 0 &&
    value.length <= maximum;
}
