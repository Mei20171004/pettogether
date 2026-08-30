import { FieldPath, FieldValue, Timestamp } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import {
  boundedID,
  exactObject,
  fingerprint,
  lt5CallableOptions,
  mutationID,
  receiptReference,
} from "./lt5_common.js";
import {
  canonicalPointer,
  canonicalTransfer,
} from "./task_responsibility.js";
import {
  canonicalSession,
  canonicalSessionPointer,
} from "./handoff_sessions.js";

const tokenPageSize = 450;
const claimPageSize = 100;
const purgePageSize = 300;

// Leaving a household removes the member's notification records for it. Without
// this, a rejoining member would keep documents from their previous membership,
// and the epoch-scoped list rules could not authorize an empty collection for a
// member who has never received a notification.
export const PURGED_NOTIFICATION_COLLECTIONS = Object.freeze([
  "notificationInbox",
  "notificationDeliveries",
  "notificationDigests",
  "notificationDeliveryManifests",
]);

export function createMembershipCallables(db) {
  return {
    leaveHousehold: onCall(
      lt5CallableOptions,
      (request) => leaveHouseholdAt(db, request, new Date()),
    ),
  };
}

export async function leaveHouseholdAt(db, request, receivedAt = new Date()) {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in before leaving a household.");
  }
  if (!(receivedAt instanceof Date) || Number.isNaN(receivedAt.getTime())) {
    throw new HttpsError("internal", "The server clock is unavailable.");
  }
  const input = parseInput(request.data);
  const household = db.collection("households").doc(input.householdID);
  const member = household.collection("members").doc(uid);
  const receipt = receiptReference(
    household,
    "membershipMutationReceipts",
    uid,
    input.clientMutationID,
  );
  const state = household.collection("membershipRevocations").doc(uid);
  const expectedFingerprint = fingerprint(input);

  const preparation = await db.runTransaction(async (transaction) => {
    const [householdSnapshot, memberSnapshot, receiptSnapshot, stateSnapshot] =
      await Promise.all([
        transaction.get(household),
        transaction.get(member),
        transaction.get(receipt),
        transaction.get(state),
      ]);
    const existingState = stateSnapshot.exists
      ? canonicalRevocationState(uid, stateSnapshot.data())
      : null;
    const existingReceipt = receiptSnapshot.exists
      ? canonicalMembershipReceipt(uid, receiptSnapshot.data())
      : null;
    if (existingReceipt?.status === "complete" && !memberSnapshot.exists) {
      return { result: existingReceipt.result, existing: true };
    }
    if (existingState != null) {
      return { result: null, existing: true };
    }
    if (existingReceipt != null) {
      throw new HttpsError(
        "invalid-argument",
        "clientMutationID was already used for another request.",
      );
    }
    if (!householdSnapshot.exists || !memberSnapshot.exists) {
      throw new HttpsError("permission-denied", "Household membership is required.");
    }
    await assertCanLeave({
      transaction,
      household,
      householdSnapshot,
      uid,
      now: Timestamp.fromDate(receivedAt),
    });
    const serverTime = FieldValue.serverTimestamp();
    const statePayload = {
      schemaVersion: 1,
      uid,
      status: "draining",
      initiatingMutationID: input.clientMutationID,
      initiatingFingerprint: expectedFingerprint,
      receiptID: receipt.id,
      tokenCursor: null,
      purgeCollection: null,
      purgeCursor: null,
      disabledInstallationCount: 0,
      result: null,
      createdAt: serverTime,
      updatedAt: serverTime,
    };
    if (existingState == null) transaction.create(state, statePayload);
    else transaction.set(state, statePayload);
    transaction.create(receipt, {
      schemaVersion: 1,
      uid,
      fingerprint: expectedFingerprint,
      action: "leaveHousehold",
      status: "revoking",
      result: null,
      createdAt: serverTime,
      updatedAt: serverTime,
    });
    return { result: null, existing: false };
  });
  if (preparation.result != null) {
    return { ...preparation.result, existing: true };
  }

  while (true) {
    await revokeMembershipAfterClaims({
      db,
      household,
      member,
      state,
      uid,
      receivedAt,
    });
    const outcome = await disableHouseholdTokens({
      db,
      householdID: input.householdID,
      uid,
      state,
      household,
      member,
    });
    if (!outcome.restart) {
      const purged = await purgeHouseholdNotifications({
        db,
        householdID: input.householdID,
        uid,
        state,
        household,
      });
      return { ...purged.result, existing: preparation.existing };
    }
  }
}

async function revokeMembershipAfterClaims({
  db,
  household,
  member,
  state,
  uid,
  receivedAt,
}) {
  while (true) {
    const outcome = await db.runTransaction(async (transaction) => {
    const [stateSnapshot, householdSnapshot, memberSnapshot, claims] =
      await Promise.all([
        transaction.get(state),
        transaction.get(household),
        transaction.get(member),
        transaction.get(
          state.collection("notificationClaims")
            .orderBy(FieldPath.documentId())
            .limit(claimPageSize),
        ),
      ]);
    const current = canonicalRevocationState(uid, stateSnapshot.data());
    // A retry after a crash must never move a later phase backwards.
    if (current.status !== "draining") return;
    const now = Timestamp.fromDate(receivedAt);
    const activeClaims = [];
    const expiredClaims = [];
    for (const claim of claims.docs) {
      const leaseUntil = claim.data()?.leaseUntil;
      if (!(leaseUntil instanceof Timestamp)) {
        throw new HttpsError(
          "failed-precondition",
          "Notification delivery state needs review before leaving.",
        );
      }
      if (leaseUntil.toMillis() > now.toMillis()) activeClaims.push(claim.id);
      else expiredClaims.push(claim.ref);
    }
    if (activeClaims.length > 0) {
      throw new HttpsError(
        "aborted",
        "Notification revocation is still in progress. Retry shortly.",
        { retryable: true },
      );
    }
    if (claims.size === claimPageSize) {
      for (const expiredClaim of expiredClaims) transaction.delete(expiredClaim);
      return { retry: true };
    }
    if (memberSnapshot.exists) {
      await assertCanLeave({
        transaction,
        household,
        householdSnapshot,
        uid,
        now,
      });
      for (const expiredClaim of expiredClaims) transaction.delete(expiredClaim);
      transaction.delete(member);
    } else {
      for (const expiredClaim of expiredClaims) transaction.delete(expiredClaim);
    }
    transaction.update(state, {
      status: "revokingTokens",
      tokenCursor: null,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { retry: false };
    });
    if (!outcome?.retry) return;
  }
}

async function disableHouseholdTokens({
  db,
  householdID,
  uid,
  state,
  household,
  member,
}) {
  while (true) {
    const page = await db.runTransaction(async (transaction) => {
      const preference = db.doc(
        `users/${uid}/householdNotificationPreferences/${householdID}`,
      );
      const inboxCursor = db.doc(
        `users/${uid}/notificationInboxState/${householdID}`,
      );
      const [stateSnapshot, memberSnapshot, preferenceSnapshot,
        inboxCursorSnapshot] = await Promise.all([
        transaction.get(state),
        transaction.get(member),
        transaction.get(preference),
        transaction.get(inboxCursor),
      ]);
      const current = canonicalRevocationState(uid, stateSnapshot.data());
      if (current.status === "purgingNotifications") {
        return { done: true, result: null, restart: false };
      }
      if (current.status !== "revokingTokens") {
        throw new HttpsError(
          "aborted",
          "Membership revocation is still in progress. Retry shortly.",
          { retryable: true },
        );
      }
      let query = db.collection("users").doc(uid).collection("notificationTokens")
        .where("householdID", "==", householdID)
        .orderBy(FieldPath.documentId())
        .limit(tokenPageSize);
      if (current.tokenCursor != null) query = query.startAfter(current.tokenCursor);
      const tokens = await transaction.get(query);
      if (!tokens.empty) {
        let disabled = 0;
        for (const token of tokens.docs) {
          if (token.data()?.enabled === true) {
            disabled += 1;
            transaction.update(token.ref, {
              enabled: false,
              updatedAt: FieldValue.serverTimestamp(),
            });
          }
        }
        transaction.update(state, {
          tokenCursor: tokens.docs.at(-1).id,
          disabledInstallationCount: FieldValue.increment(disabled),
          updatedAt: FieldValue.serverTimestamp(),
        });
        return { done: false, result: null };
      }
      if (memberSnapshot.exists) {
        transaction.update(state, {
          status: "draining",
          tokenCursor: null,
          updatedAt: FieldValue.serverTimestamp(),
        });
        return { done: true, result: null, restart: true };
      }
      transaction.update(state, {
        status: "purgingNotifications",
        tokenCursor: null,
        purgeCollection: PURGED_NOTIFICATION_COLLECTIONS[0],
        purgeCursor: null,
        updatedAt: FieldValue.serverTimestamp(),
      });
      if (preferenceSnapshot.exists) transaction.delete(preference);
      if (inboxCursorSnapshot.exists) transaction.delete(inboxCursor);
      return { done: true, result: null, restart: false };
    });
    if (page.done) return page;
  }
}

async function purgeHouseholdNotifications({
  db,
  householdID,
  uid,
  state,
  household,
}) {
  while (true) {
    const page = await db.runTransaction(async (transaction) => {
      const stateSnapshot = await transaction.get(state);
      const current = canonicalRevocationState(uid, stateSnapshot.data());
      if (current.status !== "purgingNotifications") {
        throw new HttpsError(
          "aborted",
          "Membership revocation is still in progress. Retry shortly.",
          { retryable: true },
        );
      }
      const collectionName = current.purgeCollection;
      let query = db.collection("users").doc(uid).collection(collectionName)
        .where("householdID", "==", householdID)
        .orderBy(FieldPath.documentId())
        .limit(purgePageSize);
      if (current.purgeCursor != null) {
        query = query.startAfter(current.purgeCursor);
      }
      const documents = await transaction.get(query);
      if (!documents.empty) {
        for (const document of documents.docs) transaction.delete(document.ref);
        transaction.update(state, {
          purgeCursor: documents.docs.at(-1).id,
          updatedAt: FieldValue.serverTimestamp(),
        });
        return { done: false, result: null };
      }
      const nextIndex =
        PURGED_NOTIFICATION_COLLECTIONS.indexOf(collectionName) + 1;
      if (nextIndex < PURGED_NOTIFICATION_COLLECTIONS.length) {
        transaction.update(state, {
          purgeCollection: PURGED_NOTIFICATION_COLLECTIONS[nextIndex],
          purgeCursor: null,
          updatedAt: FieldValue.serverTimestamp(),
        });
        return { done: false, result: null };
      }
      const result = {
        householdID,
        left: true,
        disabledInstallationCount: current.disabledInstallationCount,
      };
      const receipt = household.collection("membershipMutationReceipts")
        .doc(current.receiptID);
      transaction.update(receipt, {
        status: "complete",
        result,
        updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.delete(state);
      return { done: true, result };
    });
    if (page.done) return page;
  }
}

async function assertCanLeave({
  transaction,
  household,
  householdSnapshot,
  uid,
  now,
}) {
  if (!householdSnapshot.exists) {
    throw new HttpsError("permission-denied", "Household membership is required.");
  }
  if (householdSnapshot.data()?.ownerID === uid) throw blocker("owner");
  const assignedTasks = household.collection("tasks").where("assigneeID", "==", uid);
  const pendingTransfers = household.collection("taskResponsibilityTransfers")
    .where("status", "==", "pending");
  const transferStates = household.collection("taskResponsibilityState");
  const activeSessions = household.collection("handoffSessions")
    .where("status", "in", ["offered", "accepted"]);
  const handoffPointer = household.collection("handoff").doc("sessionState");
  const medicationResponsibilities = household.collection("medicationOccurrences")
    .where("responsibleByID", "==", uid)
    .where("outcomeStatus", "==", "unresolved")
    .orderBy(FieldPath.documentId())
    .limit(101);
  const [taskSnapshot, transferSnapshot, transferStateSnapshot, sessionSnapshot,
    pointerSnapshot, medicationResponsibilitySnapshot] =
    await Promise.all([
      transaction.get(assignedTasks),
      transaction.get(pendingTransfers),
      transaction.get(transferStates),
      transaction.get(activeSessions),
      transaction.get(handoffPointer),
      transaction.get(medicationResponsibilities),
    ]);
  if (taskSnapshot.docs.some((document) => document.data()?.status === "claimed")) {
    throw blocker("assignedTask");
  }
  assertMedicationResponsibilitiesCanLeave({
    snapshot: medicationResponsibilitySnapshot,
    uid,
    now,
  });
  const pendingByTask = new Map();
  try {
    for (const document of transferSnapshot.docs) {
      const transfer = canonicalTransfer(document.id, document.data());
      if (transfer.status !== "pending" || pendingByTask.has(transfer.taskID)) {
        throw new Error("duplicate pending transfer");
      }
      pendingByTask.set(transfer.taskID, transfer);
      if (transfer.requestedByID === uid || transfer.consentByID === uid ||
          transfer.responsibilityFromID === uid || transfer.responsibilityToID === uid) {
        throw blocker("pendingTransfer");
      }
    }
    if (transferStateSnapshot.size !== pendingByTask.size) {
      throw blocker("pendingTransfer");
    }
    for (const document of transferStateSnapshot.docs) {
      const pointer = canonicalPointer(document.id, document.data());
      const transfer = pendingByTask.get(document.id);
      if (transfer == null || pointer.transferID !== transfer.id ||
          pointer.taskRevisionAtProposal !== transfer.taskRevisionAtProposal ||
          !pointer.createdAt.isEqual(transfer.createdAt)) {
        throw blocker("pendingTransfer");
      }
    }
  } catch {
    throw blocker("pendingTransfer");
  }
  try {
    const sessions = sessionSnapshot.docs.map((document) =>
      canonicalSession(
        document.id,
        document.data(),
        householdSnapshot.data()?.ownerID,
      ));
    if (sessions.some((session) =>
      session.creatorID === uid || session.recipientID === uid)) {
      throw blocker("activeHandoff");
    }
    if (sessions.length === 0) {
      if (pointerSnapshot.exists) throw blocker("activeHandoff");
      return;
    }
    if (sessions.length !== 1 || !pointerSnapshot.exists) {
      throw blocker("activeHandoff");
    }
    const pointer = canonicalSessionPointer(pointerSnapshot.data());
    if (pointer.sessionID !== sessions[0].id ||
        pointer.sessionStatus !== sessions[0].status ||
        !pointer.plannedEndAt.isEqual(sessions[0].plannedEndAt)) {
      throw blocker("activeHandoff");
    }
  } catch {
    throw blocker("activeHandoff");
  }
}

function assertMedicationResponsibilitiesCanLeave({ snapshot, uid, now }) {
  if (!(now instanceof Timestamp)) {
    throw new HttpsError("internal", "The server clock is unavailable.");
  }
  if (snapshot.size > 100) throw blocker("tooManyMedicationResponsibilities");
  const keys = new Set([
    "schemaVersion", "id", "medicationID", "scheduleVersionID",
    "scheduleVersion", "slotID", "localDate", "dueAt",
    "timeZoneIdentifier", "petID", "petName", "medicationName", "doseText",
    "instructions", "responsibilityStatus", "responsibleByID",
    "responsibleByName", "claimedAt", "outcomeStatus", "outcomeByID",
    "outcomeByName", "outcomeAt", "skippedReasonCode", "skippedReasonNote",
    "materializedAt", "revision",
  ]);
  const safeBefore = now.toMillis() - 45 * 60 * 1000;
  for (const document of snapshot.docs) {
    const data = document.data();
    if (data == null || Object.keys(data).length !== keys.size ||
        Object.keys(data).some((key) => !keys.has(key)) ||
        data.schemaVersion !== 1 || data.id !== document.id ||
        data.responsibilityStatus !== "claimed" ||
        data.responsibleByID !== uid || data.outcomeStatus !== "unresolved" ||
        !(data.dueAt instanceof Timestamp) ||
        !Number.isInteger(data.revision) || data.revision < 1) {
      throw blocker("medicationResponsibilityNeedsRepair");
    }
    if (data.dueAt.toMillis() > safeBefore) {
      throw blocker("unresolvedMedicationResponsibility");
    }
  }
}

function canonicalRevocationState(uid, data) {
  const keys = new Set([
    "schemaVersion", "uid", "status", "initiatingMutationID",
    "initiatingFingerprint", "receiptID", "tokenCursor",
    "purgeCollection", "purgeCursor",
    "disabledInstallationCount", "result", "createdAt", "updatedAt",
  ]);
  const validResult = data?.result == null ||
    (typeof data.result.householdID === "string" && data.result.householdID.length > 0 &&
      data.result.left === true &&
      data.result.disabledInstallationCount === data.disabledInstallationCount &&
      Object.keys(data.result).length === 3);
  if (data == null || Object.keys(data).length !== keys.size ||
      Object.keys(data).some((key) => !keys.has(key)) ||
      data.schemaVersion !== 1 || data.uid !== uid ||
      !["draining", "revokingTokens", "purgingNotifications"]
        .includes(data.status) ||
      !validStoredID(data.initiatingMutationID) ||
      typeof data.initiatingFingerprint !== "string" ||
      !/^[a-f0-9]{64}$/.test(data.initiatingFingerprint) ||
      !validStoredID(data.receiptID) ||
      (data.tokenCursor != null && !validCursor(data.tokenCursor)) ||
      (data.purgeCollection != null &&
        !PURGED_NOTIFICATION_COLLECTIONS.includes(data.purgeCollection)) ||
      (data.purgeCursor != null && !validCursor(data.purgeCursor)) ||
      (data.status !== "purgingNotifications" && data.purgeCollection != null) ||
      !Number.isInteger(data.disabledInstallationCount) ||
      data.disabledInstallationCount < 0 || !validResult ||
      !(data.createdAt instanceof Timestamp) || !(data.updatedAt instanceof Timestamp) ||
      data.result != null) {
    throw new HttpsError(
      "failed-precondition",
      "The membership revocation state needs review.",
    );
  }
  return data;
}

function canonicalMembershipReceipt(uid, data) {
  const keys = new Set([
    "schemaVersion", "uid", "fingerprint", "action", "status", "result",
    "createdAt", "updatedAt",
  ]);
  const validResult = data?.result == null ||
    (typeof data.result.householdID === "string" && data.result.householdID.length > 0 &&
      data.result.left === true &&
      Number.isInteger(data.result.disabledInstallationCount) &&
      data.result.disabledInstallationCount >= 0 &&
      Object.keys(data.result).length === 3);
  if (data == null || Object.keys(data).length !== keys.size ||
      Object.keys(data).some((key) => !keys.has(key)) ||
      data.schemaVersion !== 1 || data.uid !== uid ||
      typeof data.fingerprint !== "string" || !/^[a-f0-9]{64}$/.test(data.fingerprint) ||
      data.action !== "leaveHousehold" ||
      !["revoking", "complete"].includes(data.status) || !validResult ||
      !(data.createdAt instanceof Timestamp) || !(data.updatedAt instanceof Timestamp) ||
      (data.status === "revoking" && data.result != null) ||
      (data.status === "complete" && data.result == null)) {
    throw new HttpsError(
      "failed-precondition",
      "The membership receipt needs review.",
    );
  }
  return data;
}

function parseInput(data) {
  exactObject(data, new Set(["householdID", "clientMutationID"]));
  return {
    householdID: boundedID(data.householdID, "householdID"),
    clientMutationID: mutationID(data.clientMutationID),
  };
}

function validStoredID(value) {
  return typeof value === "string" && value.length > 0 &&
    value.length <= 128 && !value.includes("/");
}

function validCursor(value) {
  return typeof value === "string" && value.length > 0 &&
    value.length <= 1500 && !value.includes("/");
}

function blocker(blockerCode) {
  const messages = {
    owner: "Transfer ownership before leaving this household.",
    assignedTask: "Release or complete assigned care before leaving.",
    pendingTransfer: "Resolve pending responsibility requests before leaving.",
    activeHandoff: "Resolve the active handoff obligation before leaving.",
    unresolvedMedicationResponsibility:
      "Resolve the current medication responsibility before leaving.",
    medicationResponsibilityNeedsRepair:
      "Medication responsibility needs review before leaving.",
    tooManyMedicationResponsibilities:
      "Too many medication responsibilities need review before leaving.",
  };
  return new HttpsError(
    "failed-precondition",
    messages[blockerCode],
    { blockerCode },
  );
}
