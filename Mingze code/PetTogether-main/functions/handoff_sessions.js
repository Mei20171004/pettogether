import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { IANAZone } from "luxon";

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

const actions = new Set(["offer", "accept", "decline", "cancel", "close"]);
const maximumDurationMilliseconds = 30 * 24 * 60 * 60 * 1000;

export function createHandoffSessionCallables(db, { now = () => new Date() } = {}) {
  return {
    mutateHandoffSession: onCall(
      lt5CallableOptions,
      (request) => mutateHandoffSessionAt(db, request, now()),
    ),
  };
}

export async function mutateHandoffSessionAt(
  db,
  request,
  receivedAt = new Date(),
) {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in before changing handoff.");
  }
  if (!(receivedAt instanceof Date) || Number.isNaN(receivedAt.getTime())) {
    throw new HttpsError("internal", "The server clock is unavailable.");
  }
  const input = parseInput(request.data);
  const household = db.collection("households").doc(input.householdID);
  const actorReference = household.collection("members").doc(uid);
  const pointerReference = household.collection("handoff").doc("sessionState");
  const receipt = receiptReference(
    household,
    "handoffSessionReceipts",
    uid,
    input.clientMutationID,
  );
  const expectedFingerprint = fingerprint(input);

  return db.runTransaction(async (transaction) => {
    const [householdSnapshot, actorSnapshot, pointerSnapshot, receiptSnapshot,
      activeSessionsSnapshot] =
      await Promise.all([
        transaction.get(household),
        transaction.get(actorReference),
        transaction.get(pointerReference),
        transaction.get(receipt),
        transaction.get(
          household.collection("handoffSessions")
            .where("status", "in", ["offered", "accepted"]),
        ),
      ]);
    const prior = readReceipt(receiptSnapshot, expectedFingerprint, input.action);
    if (prior != null) return { ...prior, existing: true };
    if (!householdSnapshot.exists || !actorSnapshot.exists) {
      throw new HttpsError("permission-denied", "Household membership is required.");
    }
    const actorName = validName(actorSnapshot.data()?.displayName, "caregiver");
    const householdData = householdSnapshot.data();
    const ownerID = boundedStoredID(householdData?.ownerID, "household owner");
    const pointer = pointerSnapshot.exists
      ? canonicalSessionPointer(pointerSnapshot.data())
      : null;

    let result;
    if (input.action === "offer") {
      result = await offer({
        transaction,
        household,
        householdData,
        pointer,
        input,
        uid,
        actorName,
        receivedAt,
        activeSessionsSnapshot,
      });
    } else {
      result = await resolveSession({
        transaction,
        household,
        pointerReference,
        pointer,
        input,
        uid,
        actorName,
        ownerID,
        receivedAt,
        activeSessionsSnapshot,
      });
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

async function offer({
  transaction,
  household,
  householdData,
  pointer,
  input,
  uid,
  actorName,
  receivedAt,
  activeSessionsSnapshot,
}) {
  if (pointer != null || !activeSessionsSnapshot.empty) {
    throw new HttpsError(
      "failed-precondition",
      "Resolve the active handoff session before offering another.",
      {
        sessionID: pointer?.sessionID ?? activeSessionsSnapshot.docs[0]?.id ?? null,
        sessionStatus: pointer?.sessionStatus ??
          activeSessionsSnapshot.docs[0]?.data()?.status ?? null,
      },
    );
  }
  if (input.recipientID === uid) {
    throw new HttpsError("invalid-argument", "Choose another caregiver.");
  }
  if (input.plannedEndMilliseconds <= receivedAt.getTime()) {
    throw new HttpsError("invalid-argument", "The handoff window is invalid.");
  }
  const templateReference = household.collection("handoff").doc("current");
  const recipientReference = household.collection("members").doc(input.recipientID);
  const versionID = versionIDFor(input.expectedHandoffRevision);
  const versionReference = household.collection("handoffVersions").doc(versionID);
  const sessionID = `hs_${digest(`${uid}:${input.clientMutationID}`)}`;
  const sessionReference = household.collection("handoffSessions").doc(sessionID);
  const [templateSnapshot, recipientSnapshot, versionSnapshot, sessionSnapshot] =
    await Promise.all([
      transaction.get(templateReference),
      transaction.get(recipientReference),
      transaction.get(versionReference),
      transaction.get(sessionReference),
    ]);
  if (!templateSnapshot.exists) {
    throw new HttpsError("failed-precondition", "Create handoff information first.");
  }
  if (!recipientSnapshot.exists) {
    throw new HttpsError("failed-precondition", "The selected caregiver is unavailable.");
  }
  if (sessionSnapshot.exists) {
    throw new HttpsError("already-exists", "This handoff session already exists.");
  }
  const template = canonicalTemplate(templateSnapshot.data());
  if (template.revision !== input.expectedHandoffRevision) {
    stale({ handoffRevision: template.revision });
  }
  const recipientName = validName(recipientSnapshot.data()?.displayName, "recipient");
  const zone = householdData?.timeZoneIdentifier;
  if (typeof zone !== "string" || !IANAZone.isValidZone(zone)) {
    throw new HttpsError(
      "failed-precondition",
      "Repair the household timezone before offering handoff.",
    );
  }
  const serverTime = FieldValue.serverTimestamp();
  const transitionTime = Timestamp.fromDate(receivedAt);
  const version = {
    schemaVersion: 1,
    id: versionID,
    sourceHandoffRevision: template.revision,
    careInstructions: template.careInstructions,
    emergencyContactName: template.emergencyContactName,
    emergencyContactPhone: template.emergencyContactPhone,
    veterinaryHospitalName: template.veterinaryHospitalName,
    veterinaryHospitalPhone: template.veterinaryHospitalPhone,
    updatedByID: template.updatedByID,
    updatedByName: template.updatedByName,
    updatedAt: template.updatedAt,
    materializedAt: serverTime,
  };
  if (versionSnapshot.exists) {
    assertEquivalentVersion(versionID, versionSnapshot.data(), version);
  } else {
    transaction.create(versionReference, version);
  }
  const session = {
    schemaVersion: 1,
    id: sessionID,
    versionID,
    handoffRevisionSnapshot: template.revision,
    creatorID: uid,
    creatorName: actorName,
    recipientID: input.recipientID,
    recipientName,
    timeZoneIdentifierSnapshot: zone,
    plannedStartAt: Timestamp.fromMillis(input.plannedStartMilliseconds),
    plannedEndAt: Timestamp.fromMillis(input.plannedEndMilliseconds),
    status: "offered",
    offeredAt: transitionTime,
    acceptedByID: null,
    acceptedByName: null,
    acceptedAt: null,
    declinedByID: null,
    declinedByName: null,
    declinedAt: null,
    cancelledByID: null,
    cancelledByName: null,
    cancelledAt: null,
    closedByID: null,
    closedByName: null,
    closedAt: null,
    resolutionReason: null,
    revision: 1,
  };
  transaction.create(sessionReference, session);
  transaction.create(household.collection("handoff").doc("sessionState"), {
    schemaVersion: 1,
    sessionID,
    sessionStatus: "offered",
    plannedEndAt: session.plannedEndAt,
    updatedAt: transitionTime,
  });
  transaction.create(
    eventReference(household, `handoffSessions/${sessionID}`, 1, "handoffOffered"),
    handoffEvent({
      session,
      sourceRevision: 1,
      action: "handoffOffered",
      actorID: uid,
      actorName,
      handoffStatus: "offered",
      occurredAt: transitionTime,
    }),
  );
  return sessionResult({
    sessionID,
    sessionRevision: 1,
    sessionStatus: "offered",
    activeSessionID: sessionID,
    versionID,
  });
}

async function resolveSession({
  transaction,
  household,
  pointerReference,
  pointer,
  input,
  uid,
  actorName,
  ownerID,
  receivedAt,
  activeSessionsSnapshot,
}) {
  const sessionReference = household.collection("handoffSessions").doc(input.sessionID);
  const sessionSnapshot = await transaction.get(sessionReference);
  if (!sessionSnapshot.exists) {
    throw new HttpsError("not-found", "The handoff session no longer exists.");
  }
  const session = canonicalSession(
    sessionSnapshot.id,
    sessionSnapshot.data(),
    ownerID,
  );
  if (session.revision !== input.expectedSessionRevision) {
    stale({
      sessionID: session.id,
      sessionRevision: session.revision,
      sessionStatus: session.status,
    });
  }
  if (pointer == null || pointer.sessionID !== session.id ||
      pointer.sessionStatus !== session.status ||
      pointer.plannedEndAt.toMillis() !== session.plannedEndAt.toMillis() ||
      activeSessionsSnapshot.size !== 1 ||
      activeSessionsSnapshot.docs[0].id !== session.id ||
      activeSessionsSnapshot.docs[0].data()?.status !== session.status) {
    throw new HttpsError(
      "failed-precondition",
      "The active handoff state is inconsistent and must be reviewed.",
    );
  }

  let status;
  let revision;
  let action;
  let resolutionReason = null;
  const update = {};
  const transitionTime = Timestamp.fromDate(receivedAt);
  if (input.action === "accept") {
    requireStatus(session, "offered");
    if (uid !== session.recipientID) throw wrongActor();
    if (receivedAt.getTime() >= session.plannedEndAt.toMillis()) {
      throw new HttpsError(
        "failed-precondition",
        "This handoff window has ended and must be cancelled or closed.",
      );
    }
    status = "accepted";
    revision = 2;
    action = "handoffAccepted";
    update.acceptedByID = uid;
    update.acceptedByName = actorName;
    update.acceptedAt = transitionTime;
  } else if (input.action === "decline") {
    requireStatus(session, "offered");
    if (uid !== session.recipientID) throw wrongActor();
    status = "declined";
    revision = 2;
    action = "handoffDeclined";
    update.declinedByID = uid;
    update.declinedByName = actorName;
    update.declinedAt = transitionTime;
  } else if (input.action === "cancel") {
    requireStatus(session, "offered");
    if (uid !== session.creatorID && uid !== ownerID) throw wrongActor();
    if (uid !== session.creatorID) resolutionReason = "ownerRecovery";
    status = "cancelled";
    revision = 2;
    action = "handoffCancelled";
    update.cancelledByID = uid;
    update.cancelledByName = actorName;
    update.cancelledAt = transitionTime;
  } else {
    requireStatus(session, "accepted");
    if (uid !== session.creatorID && uid !== session.recipientID && uid !== ownerID) {
      throw wrongActor();
    }
    if (uid !== session.creatorID && uid !== session.recipientID) {
      resolutionReason = "ownerRecovery";
    }
    status = "closed";
    revision = 3;
    action = "handoffClosed";
    update.closedByID = uid;
    update.closedByName = actorName;
    update.closedAt = transitionTime;
  }
  update.status = status;
  update.resolutionReason = resolutionReason;
  update.revision = revision;
  transaction.update(sessionReference, update);
  if (status === "accepted") {
    transaction.update(pointerReference, {
      sessionStatus: "accepted",
      updatedAt: transitionTime,
    });
  } else {
    transaction.delete(pointerReference);
  }
  transaction.create(
    eventReference(household, `handoffSessions/${session.id}`, revision, action),
    handoffEvent({
      session,
      sourceRevision: revision,
      action,
      actorID: uid,
      actorName,
      handoffStatus: status,
      occurredAt: transitionTime,
    }),
  );
  return sessionResult({
    sessionID: session.id,
    sessionRevision: revision,
    sessionStatus: status,
    activeSessionID: status === "accepted" ? session.id : null,
    versionID: session.versionID,
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
  const keys = new Set(["householdID", "action", "clientMutationID"]);
  if (action === "offer") {
    keys.add("recipientID");
    keys.add("expectedHandoffRevision");
    keys.add("plannedStartMilliseconds");
    keys.add("plannedEndMilliseconds");
  } else {
    keys.add("sessionID");
    keys.add("expectedSessionRevision");
  }
  exactObject(data, keys);
  const input = {
    householdID: boundedID(data.householdID, "householdID"),
    action,
    clientMutationID: mutationID(data.clientMutationID),
    recipientID: null,
    expectedHandoffRevision: null,
    plannedStartMilliseconds: null,
    plannedEndMilliseconds: null,
    sessionID: null,
    expectedSessionRevision: null,
  };
  if (action === "offer") {
    input.recipientID = boundedID(data.recipientID, "recipientID");
    input.expectedHandoffRevision = positiveRevision(
      data.expectedHandoffRevision,
      "expectedHandoffRevision",
    );
    if (!Number.isSafeInteger(data.plannedStartMilliseconds) ||
        !Number.isSafeInteger(data.plannedEndMilliseconds) ||
        data.plannedStartMilliseconds >= data.plannedEndMilliseconds ||
        data.plannedEndMilliseconds - data.plannedStartMilliseconds >
          maximumDurationMilliseconds) {
      throw new HttpsError("invalid-argument", "The handoff window is invalid.");
    }
    input.plannedStartMilliseconds = data.plannedStartMilliseconds;
    input.plannedEndMilliseconds = data.plannedEndMilliseconds;
  } else {
    input.sessionID = boundedID(data.sessionID, "sessionID");
    input.expectedSessionRevision = positiveRevision(
      data.expectedSessionRevision,
      "expectedSessionRevision",
    );
  }
  return input;
}

function canonicalTemplate(data) {
  const keys = new Set([
    "schemaVersion", "careInstructions", "emergencyContactName",
    "emergencyContactPhone", "veterinaryHospitalName",
    "veterinaryHospitalPhone", "revision", "updatedByID", "updatedByName",
    "updatedAt",
  ]);
  if (data == null || Object.keys(data).length !== keys.size ||
      Object.keys(data).some((key) => !keys.has(key)) || data.schemaVersion !== 1 ||
      typeof data.careInstructions !== "string" || data.careInstructions.length > 1000 ||
      typeof data.emergencyContactName !== "string" || data.emergencyContactName.length > 80 ||
      typeof data.emergencyContactPhone !== "string" || data.emergencyContactPhone.length > 40 ||
      typeof data.veterinaryHospitalName !== "string" || data.veterinaryHospitalName.length > 100 ||
      typeof data.veterinaryHospitalPhone !== "string" || data.veterinaryHospitalPhone.length > 40 ||
      !Number.isInteger(data.revision) || data.revision < 1 ||
      data.revision > 999999 || typeof data.updatedByID !== "string" ||
      typeof data.updatedByName !== "string" || !(data.updatedAt instanceof Timestamp)) {
    throw new HttpsError(
      "failed-precondition",
      "The handoff template needs canonical repair.",
    );
  }
  return data;
}

function assertEquivalentVersion(versionID, stored, expected) {
  const keys = new Set([
    "schemaVersion", "id", "sourceHandoffRevision", "careInstructions",
    "emergencyContactName", "emergencyContactPhone", "veterinaryHospitalName",
    "veterinaryHospitalPhone", "updatedByID", "updatedByName", "updatedAt",
    "materializedAt",
  ]);
  const comparable = [...keys].filter((key) => key !== "materializedAt");
  if (stored == null || Object.keys(stored).length !== keys.size ||
      Object.keys(stored).some((key) => !keys.has(key)) || stored.id !== versionID ||
      !(stored.materializedAt instanceof Timestamp) ||
      comparable.some((key) => {
        const left = stored[key];
        const right = expected[key];
        if (left instanceof Timestamp || right instanceof Timestamp) {
          return !(left instanceof Timestamp && right instanceof Timestamp && left.isEqual(right));
        }
        return left !== right;
      })) {
    throw new HttpsError(
      "failed-precondition",
      "The immutable handoff version conflicts with its source revision.",
    );
  }
}

export function canonicalSessionPointer(data) {
  const keys = new Set([
    "schemaVersion", "sessionID", "sessionStatus", "plannedEndAt", "updatedAt",
  ]);
  if (data == null || Object.keys(data).length !== keys.size ||
      Object.keys(data).some((key) => !keys.has(key)) || data.schemaVersion !== 1 ||
      typeof data.sessionID !== "string" || data.sessionID.length === 0 ||
      data.sessionID.length > 128 || data.sessionID.includes("/") ||
      !["offered", "accepted"].includes(data.sessionStatus) ||
      !(data.plannedEndAt instanceof Timestamp) || !(data.updatedAt instanceof Timestamp)) {
    throw new HttpsError(
      "failed-precondition",
      "The active handoff state is malformed and must be reviewed.",
    );
  }
  return data;
}

export function canonicalSession(sessionID, data, ownerID) {
  const keys = new Set([
    "schemaVersion", "id", "versionID", "handoffRevisionSnapshot", "creatorID",
    "creatorName", "recipientID", "recipientName", "timeZoneIdentifierSnapshot",
    "plannedStartAt", "plannedEndAt", "status", "offeredAt", "acceptedByID",
    "acceptedByName", "acceptedAt", "declinedByID", "declinedByName", "declinedAt",
    "cancelledByID", "cancelledByName", "cancelledAt", "closedByID", "closedByName",
    "closedAt", "resolutionReason", "revision",
  ]);
  const actorPair = (id, name, at) =>
    (id == null && name == null && at == null) ||
    (storedID(id) && storedName(name) && at instanceof Timestamp);
  const versionID = Number.isInteger(data?.handoffRevisionSnapshot) &&
    data.handoffRevisionSnapshot >= 1 && data.handoffRevisionSnapshot <= 999999
    ? versionIDFor(data.handoffRevisionSnapshot)
    : null;
  if (data == null || Object.keys(data).length !== keys.size ||
      Object.keys(data).some((key) => !keys.has(key)) || data.schemaVersion !== 1 ||
      data.id !== sessionID || !storedID(sessionID) || data.versionID !== versionID ||
      !["offered", "accepted", "declined", "cancelled", "closed"].includes(data.status) ||
      !Number.isInteger(data.revision) || !(data.plannedStartAt instanceof Timestamp) ||
      !(data.plannedEndAt instanceof Timestamp) || !(data.offeredAt instanceof Timestamp) ||
      ["creatorID", "creatorName", "recipientID", "recipientName",
      ].some((key) => key.endsWith("ID") ? !storedID(data[key]) : !storedName(data[key])) ||
      data.creatorID === data.recipientID ||
      typeof data.timeZoneIdentifierSnapshot !== "string" ||
      !IANAZone.isValidZone(data.timeZoneIdentifierSnapshot) ||
      data.plannedStartAt.toMillis() >= data.plannedEndAt.toMillis() ||
      data.plannedEndAt.toMillis() - data.plannedStartAt.toMillis() >
        maximumDurationMilliseconds ||
      data.offeredAt.toMillis() >= data.plannedEndAt.toMillis() ||
      !actorPair(data.acceptedByID, data.acceptedByName, data.acceptedAt) ||
      !actorPair(data.declinedByID, data.declinedByName, data.declinedAt) ||
      !actorPair(data.cancelledByID, data.cancelledByName, data.cancelledAt) ||
      !actorPair(data.closedByID, data.closedByName, data.closedAt) ||
      ![null, "ownerRecovery"].includes(data.resolutionReason) ||
      (data.status === "offered" &&
        (data.revision !== 1 || data.acceptedAt != null || data.declinedAt != null ||
          data.cancelledAt != null || data.closedAt != null ||
          data.resolutionReason != null)) ||
      (data.status === "accepted" &&
        (data.revision !== 2 || data.acceptedByID !== data.recipientID ||
          data.acceptedAt.toMillis() < data.offeredAt.toMillis() ||
          data.acceptedAt.toMillis() >= data.plannedEndAt.toMillis() ||
          data.declinedAt != null || data.cancelledAt != null ||
          data.closedAt != null || data.resolutionReason != null)) ||
      (data.status === "declined" &&
        (data.revision !== 2 || data.declinedByID !== data.recipientID ||
          data.declinedAt.toMillis() < data.offeredAt.toMillis() ||
          data.acceptedAt != null || data.cancelledAt != null ||
          data.closedAt != null || data.resolutionReason != null)) ||
      (data.status === "cancelled" &&
        (data.revision !== 2 || data.cancelledAt == null || data.acceptedAt != null ||
          data.cancelledAt.toMillis() < data.offeredAt.toMillis() ||
          data.declinedAt != null || data.closedAt != null ||
          (data.resolutionReason == null
            ? data.cancelledByID !== data.creatorID
            : data.cancelledByID !== ownerID || data.cancelledByID === data.creatorID))) ||
      (data.status === "closed" &&
        (data.revision !== 3 || data.acceptedByID !== data.recipientID ||
          data.acceptedAt.toMillis() < data.offeredAt.toMillis() ||
          data.acceptedAt.toMillis() >= data.plannedEndAt.toMillis() ||
          data.closedAt == null || data.closedAt.toMillis() < data.acceptedAt.toMillis() ||
          data.declinedAt != null || data.cancelledAt != null ||
          (data.resolutionReason == null
            ? ![data.creatorID, data.recipientID].includes(data.closedByID)
            : data.closedByID !== ownerID ||
              [data.creatorID, data.recipientID].includes(data.closedByID))))) {
    throw new HttpsError(
      "failed-precondition",
      "The handoff session is malformed and must be reviewed.",
    );
  }
  return data;
}

function handoffEvent({
  session,
  sourceRevision,
  action,
  actorID,
  actorName,
  handoffStatus,
  occurredAt,
}) {
  return v2Event({
    sourceType: "handoffSession",
    sourceID: session.id,
    sourceRevision,
    action,
    actorID,
    actorName,
    handoffCreatorID: session.creatorID,
    handoffCreatorName: session.creatorName,
    handoffRecipientID: session.recipientID,
    handoffRecipientName: session.recipientName,
    handoffStatus,
    occurredAt,
  });
}

function sessionResult({
  sessionID,
  sessionRevision,
  sessionStatus,
  activeSessionID,
  versionID,
}) {
  return {
    sessionID,
    sessionRevision,
    sessionStatus,
    activeSessionID,
    versionID,
  };
}

function versionIDFor(revision) {
  if (revision > 999999) {
    throw new HttpsError("failed-precondition", "The handoff revision is unsupported.");
  }
  return `v${String(revision).padStart(6, "0")}`;
}

function boundedStoredID(value, field) {
  if (typeof value !== "string" || value.length === 0 ||
      value.length > 128 || value.includes("/")) {
    throw new HttpsError("failed-precondition", `${field} needs repair.`);
  }
  return value;
}

function storedID(value) {
  return typeof value === "string" && value.length > 0 &&
    value.length <= 128 && !value.includes("/");
}

function storedName(value) {
  return typeof value === "string" && value.trim().length > 0 &&
    value.length <= 50;
}

function requireStatus(session, expected) {
  if (session.status !== expected) {
    throw new HttpsError("failed-precondition", "The handoff session already changed.");
  }
}

function wrongActor() {
  return new HttpsError("permission-denied", "This member cannot perform that action.");
}
