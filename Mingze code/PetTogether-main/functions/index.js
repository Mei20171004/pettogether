import { randomUUID } from "node:crypto";

import { initializeApp } from "firebase-admin/app";
import { FieldValue, Timestamp, getFirestore } from "firebase-admin/firestore";
import { setGlobalOptions } from "firebase-functions/v2";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { DateTime } from "luxon";

import {
  createMedicationCallables,
} from "./medication.js";
import { createHealthCallables } from "./health.js";
import { createNotificationV2Functions } from "./notifications_v2.js";
import { createCollaborationEventFunctions } from "./collaboration.js";
import {
  createTaskResponsibilityCallables,
} from "./task_responsibility.js";
import { createHandoffSessionCallables } from "./handoff_sessions.js";
import { createMembershipCallables } from "./membership.js";

initializeApp();
setGlobalOptions({ region: "asia-northeast1", maxInstances: 10 });

const db = getFirestore();
const actions = new Set(["claim", "requestOpen", "requestDirect"]);
const categories = new Set(["feeding", "walking", "medication", "grooming", "other"]);
const priorities = new Set(["normal", "urgent"]);

export const {
  archivePet,
  createMedicationPlan,
  replaceMedicationPlan,
  stopMedicationPlan,
  mutateMedicationOccurrence,
} = createMedicationCallables(db);

export const { createDailyHealthCheckIn, createHealthRecord } =
  createHealthCallables(db);

export const {
  setHouseholdNotificationPreferences,
  resetMalformedNotificationPreferences,
  resolveNotificationInboxRoute,
  expireNotificationInbox,
  recoverNotificationDigests,
  recoverNotificationManifests,
  dispatchNotificationV2,
  generateMedicationNotificationIntentsV2,
  onTaskNotificationSourceWritten,
  onTransferNotificationSourceWritten,
  onHandoffNotificationSourceWritten,
  onMedicationOccurrenceNotificationSourceWritten,
} = createNotificationV2Functions(db, {
  projectID: process.env.GCLOUD_PROJECT ?? process.env.GOOGLE_CLOUD_PROJECT,
});

export const { recordTaskCollaborationEvent } =
  createCollaborationEventFunctions(db);

export const { mutateTaskResponsibility } =
  createTaskResponsibilityCallables(db);

export const { mutateHandoffSession } = createHandoffSessionCallables(db);

export const { leaveHousehold } = createMembershipCallables(db);

export const mutateRoutineOccurrence = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in before changing care.");
  }

  const input = parseInput(request.data, uid);
  const requestID = input.action === "claim" ? null : randomUUID();
  const household = db.collection("households").doc(input.householdID);
  const routine = household.collection("routines").doc(input.routineID);
  const actor = household.collection("members").doc(uid);
  const recipient = input.recipientID == null
    ? null
    : household.collection("members").doc(input.recipientID);
  const taskID = `${input.routineID}_${input.localDate}`;
  const task = household.collection("tasks").doc(taskID);

  await db.runTransaction(async (transaction) => {
    const [householdSnapshot, routineSnapshot, actorSnapshot, taskSnapshot] =
      await Promise.all([
        transaction.get(household),
        transaction.get(routine),
        transaction.get(actor),
        transaction.get(task),
      ]);
    const recipientSnapshot = recipient == null
      ? null
      : await transaction.get(recipient);

    if (!householdSnapshot.exists || !actorSnapshot.exists) {
      throw new HttpsError("permission-denied", "Household membership is required.");
    }
    if (!routineSnapshot.exists) {
      throw new HttpsError("not-found", "The care routine no longer exists.");
    }
    if (taskSnapshot.exists) {
      throw new HttpsError("already-exists", "This occurrence changed. Refresh and try again.");
    }
    if (input.action === "requestDirect" && !recipientSnapshot?.exists) {
      throw new HttpsError("failed-precondition", "The selected caregiver is unavailable.");
    }

    const householdData = householdSnapshot.data();
    const routineData = routineSnapshot.data();
    const actorData = actorSnapshot.data();
    const recipientData = recipientSnapshot?.data();
    const occurrence = canonicalOccurrence({
      householdData,
      routineData,
      routineID: input.routineID,
      localDate: input.localDate,
    });
    const actorName = validName(actorData?.displayName, 50, "caregiver");
    const serverTime = FieldValue.serverTimestamp();

    const assignment = input.action === "claim"
      ? {
          status: "claimed",
          assignmentRequestID: null,
          assignmentMode: null,
          requestedByID: null,
          requestedByName: null,
          requestedToID: null,
          requestedToName: null,
          assignmentRequestedAt: null,
          assigneeID: uid,
          assigneeName: actorName,
          claimedAt: serverTime,
        }
      : {
          status: "unclaimed",
          assignmentRequestID: requestID,
          assignmentMode: input.action === "requestDirect" ? "direct" : "open",
          requestedByID: uid,
          requestedByName: actorName,
          requestedToID: input.recipientID,
          requestedToName: input.recipientID == null
            ? null
            : validName(recipientData?.displayName, 50, "recipient"),
          assignmentRequestedAt: serverTime,
          assigneeID: null,
          assigneeName: null,
          claimedAt: null,
        };
    const collaboration = {
      lastCollaborationAction: input.action === "claim"
        ? "taskClaimed"
        : "taskRequested",
      lastCollaborationActorID: uid,
      lastCollaborationActorName: actorName,
      lastCollaborationTargetID: input.recipientID,
      lastCollaborationTargetName: input.recipientID == null
        ? null
        : validName(recipientData?.displayName, 50, "recipient"),
      lastCollaborationRequestID: requestID,
      lastCollaborationAt: serverTime,
    };

    const petSnapshot = await canonicalPetSnapshot({
      transaction,
      household,
      householdData,
      routineData,
    });
    transaction.create(task, {
      id: taskID,
      title: occurrence.title,
      category: occurrence.category,
      dueTime: occurrence.dueTime,
      kind: "routine",
      priority: occurrence.priority,
      routineID: input.routineID,
      ...petSnapshot,
      ...assignment,
      ...collaboration,
      createdByID: occurrence.createdByID,
      createdBy: occurrence.createdByName,
      createdAt: serverTime,
      completedByID: null,
      completedBy: null,
      completedAt: null,
      revision: 1,
    });
  });

  return { taskID, requestID, revision: 1 };
});

function parseInput(data, uid) {
  if (data == null || typeof data !== "object" || Array.isArray(data)) {
    throw new HttpsError("invalid-argument", "A structured request is required.");
  }
  const householdID = boundedID(data.householdID, "householdID");
  const routineID = boundedID(data.routineID, "routineID");
  const action = data.action;
  const localDate = data.localDate;
  if (!actions.has(action)) {
    throw new HttpsError("invalid-argument", "The occurrence action is invalid.");
  }
  if (typeof localDate !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(localDate)) {
    throw new HttpsError("invalid-argument", "localDate must use YYYY-MM-DD.");
  }
  const recipientID = data.recipientID == null
    ? null
    : boundedID(data.recipientID, "recipientID");
  if ((action === "requestDirect") !== (recipientID != null)) {
    throw new HttpsError("invalid-argument", "Direct requests require one recipient.");
  }
  if (recipientID === uid) {
    throw new HttpsError("invalid-argument", "Choose a different caregiver.");
  }
  return { householdID, routineID, action, localDate, recipientID };
}

function boundedID(value, field) {
  if (typeof value !== "string" || value.length === 0 || value.length > 200 || value.includes("/")) {
    throw new HttpsError("invalid-argument", `${field} is invalid.`);
  }
  return value;
}

function canonicalOccurrence({ householdData, routineData, routineID, localDate }) {
  const zone = householdData?.timeZoneIdentifier;
  if (typeof zone !== "string" || !DateTime.now().setZone(zone).isValid) {
    throw new HttpsError("failed-precondition", "Repair the household timezone first.");
  }
  if (routineData?.timeZoneIdentifier !== zone || routineData?.isActive !== true) {
    throw new HttpsError("failed-precondition", "This routine is inactive or needs repair.");
  }
  const title = validName(routineData.title, 120, "routine");
  if (!categories.has(routineData.category) || !priorities.has(routineData.priority)) {
    throw new HttpsError("failed-precondition", "This routine needs repair.");
  }
  if (!Number.isInteger(routineData.hour) || routineData.hour < 0 || routineData.hour > 23 ||
      !Number.isInteger(routineData.minute) || routineData.minute < 0 || routineData.minute > 59) {
    throw new HttpsError("failed-precondition", "This routine has an invalid time.");
  }
  if (!(routineData.startDate instanceof Timestamp)) {
    throw new HttpsError("failed-precondition", "This routine has no valid start date.");
  }
  const weekdays = routineData.weekdays;
  if (!Array.isArray(weekdays) || weekdays.length === 0 || weekdays.length > 7 ||
      new Set(weekdays).size !== weekdays.length ||
      weekdays.some((day) => !Number.isInteger(day) || day < 1 || day > 7)) {
    throw new HttpsError("failed-precondition", "This routine has invalid weekdays.");
  }
  if (routineData.frequency !== "daily" && routineData.frequency !== "selectedDays") {
    throw new HttpsError("failed-precondition", "This routine has an invalid frequency.");
  }

  const day = DateTime.fromFormat(localDate, "yyyy-MM-dd", { zone, setZone: true });
  if (!day.isValid || day.toFormat("yyyy-MM-dd") !== localDate) {
    throw new HttpsError("invalid-argument", "The occurrence date is invalid.");
  }
  const startDay = DateTime.fromJSDate(routineData.startDate.toDate(), { zone }).startOf("day");
  const appleWeekday = day.weekday % 7 + 1;
  const occurs = routineData.frequency === "daily" || weekdays.includes(appleWeekday);
  if (day.startOf("day") < startDay || !occurs) {
    throw new HttpsError("failed-precondition", "The routine is not scheduled for this date.");
  }
  const due = DateTime.fromObject(
    {
      year: day.year,
      month: day.month,
      day: day.day,
      hour: routineData.hour,
      minute: routineData.minute,
    },
    { zone },
  );
  if (!due.isValid || due.toFormat("yyyy-MM-dd") !== localDate ||
      due.hour !== routineData.hour || due.minute !== routineData.minute) {
    throw new HttpsError("failed-precondition", "This local time does not exist on that date.");
  }

  const createdByID = boundedID(routineData.createdByID, "createdByID");
  const createdByName = validName(routineData.createdByName, 50, "creator");
  return {
    routineID,
    title,
    category: routineData.category,
    priority: routineData.priority,
    dueTime: Timestamp.fromDate(due.toUTC().toJSDate()),
    createdByID,
    createdByName,
  };
}

async function canonicalPetSnapshot({ transaction, household, householdData, routineData }) {
  const hasPetID = Object.hasOwn(routineData, "petID");
  const hasPetName = Object.hasOwn(routineData, "petName");
  if (hasPetID !== hasPetName) {
    throw new HttpsError("failed-precondition", "This routine has an incomplete pet snapshot.");
  }
  if (!hasPetID) {
    const legacyPet = await transaction.get(
      household.collection("pets").doc("legacy-primary"),
    );
    if (legacyPet.exists) {
      if (legacyPet.data()?.isArchived === true) {
        throw new HttpsError("failed-precondition", "This pet is archived or unavailable.");
      }
      return {
        petID: "legacy-primary",
        petName: validName(legacyPet.data()?.name, 60, "pet"),
      };
    }
    return {
      petID: "legacy-primary",
      petName: validName(householdData?.petName, 60, "pet"),
    };
  }
  const petID = boundedID(routineData.petID, "petID");
  validName(routineData.petName, 60, "pet");
  const petSnapshot = await transaction.get(household.collection("pets").doc(petID));
  if (!petSnapshot.exists || petSnapshot.data()?.isArchived === true) {
    throw new HttpsError("failed-precondition", "This pet is archived or unavailable.");
  }
  const currentPetName = validName(petSnapshot.data()?.name, 60, "pet");
  return { petID, petName: currentPetName };
}

function validName(value, maximum, label) {
  if (typeof value !== "string" || value.trim().length === 0 || value.length > maximum) {
    throw new HttpsError("failed-precondition", `The ${label} name is invalid.`);
  }
  return value;
}
