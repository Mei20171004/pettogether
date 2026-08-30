import { createHash } from "node:crypto";

import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

export const lt5CallableOptions = {
  enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
};

export function exactObject(data, allowedKeys) {
  if (data == null || typeof data !== "object" || Array.isArray(data) ||
      Object.keys(data).length !== allowedKeys.size ||
      Object.keys(data).some((key) => !allowedKeys.has(key))) {
    throw new HttpsError("invalid-argument", "The request shape is invalid.");
  }
  return data;
}

export function boundedID(value, field) {
  if (typeof value !== "string" || value.length === 0 ||
      value.length > 128 || value.includes("/")) {
    throw new HttpsError("invalid-argument", `${field} is invalid.`);
  }
  return value;
}

export function positiveRevision(value, field, { allowZero = false } = {}) {
  if (!Number.isInteger(value) || value < (allowZero ? 0 : 1)) {
    throw new HttpsError("invalid-argument", `${field} is invalid.`);
  }
  return value;
}

export function mutationID(value) {
  return boundedID(value, "clientMutationID");
}

export function validName(value, field) {
  if (typeof value !== "string" || value.trim().length === 0 || value.length > 50) {
    throw new HttpsError("failed-precondition", `${field} needs repair.`);
  }
  return value;
}

export function digest(value) {
  return createHash("sha256").update(value).digest("hex");
}

export function fingerprint(input) {
  return digest(stableJSON(input));
}

export function receiptReference(household, collectionID, uid, clientMutationID) {
  return household.collection(collectionID).doc(digest(`${uid}:${clientMutationID}`));
}

export function readReceipt(snapshot, expectedFingerprint, action) {
  if (!snapshot.exists) return null;
  const data = snapshot.data();
  if (data?.schemaVersion !== 1 || data?.fingerprint !== expectedFingerprint ||
      data?.action !== action || data?.result == null ||
      typeof data.result !== "object" || Array.isArray(data.result)) {
    throw new HttpsError(
      "invalid-argument",
      "clientMutationID was already used for another request.",
    );
  }
  return data.result;
}

export function receiptPayload({ uid, expectedFingerprint, action, result }) {
  return {
    schemaVersion: 1,
    uid,
    fingerprint: expectedFingerprint,
    action,
    result,
    createdAt: FieldValue.serverTimestamp(),
  };
}

export function eventReference(household, sourcePath, sourceRevision, action) {
  const id = digest(`${sourcePath}|${sourceRevision}|${action}`);
  return household.collection("collaborationEvents").doc(id);
}

export function v2Event({
  sourceType,
  sourceID,
  sourceRevision,
  action,
  actorID,
  actorName,
  responsibilityFromID = null,
  responsibilityFromName = null,
  responsibilityToID = null,
  responsibilityToName = null,
  handoffCreatorID = null,
  handoffCreatorName = null,
  handoffRecipientID = null,
  handoffRecipientName = null,
  requestID = null,
  petID = null,
  petName = null,
  taskTitle = null,
  taskCategory = null,
  taskPriority = null,
  taskDueTime = null,
  stateAfter = null,
  handoffStatus = null,
  occurredAt = FieldValue.serverTimestamp(),
}) {
  return {
    schemaVersion: 2,
    sourceType,
    sourceID,
    sourceRevision,
    action,
    actorID,
    actorName,
    responsibilityFromID,
    responsibilityFromName,
    responsibilityToID,
    responsibilityToName,
    handoffCreatorID,
    handoffCreatorName,
    handoffRecipientID,
    handoffRecipientName,
    requestID,
    petID,
    petName,
    taskTitle,
    taskCategory,
    taskPriority,
    taskDueTime,
    stateAfter,
    handoffStatus,
    occurredAt,
    recordedAt: FieldValue.serverTimestamp(),
  };
}

export function timestamp(value, field) {
  if (!(value instanceof Timestamp)) {
    throw new HttpsError("failed-precondition", `${field} needs repair.`);
  }
  return value;
}

export function stale(details) {
  throw new HttpsError(
    "aborted",
    "The source changed. Refresh and try again.",
    details,
  );
}

function stableJSON(value) {
  if (Array.isArray(value)) return `[${value.map(stableJSON).join(",")}]`;
  if (value != null && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) =>
      `${JSON.stringify(key)}:${stableJSON(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}
