import { createHash, createHmac, randomUUID } from "node:crypto";

import { FieldPath, Timestamp } from "firebase-admin/firestore";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { HttpsError } from "firebase-functions/v2/https";
import { DateTime } from "luxon";

import {
  boundedID,
  exactObject,
  fingerprint,
  lt5CallableOptions,
  mutationID,
} from "./lt5_common.js";
import { canonicalSession } from "./handoff_sessions.js";
import { canonicalTransfer } from "./task_responsibility.js";

const preferenceKeys = new Set([
  "householdID", "expectedRevision", "clientMutationID",
  "medicationRemindersEnabled", "assignmentAlertsEnabled",
  "urgentAlertsEnabled", "pushEnabled", "backupForMemberIDs",
  "quietHoursEnabled", "quietStartMinute", "quietEndMinute",
  "summaryEnabled", "summaryMinute",
]);
const preferenceStoredKeys = new Set([
  "schemaVersion", "uid", "householdID", "memberJoinedAtSnapshot",
  "medicationRemindersEnabled", "assignmentAlertsEnabled",
  "urgentAlertsEnabled", "pushEnabled", "backupForMemberIDs",
  "quietHoursEnabled", "quietStartMinute", "quietEndMinute",
  "summaryEnabled", "summaryMinute", "timeZoneIdentifierSnapshot",
  "revision", "createdAt", "updatedAt",
]);
const inboxKeys = new Set([
  "schemaVersion", "id", "householdID", "recipientID",
  "recipientJoinedAtSnapshot", "category", "level", "routeReason",
  "sourceType", "sourceID", "sourcePath", "sourceRevision",
  "preferenceRevision", "status", "availableAt", "expiresAt",
  "nextDispatchAt", "coalescingKey", "cancelReason", "cancelledAt",
  "createdAt", "updatedAt",
]);
const categories = new Set(["medication", "assignment", "urgent", "summary"]);
const levels = new Set([
  "due", "overdue15", "overdue30", "directAssignment",
  "responsibilityProposal", "handoffOffer", "urgentUnclaimed",
  "burstSummary", "dailySummary",
]);
const routeReasons = new Set([
  "responsible", "backup", "medicationOptIn", "directTarget",
  "handoffRecipient", "urgentOptIn", "summary",
]);
const sourceTypes = new Set([
  "medicationOccurrence", "task", "taskResponsibilityTransfer",
  "handoffSession", "notificationDigest",
]);
const canonicalInstallationID = /^[a-f0-9]{64}$/;
const maxInstallations = 1000;
const manifestBatchSize = 400;

export function createNotificationV2Functions(db, {
  projectID,
  keyRing = new Map(),
  provider = null,
} = {}) {
  const activeBindingKeyVersion = positiveKeyVersion(keyRing);
  const sourceHandler = (sourceType) => async (event) => {
    const householdID = event.params.householdID;
    const sourceID = event.params.sourceID;
    return generateNotificationSourceAt({
      db, householdID, sourceType, sourceID, projectID,
      bindingKeyVersion: activeBindingKeyVersion,
    });
  };
  return {
    setHouseholdNotificationPreferences: onCall(
      lt5CallableOptions,
      (request) => setHouseholdNotificationPreferencesAt(db, request),
    ),
    resetMalformedNotificationPreferences: onCall(
      lt5CallableOptions,
      (request) => resetMalformedNotificationPreferencesAt(db, request),
    ),
    resolveNotificationInboxRoute: onCall(
      lt5CallableOptions,
      (request) => resolveNotificationInboxRouteAt(db, request),
    ),
    expireNotificationInbox: onSchedule(
      { schedule: "every 15 minutes", timeZone: "UTC", retryCount: 3 },
      () => expireNotificationInboxAt(db),
    ),
    recoverNotificationDigests: onSchedule(
      { schedule: "every 5 minutes", timeZone: "UTC", retryCount: 3 },
      () => recoverNotificationDigestsAt({
        db, projectID, bindingKeyVersion: activeBindingKeyVersion,
      }),
    ),
    recoverNotificationManifests: onSchedule(
      { schedule: "every 5 minutes", timeZone: "UTC", retryCount: 3 },
      () => recoverNotificationManifestsAt({ db }),
    ),
    dispatchNotificationV2: onSchedule(
      { schedule: "every 5 minutes", timeZone: "UTC", retryCount: 3 },
      () => dispatchReadyNotificationDeliveriesAt({
        db, projectID, keyRing, provider,
      }),
    ),
    generateMedicationNotificationIntentsV2: onSchedule(
      { schedule: "every 5 minutes", timeZone: "UTC", retryCount: 3 },
      () => generateMedicationNotificationIntentsAt({
        db, projectID, bindingKeyVersion: activeBindingKeyVersion,
      }),
    ),
    onTaskNotificationSourceWritten: onDocumentWritten(
      "households/{householdID}/tasks/{sourceID}",
      sourceHandler("task"),
    ),
    onTransferNotificationSourceWritten: onDocumentWritten(
      "households/{householdID}/taskResponsibilityTransfers/{sourceID}",
      sourceHandler("taskResponsibilityTransfer"),
    ),
    onHandoffNotificationSourceWritten: onDocumentWritten(
      "households/{householdID}/handoffSessions/{sourceID}",
      sourceHandler("handoffSession"),
    ),
    onMedicationOccurrenceNotificationSourceWritten: onDocumentWritten(
      "households/{householdID}/medicationOccurrences/{sourceID}",
      sourceHandler("medicationOccurrence"),
    ),
  };
}

export async function readNotificationGatesAt(db, projectID) {
  try {
    const [generationSnapshot, dispatchSnapshot] = await Promise.all([
      db.doc("systemConfig/notificationIntentGenerationV2").get(),
      db.doc("systemConfig/notificationDispatchV2").get(),
    ]);
    const generation = canonicalGate(generationSnapshot.data(), projectID);
    const dispatch = canonicalGate(dispatchSnapshot.data(), projectID);
    return { generation, dispatch, enabled: generation != null && dispatch != null };
  } catch {
    return { generation: null, dispatch: null, enabled: false };
  }
}

export async function setHouseholdNotificationPreferencesAt(
  db,
  request,
  receivedAt = new Date(),
) {
  const uid = requireAuth(request);
  const input = parsePreferenceInput(request.data);
  const now = trustedTimestamp(receivedAt);
  return writePreferenceMutation({ db, uid, input, now, action: "set" });
}

export async function resetMalformedNotificationPreferencesAt(
  db,
  request,
  receivedAt = new Date(),
) {
  const uid = requireAuth(request);
  exactObject(request.data, new Set(["householdID", "clientMutationID"]));
  const input = {
    householdID: boundedID(request.data.householdID, "householdID"),
    clientMutationID: mutationID(request.data.clientMutationID),
  };
  const now = trustedTimestamp(receivedAt);
  return writePreferenceMutation({ db, uid, input, now, action: "reset" });
}

async function writePreferenceMutation({ db, uid, input, now, action }) {
  const household = db.doc(`households/${input.householdID}`);
  const member = household.collection("members").doc(uid);
  const preference = db.doc(
    `users/${uid}/householdNotificationPreferences/${input.householdID}`,
  );
  const requestFingerprint = fingerprint({
    action,
    ...Object.fromEntries(
      Object.entries(input).filter(([key]) => key !== "clientMutationID"),
    ),
  });
  return db.runTransaction(async (transaction) => {
    const [householdSnapshot, memberSnapshot, preferenceSnapshot] =
      await Promise.all([
        transaction.get(household),
        transaction.get(member),
        transaction.get(preference),
      ]);
    if (!householdSnapshot.exists || !memberSnapshot.exists) {
      throw new HttpsError("permission-denied", "Household membership is required.");
    }
    const joinedAt = memberSnapshot.data()?.joinedAt;
    if (!(joinedAt instanceof Timestamp)) {
      throw new HttpsError("failed-precondition", "Membership needs repair.");
    }
    const receiptID = sha256(
      `${uid}:${joinedAt.seconds}:${joinedAt.nanoseconds}:${input.clientMutationID}`,
    );
    const receipt = db.doc(
      `users/${uid}/notificationPreferenceMutationReceipts/${receiptID}`,
    );
    const receiptSnapshot = await transaction.get(receipt);
    if (receiptSnapshot.exists) {
      const stored = canonicalPreferenceReceipt({
        uid,
        householdID: input.householdID,
        joinedAt,
        action,
        fingerprint: requestFingerprint,
        data: receiptSnapshot.data(),
      });
      return { ...stored.result, existing: true };
    }

    const householdData = householdSnapshot.data();
    const zone = householdData?.timeZoneIdentifier;
    if (!validTimeZone(zone)) {
      throw new HttpsError("failed-precondition", "Household timezone needs repair.");
    }
    const current = preferenceSnapshot.exists
      ? canonicalCurrentPreference(
        preferenceSnapshot.data(), uid, input.householdID, joinedAt, zone,
      )
      : null;
    let next;
    if (action === "set") {
      if (preferenceSnapshot.exists && current == null) {
        throw new HttpsError(
          "failed-precondition",
          "Notification preferences need repair.",
          { reason: "preferencesMalformed", currentRevision: safeRevision(
            preferenceSnapshot.data()?.revision,
          ) },
        );
      }
      const currentRevision = current?.revision ?? 0;
      if (input.expectedRevision !== currentRevision) {
        throw new HttpsError(
          "aborted",
          "Notification preferences changed. Refresh and retry.",
          { reason: "revisionMismatch", currentRevision },
        );
      }
      await validateBackupMembers({
        transaction,
        household,
        uid,
        memberIDs: input.backupForMemberIDs,
      });
      next = preferencePayload({
        uid,
        input,
        joinedAt,
        zone,
        revision: currentRevision + 1,
        createdAt: current?.createdAt ?? now,
        now,
      });
    } else {
      if (current != null) {
        throw new HttpsError(
          "failed-precondition",
          "Notification preferences are already canonical.",
          { reason: "preferencesAlreadyCanonical", currentRevision: current.revision },
        );
      }
      if (!preferenceSnapshot.exists) {
        throw new HttpsError(
          "failed-precondition",
          "Notification preferences need repair.",
          { reason: "preferencesMalformed", currentRevision: null },
        );
      }
      const malformed = preferenceSnapshot.data();
      const revision = Number.isInteger(malformed?.revision) && malformed.revision > 0
        ? malformed.revision + 1
        : 1;
      const createdAt = malformed?.createdAt instanceof Timestamp &&
          malformed.createdAt.toMillis() <= now.toMillis()
        ? malformed.createdAt
        : now;
      next = preferencePayload({
        uid,
        input: conservativePreferenceInput(input.householdID),
        joinedAt,
        zone,
        revision,
        createdAt,
        now,
      });
    }
    const result = {
      householdID: input.householdID,
      revision: next.revision,
      existing: false,
    };
    transaction.set(preference, next);
    transaction.create(receipt, {
      schemaVersion: 1,
      uid,
      householdID: input.householdID,
      memberJoinedAtSnapshot: joinedAt,
      action,
      fingerprint: requestFingerprint,
      result,
      createdAt: now,
    });
    return result;
  });
}

export async function resolveNotificationInboxRouteAt(
  db,
  request,
  receivedAt = new Date(),
) {
  const uid = requireAuth(request);
  exactObject(request.data, new Set(["householdID", "inboxItemID"]));
  const householdID = boundedID(request.data.householdID, "householdID");
  const inboxItemID = hexID(request.data.inboxItemID, "inboxItemID");
  const now = trustedTimestamp(receivedAt);
  const serverCheckedAt = rfc3339(now);
  const member = db.doc(`households/${householdID}/members/${uid}`);
  const item = db.doc(`users/${uid}/notificationInbox/${inboxItemID}`);
  const [memberSnapshot, itemSnapshot] = await Promise.all([
    member.get(), item.get(),
  ]);
  if (!memberSnapshot.exists) {
    throw new HttpsError("permission-denied", "Household membership is required.");
  }
  if (!itemSnapshot.exists) {
    return rejectRoute(householdID, inboxItemID, "missing", serverCheckedAt);
  }
  const inbox = canonicalInbox(itemSnapshot.data(), uid, householdID, inboxItemID);
  if (inbox == null) {
    return rejectRoute(householdID, inboxItemID, "malformed", serverCheckedAt);
  }
  const joinedAt = memberSnapshot.data()?.joinedAt;
  if (!(joinedAt instanceof Timestamp) ||
      !joinedAt.isEqual(inbox.recipientJoinedAtSnapshot)) {
    return rejectRoute(householdID, inboxItemID, "membershipEnded", serverCheckedAt);
  }
  if (inbox.status === "cancelled") {
    return rejectRoute(householdID, inboxItemID, "cancelled", serverCheckedAt);
  }
  if (inbox.expiresAt.toMillis() <= now.toMillis()) {
    await cancelExpiredInboxItem(db, item, inbox, now);
    return rejectRoute(householdID, inboxItemID, "expired", serverCheckedAt);
  }
  const source = sourceReference(db, uid, householdID, inbox);
  let sourceSnapshot;
  try {
    sourceSnapshot = await source.get();
  } catch {
    throw new HttpsError("unavailable", "Notification source is unavailable.");
  }
  if (!sourceSnapshot.exists) {
    return rejectRoute(householdID, inboxItemID, "sourceUnavailable", serverCheckedAt);
  }
  if (!sourceMatchesInbox(sourceSnapshot.data(), inbox, now)) {
    return rejectRoute(householdID, inboxItemID, "sourceChanged", serverCheckedAt);
  }
  return {
    disposition: "open",
    householdID,
    inboxItemID,
    category: inbox.category,
    level: inbox.level,
    serverCheckedAt,
  };
}

export async function expireNotificationInboxAt(db, receivedAt = new Date()) {
  const now = trustedTimestamp(receivedAt);
  let cancelled = 0;
  while (true) {
    const page = await db.collectionGroup("notificationInbox")
      .where("status", "==", "active")
      .where("expiresAt", "<=", now)
      .orderBy("expiresAt")
      .orderBy(FieldPath.documentId())
      .limit(100)
      .get();
    for (const document of page.docs) {
      const data = document.data();
      if (data?.status !== "active" || !(data.expiresAt instanceof Timestamp) ||
          data.expiresAt.toMillis() > now.toMillis()) continue;
      await cancelExpiredInboxItem(db, document.ref, data, now);
      cancelled += 1;
    }
    if (page.size < 100) break;
  }
  return { cancelled };
}

export async function generateNotificationSourceAt({
  db,
  householdID,
  sourceType,
  sourceID,
  projectID,
  bindingKeyVersion = null,
  now = new Date(),
}) {
  boundedID(householdID, "householdID");
  boundedID(sourceID, "sourceID");
  if (!sourceTypes.has(sourceType) || sourceType === "notificationDigest") {
    throw new HttpsError("invalid-argument", "sourceType is invalid.");
  }
  const trustedNow = trustedTimestamp(now);
  const gates = await readNotificationGatesAt(db, projectID);
  if (gates.generation == null) return { created: 0, disabled: true };
  const household = db.doc(`households/${householdID}`);
  const sourcePath = `${collectionForSource(sourceType)}/${sourceID}`;
  const source = household.collection(collectionForSource(sourceType)).doc(sourceID);
  const [householdSnapshot, sourceSnapshot, memberSnapshots] = await Promise.all([
    household.get(), source.get(), household.collection("members").get(),
  ]);
  if (!householdSnapshot.exists || !sourceSnapshot.exists) {
    return { created: 0, disabled: false };
  }
  const sourceData = sourceSnapshot.data();
  const medication = sourceType === "medicationOccurrence" &&
      validStoredID(sourceData?.medicationID)
    ? household.collection("medications").doc(sourceData.medicationID)
    : null;
  const medicationVersion = medication != null &&
      validStoredID(sourceData?.scheduleVersionID)
    ? medication.collection("scheduleVersions").doc(sourceData.scheduleVersionID)
    : null;
  const [medicationSnapshot, medicationVersionSnapshot] = medication == null ||
      medicationVersion == null
    ? [null, null]
    : await Promise.all([medication.get(), medicationVersion.get()]);
  const medicationRelationValid = sourceType !== "medicationOccurrence" ||
    canonicalMedicationOccurrenceRelation({
      occurrenceID: sourceID,
      occurrence: sourceData,
      medication: medicationSnapshot?.data(),
      version: medicationVersionSnapshot?.data(),
    });
  const candidates = medicationRelationValid ? notificationCandidates({
    sourceType,
    sourceID,
    sourceData,
    ownerID: householdSnapshot.data()?.ownerID,
    now: trustedNow,
  }) : [];
  if (candidates.length === 0) {
    const cancelled = await cancelTerminalSourceIntentsAt({
      db,
      householdID,
      sourceType,
      sourceID,
      source,
      memberIDs: memberSnapshots.docs.map((document) => document.id),
      ownerID: householdSnapshot.data()?.ownerID,
      now: trustedNow,
    });
    return { created: 0, cancelled, disabled: false };
  }
  const members = new Map(memberSnapshots.docs.map((document) => [
    document.id,
    document.data(),
  ]));
  const preferenceSnapshots = await Promise.all([...members.keys()].map(async (uid) => [
    uid,
    await db.doc(`users/${uid}/householdNotificationPreferences/${householdID}`).get(),
  ]));
  const preferences = new Map(preferenceSnapshots.map(([uid, snapshot]) => [
    uid,
    canonicalCurrentPreference(
      snapshot.data(), uid, householdID, members.get(uid)?.joinedAt,
      householdSnapshot.data()?.timeZoneIdentifier,
    ),
  ]));
  await reconcileActiveSourceIntentsAt({
    db, householdID, sourceType, sourceID, source,
    sourceData, memberIDs: [...members.keys()],
    ownerID: householdSnapshot.data()?.ownerID, now: trustedNow,
  });
  let created = 0;
  for (const candidate of candidates) {
    const recipients = recipientsForCandidate({
      candidate,
      sourceData,
      members,
      preferences,
    });
    for (const recipient of recipients) {
      const joinedAt = members.get(recipient.uid)?.joinedAt;
      if (!(joinedAt instanceof Timestamp)) continue;
      const semanticAt = candidate.semanticAt;
      if (semanticAt.toMillis() < gates.generation.cutoverAt.toMillis()) continue;
      const preference = preferences.get(recipient.uid);
      const pushEligible = recipient.pushEligible(preference);
      const dispatchPlan = pushEligible
        ? notificationDispatchPlan({
          household: { ...householdSnapshot.data(), id: householdID }, preference,
          recipientID: recipient.uid, joinedAt, candidate,
          baseAt: candidate.semanticAt, now: trustedNow,
        })
        : { nextDispatchAt: null, coalescingKey: null, digest: null };
      const intentID = intentIDFor({
        householdID,
        sourceType,
        sourcePath,
        sourceRevision: sourceData.revision,
        level: candidate.level,
        recipientID: recipient.uid,
        recipientJoinedAtSnapshot: joinedAt,
      });
      const intent = db.doc(`users/${recipient.uid}/notificationInbox/${intentID}`);
      const preferenceRef = db.doc(
        `users/${recipient.uid}/householdNotificationPreferences/${householdID}`,
      );
      const member = household.collection("members").doc(recipient.uid);
      const generationGate = db.doc("systemConfig/notificationIntentGenerationV2");
      const digestRef = dispatchPlan.digest == null
        ? null
        : db.doc(
          `users/${recipient.uid}/notificationDigests/${dispatchPlan.digest.id}`,
        );
      const summaryID = dispatchPlan.digest == null ? null : intentIDFor({
        householdID,
        sourceType: "notificationDigest",
        sourcePath: `notificationDigests/${dispatchPlan.digest.id}`,
        sourceRevision: 1,
        level: dispatchPlan.digest.payload.mode === "burst"
          ? "burstSummary"
          : "dailySummary",
        recipientID: recipient.uid,
        recipientJoinedAtSnapshot: joinedAt,
      });
      const summaryRef = summaryID == null
        ? null
        : db.doc(`users/${recipient.uid}/notificationInbox/${summaryID}`);
      const summaryManifestRef = summaryID == null
        ? null
        : db.doc(
          `users/${recipient.uid}/notificationDeliveryManifests/${summaryID}`,
        );
      const didCreate = await db.runTransaction(async (transaction) => {
        const [gateSnapshot, freshHousehold, freshSource, freshMember,
          freshPreference, existingIntent, existingDigest, existingSummary,
          existingSummaryManifest, freshMedication,
          freshMedicationVersion] = await Promise.all([
            transaction.get(generationGate), transaction.get(household),
            transaction.get(source), transaction.get(member),
            transaction.get(preferenceRef),
            transaction.get(intent), digestRef == null ? null : transaction.get(digestRef),
            summaryRef == null ? null : transaction.get(summaryRef),
            summaryManifestRef == null ? null : transaction.get(summaryManifestRef),
            medication == null ? null : transaction.get(medication),
            medicationVersion == null ? null : transaction.get(medicationVersion),
          ]);
        const gate = canonicalGate(gateSnapshot.data(), projectID);
        const joinedAtNow = freshMember.data()?.joinedAt;
        const preferenceNow = canonicalCurrentPreference(
          freshPreference.data(), recipient.uid, householdID,
          joinedAtNow, freshHousehold.data()?.timeZoneIdentifier,
        );
        if (gate == null || !freshHousehold.exists || !freshSource.exists ||
            !freshMember.exists ||
            !(joinedAtNow instanceof Timestamp) || !joinedAtNow.isEqual(joinedAt) ||
            (preferenceNow?.revision ?? null) !== (preference?.revision ?? null) ||
            recipient.pushEligible(preferenceNow) !== pushEligible ||
            (sourceType === "medicationOccurrence" &&
              !canonicalMedicationOccurrenceRelation({
                occurrenceID: sourceID,
                occurrence: freshSource.data(),
                medication: freshMedication?.data(),
                version: freshMedicationVersion?.data(),
              })) ||
            !sourceMatchesCandidate(
              sourceType, sourceID, freshSource.data(), candidate, recipient.uid,
              freshHousehold.data()?.ownerID,
            ) || semanticAt.toMillis() < gate.cutoverAt.toMillis()) return false;
        if (recipient.requiresOptIn && !recipient.inboxEligible(preferenceNow)) return false;
        if (existingIntent.exists) return false;
        if (digestRef != null) {
          if (!existingDigest.exists) {
            transaction.create(digestRef, dispatchPlan.digest.payload);
          } else {
            const digest = canonicalDigest(
              existingDigest.data(), recipient.uid, dispatchPlan.digest.id,
            );
            if (digest == null || digest.preferenceRevision !== preferenceNow.revision) {
              return false;
            }
            if (digest.status === "cancelled" &&
                digest.cancelReason === "noValidSource" &&
                trustedNow.toMillis() < digest.catchUpUntilAt.toMillis() &&
                !existingSummary.exists && !existingSummaryManifest.exists) {
              transaction.update(digestRef, {
                status: "collecting", cancelReason: null, safeErrorCode: null,
                nextFinalizeAt: trustedNow, readyAt: null, cancelledAt: null,
                blockedAt: null, updatedAt: trustedNow,
              });
            } else if (digest.status !== "collecting") {
              return false;
            }
          }
        }
        transaction.create(intent, {
          schemaVersion: 1,
          id: intentID,
          householdID,
          recipientID: recipient.uid,
          recipientJoinedAtSnapshot: joinedAt,
          category: candidate.category,
          level: candidate.level,
          routeReason: recipient.routeReason,
          sourceType,
          sourceID,
          sourcePath,
          sourceRevision: sourceData.revision,
          preferenceRevision: pushEligible ? preference.revision : null,
          status: "active",
          availableAt: trustedNow,
          expiresAt: candidate.expiresAt,
          nextDispatchAt: dispatchPlan.nextDispatchAt,
          coalescingKey: dispatchPlan.coalescingKey,
          cancelReason: null,
          cancelledAt: null,
          createdAt: trustedNow,
          updatedAt: trustedNow,
        });
        return true;
      });
      if (didCreate) {
        created += 1;
        if (dispatchPlan.nextDispatchAt != null &&
            Number.isInteger(bindingKeyVersion) && bindingKeyVersion > 0) {
          await materializeNotificationDeliveriesAt({
            db,
            uid: recipient.uid,
            intentID,
            now,
            bindingKeyVersion,
          });
        }
      }
    }
  }
  return { created, disabled: false };
}

export async function generateMedicationNotificationIntentsAt({
  db,
  projectID,
  bindingKeyVersion = null,
  now = new Date(),
}) {
  const trustedNow = trustedTimestamp(now);
  const gates = await readNotificationGatesAt(db, projectID);
  if (gates.generation == null) return { materialized: 0, created: 0, disabled: true };
  const medications = await db.collectionGroup("medications").get();
  let materialized = 0;
  let created = 0;
  for (const medication of medications.docs) {
    const household = medication.ref.parent.parent;
    const medicationData = canonicalMedicationPlan(
      medication.id, medication.data(),
    );
    if (household == null || medicationData == null) continue;
    const versions = await medication.ref.collection("scheduleVersions").limit(101).get();
    if (versions.size > 100) continue;
    for (const versionSnapshot of versions.docs) {
      const versionID = versionSnapshot.id;
      const version = versionSnapshot.ref;
      const planned = plannedMedicationOccurrences({
        medicationID: medication.id,
        medicationData,
        versionID,
        versionData: versionSnapshot.data(),
        now: trustedNow,
      });
      for (const plan of planned) {
      const occurrence = household.collection("medicationOccurrences").doc(plan.id);
      const wasMaterialized = await db.runTransaction(async (transaction) => {
        const [gateSnapshot, medicationSnapshot, versionFresh, occurrenceSnapshot] =
          await Promise.all([
            transaction.get(db.doc("systemConfig/notificationIntentGenerationV2")),
            transaction.get(medication.ref), transaction.get(version),
            transaction.get(occurrence),
          ]);
        const gate = canonicalGate(gateSnapshot.data(), projectID);
        if (gate == null || occurrenceSnapshot.exists ||
            canonicalMedicationPlan(
              medication.id, medicationSnapshot.data(),
            ) == null ||
            !sameMedicationVersion(versionFresh.data(), plan.versionData)) return false;
        transaction.create(occurrence, medicationOccurrencePayload(plan, trustedNow));
        return true;
      });
      if (wasMaterialized) materialized += 1;
      const generated = await generateNotificationSourceAt({
        db,
        householdID: household.id,
        sourceType: "medicationOccurrence",
        sourceID: plan.id,
        projectID,
        bindingKeyVersion,
        now,
      });
      created += generated.created;
      }
    }
  }
  return { materialized, created, disabled: false };
}

export async function finalizeNotificationDigestAt({
  db,
  uid,
  digestID,
  projectID,
  bindingKeyVersion = null,
  now = new Date(),
}) {
  boundedID(uid, "uid");
  hexID(digestID, "digestID");
  const trustedNow = trustedTimestamp(now);
  const digestRef = db.doc(`users/${uid}/notificationDigests/${digestID}`);
  const gates = await readNotificationGatesAt(db, projectID);
  if (gates.generation == null) return { status: "disabled" };
  const digestSnapshot = await digestRef.get();
  const digest = canonicalDigest(digestSnapshot.data(), uid, digestID);
  if (digest == null || digest.status !== "collecting" ||
      digest.nextFinalizeAt.toMillis() > trustedNow.toMillis()) {
    return { status: "skipped" };
  }
  const householdRef = db.doc(`households/${digest.householdID}`);
  const memberRef = householdRef.collection("members").doc(uid);
  const preferenceRef = db.doc(
    `users/${uid}/householdNotificationPreferences/${digest.householdID}`,
  );
  const [householdSnapshot, memberSnapshot, preferenceSnapshot] = await Promise.all([
    householdRef.get(), memberRef.get(), preferenceRef.get(),
  ]);
  const joinedAt = memberSnapshot.data()?.joinedAt;
  if (!memberSnapshot.exists || !(joinedAt instanceof Timestamp) ||
      !joinedAt.isEqual(digest.recipientJoinedAtSnapshot)) {
    await cancelDigest(digestRef, digest, "membershipEnded", trustedNow);
    return { status: "cancelled" };
  }
  const preference = canonicalCurrentPreference(
    preferenceSnapshot.data(), uid, digest.householdID, joinedAt,
    householdSnapshot.data()?.timeZoneIdentifier,
  );
  if (preference == null || preference.revision !== digest.preferenceRevision ||
      !preferenceAllowsPush(preference, "assignment")) {
    await cancelDigest(digestRef, digest, "policyChanged", trustedNow);
    return { status: "cancelled" };
  }
  const validation = await validateDigestOriginalsAt({
    db, uid, digest, now: trustedNow,
    cutoff: gates.generation.cutoverAt.toMillis(),
  });
  if (validation.status === "blocked") {
    await blockDigest(digestRef, digest, trustedNow);
    return { status: "blocked" };
  }
  if (validation.status !== "valid") {
    await cancelDigest(digestRef, digest, "noValidSource", trustedNow);
    return { status: "cancelled" };
  }
  const valid = validation;
  const summaryID = intentIDFor({
    householdID: digest.householdID,
    sourceType: "notificationDigest",
    sourcePath: `notificationDigests/${digestID}`,
    sourceRevision: 1,
    level: digest.mode === "burst" ? "burstSummary" : "dailySummary",
    recipientID: uid,
    recipientJoinedAtSnapshot: digest.recipientJoinedAtSnapshot,
  });
  const summary = db.doc(`users/${uid}/notificationInbox/${summaryID}`);
  const expiresAt = Timestamp.fromMillis(digest.windowEndAt.toMillis() + 86_400_000);
  const dispatchAvailableAt = quietEndAvailability({
    preference,
    zone: householdSnapshot.data()?.timeZoneIdentifier,
    now: trustedNow,
  });
  if (dispatchAvailableAt.toMillis() >= expiresAt.toMillis()) {
    await cancelDigest(digestRef, digest, "availabilityExpired", trustedNow);
    return { status: "cancelled" };
  }
  const expectedSummary = {
    schemaVersion: 1, id: summaryID, householdID: digest.householdID,
    recipientID: uid, recipientJoinedAtSnapshot: digest.recipientJoinedAtSnapshot,
    category: "summary",
    level: digest.mode === "burst" ? "burstSummary" : "dailySummary",
    routeReason: "summary", sourceType: "notificationDigest",
    sourceID: digestID, sourcePath: `notificationDigests/${digestID}`,
    sourceRevision: 1, preferenceRevision: digest.preferenceRevision,
    status: "active", availableAt: dispatchAvailableAt, expiresAt,
    nextDispatchAt: dispatchAvailableAt, coalescingKey: digestID,
    cancelReason: null, cancelledAt: null,
    createdAt: trustedNow, updatedAt: trustedNow,
  };
  const finalized = await db.runTransaction(async (transaction) => {
    const [freshDigest, summarySnapshot, freshGate, freshHousehold, freshMember,
      freshPreference, freshSource] = await Promise.all([
      transaction.get(digestRef), transaction.get(summary),
      transaction.get(db.doc("systemConfig/notificationIntentGenerationV2")),
      transaction.get(householdRef), transaction.get(memberRef),
      transaction.get(preferenceRef), transaction.get(valid.source),
    ]);
    const current = canonicalDigest(freshDigest.data(), uid, digestID);
    const gate = canonicalGate(freshGate.data(), projectID);
    const currentJoinedAt = freshMember.data()?.joinedAt;
    const currentPreference = canonicalCurrentPreference(
      freshPreference.data(), uid, digest.householdID, currentJoinedAt,
      freshHousehold.data()?.timeZoneIdentifier,
    );
    if (current?.status !== "collecting" || gate == null ||
        !(currentJoinedAt instanceof Timestamp) ||
        !currentJoinedAt.isEqual(digest.recipientJoinedAtSnapshot) ||
        currentPreference?.revision !== digest.preferenceRevision ||
        !preferenceAllowsPush(currentPreference, "assignment") ||
        !freshSource.exists || !sourceMatchesInbox(
          freshSource.data(), valid.inbox, trustedNow,
        )) return { status: "skipped" };
    if (summarySnapshot.exists && !matchingSummary(
      summarySnapshot.data(), expectedSummary, uid, digest.householdID, summaryID,
    )) return { status: "skipped" };
    transaction.update(digestRef, {
      status: "ready", readyAt: trustedNow, nextFinalizeAt: null,
      updatedAt: trustedNow,
    });
    if (!summarySnapshot.exists) transaction.create(summary, expectedSummary);
    return { status: "ready" };
  });
  if (finalized?.status !== "ready") return { status: "skipped" };
  if (Number.isInteger(bindingKeyVersion) && bindingKeyVersion > 0) {
    await materializeNotificationDeliveriesAt({
      db, uid, intentID: summaryID, now, bindingKeyVersion,
    });
  }
  return { status: "ready", summaryID };
}

export async function materializeNotificationDeliveriesAt({
  db,
  uid,
  intentID,
  now = new Date(),
  bindingKeyVersion,
}) {
  boundedID(uid, "uid");
  hexID(intentID, "intentID");
  if (!Number.isInteger(bindingKeyVersion) || bindingKeyVersion < 1) {
    throw new HttpsError("failed-precondition", "Binding key configuration is unavailable.");
  }
  const trustedNow = trustedTimestamp(now);
  const item = db.doc(`users/${uid}/notificationInbox/${intentID}`);
  const manifest = db.doc(`users/${uid}/notificationDeliveryManifests/${intentID}`);
  const initialized = await db.runTransaction(async (transaction) => {
    const [manifestSnapshot, itemSnapshot] = await Promise.all([
      transaction.get(manifest), transaction.get(item),
    ]);
    const inbox = canonicalInbox(
      itemSnapshot.data(), uid, itemSnapshot.data()?.householdID, intentID,
    );
    if (inbox == null || inbox.status !== "active" || inbox.nextDispatchAt == null) {
      throw new HttpsError("failed-precondition", "Notification intent is not dispatchable.");
    }
    if (manifestSnapshot.exists) {
      const current = canonicalManifest(
        manifestSnapshot.data(), uid, intentID, inbox,
      );
      if (current == null || current.bindingKeyVersion !== bindingKeyVersion) {
        throw new HttpsError("failed-precondition", "Delivery manifest needs repair.");
      }
      return { inbox, manifest: current };
    }
    const tokens = await transaction.get(
      db.collection(`users/${uid}/notificationTokens`)
        .where("householdID", "==", inbox.householdID),
    );
    const eligible = tokens.docs.filter((document) =>
      canonicalInstallationID.test(document.id) &&
      document.data()?.enabled === true && validToken(document.data()?.token),
    );
    if (eligible.length > maxInstallations) {
      const blocked = manifestPayload({
        inbox, intentID, bindingKeyVersion, selected: [], now: trustedNow,
        status: "blocked", safeErrorCode: "tooManyInstallations",
      });
      transaction.create(manifest, blocked);
      return { inbox, manifest: blocked };
    }
    const byToken = new Map();
    for (const token of eligible) {
      const value = token.data().token;
      const current = byToken.get(value);
      if (current == null || token.id < current) byToken.set(value, token.id);
    }
    const selected = [...byToken.values()].sort();
    const payload = manifestPayload({
      inbox, intentID, bindingKeyVersion, selected, now: trustedNow,
      status: "materializing", safeErrorCode: null,
    });
    transaction.create(manifest, payload);
    return { inbox, manifest: payload };
  });
  if (initialized.manifest.status !== "materializing") {
    return {
      status: initialized.manifest.status,
      selectedCount: initialized.manifest.selectedCount,
    };
  }
  return resumeNotificationManifestAt({
    db, uid, intentID, inbox: initialized.inbox, now: trustedNow,
  });
}

async function resumeNotificationManifestAt({ db, uid, intentID, inbox, now }) {
  const manifest = db.doc(`users/${uid}/notificationDeliveryManifests/${intentID}`);
  while (true) {
    const outcome = await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(manifest);
      const current = canonicalManifest(snapshot.data(), uid, intentID, inbox);
      if (current == null) {
        throw new HttpsError("failed-precondition", "Delivery manifest needs repair.");
      }
      if (current.status !== "materializing") {
        return { done: true, status: current.status, selectedCount: current.selectedCount };
      }
      const cursorIndex = current.cursorInstallationHash == null
        ? -1
        : current.selectedInstallationHashes.indexOf(current.cursorInstallationHash);
      if (current.cursorInstallationHash != null && cursorIndex < 0) {
        throw new HttpsError("failed-precondition", "Delivery manifest needs repair.");
      }
      const batch = current.selectedInstallationHashes.slice(
        cursorIndex + 1,
        cursorIndex + 1 + manifestBatchSize,
      );
      const expectedDeliveries = batch.map((installationHash) => {
        const id = deliveryIDFor(intentID, installationHash);
        return {
          reference: db.doc(`users/${uid}/notificationDeliveries/${id}`),
          expected: deliveryPayload({
            id, intentID, inbox, installationHash, now: current.createdAt,
          }),
        };
      });
      const snapshots = expectedDeliveries.length === 0 ? [] :
        await transaction.getAll(
          ...expectedDeliveries.map(({ reference }) => reference),
        );
      const conflicting = expectedDeliveries.some(({ expected }, index) =>
        snapshots[index].exists &&
        JSON.stringify(serializableDelivery(snapshots[index].data())) !==
          JSON.stringify(serializableDelivery(expected)));
      if (conflicting) {
        transaction.update(manifest, {
          status: "blocked", safeErrorCode: "conflictingDelivery",
          cursorInstallationHash: null, nextRecoveryAt: null,
          updatedAt: now, completedAt: null, blockedAt: now,
        });
        return { done: true, status: "blocked", selectedCount: current.selectedCount };
      }
      for (let index = 0; index < expectedDeliveries.length; index += 1) {
        if (!snapshots[index].exists) {
          transaction.create(
            expectedDeliveries[index].reference,
            expectedDeliveries[index].expected,
          );
        }
      }
      const nextCursor = batch.at(-1) ?? current.cursorInstallationHash;
      const finished = cursorIndex + 1 + batch.length >= current.selectedCount;
      if (finished) {
        transaction.update(manifest, {
          status: "complete", safeErrorCode: null,
          cursorInstallationHash: null, nextRecoveryAt: null,
          updatedAt: now, completedAt: now, blockedAt: null,
        });
        return { done: true, status: "complete", selectedCount: current.selectedCount };
      }
      transaction.update(manifest, {
        cursorInstallationHash: nextCursor,
        updatedAt: now,
        nextRecoveryAt: Timestamp.fromMillis(now.toMillis() + 300_000),
      });
      return { done: false };
    });
    if (outcome.done) return {
      status: outcome.status,
      selectedCount: outcome.selectedCount,
    };
  }
}

export async function dispatchNotificationDeliveryAt({
  db,
  uid,
  deliveryID,
  projectID,
  keyRing,
  provider,
  now = new Date(),
}) {
  const trustedNow = trustedTimestamp(now);
  const gates = await readNotificationGatesAt(db, projectID);
  if (!gates.enabled) {
    return { status: "deferred", reason: "gatesDisabled" };
  }
  if (typeof provider !== "function") {
    return { status: "deferred", reason: "providerUnavailable" };
  }
  boundedID(uid, "uid");
  hexID(deliveryID, "deliveryID");
  const delivery = db.doc(`users/${uid}/notificationDeliveries/${deliveryID}`);
  const deliverySnapshot = await delivery.get();
  const current = canonicalDelivery(deliverySnapshot.data(), uid, deliveryID);
  if (current == null || !["queued", "retryableFailure"].includes(current.status) ||
      current.nextAttemptAt.toMillis() > trustedNow.toMillis()) {
    return { status: "skipped", reason: "notReady" };
  }
  const intent = db.doc(`users/${uid}/notificationInbox/${current.intentID}`);
  const preliminaryIntent = await intent.get();
  const preliminaryInbox = canonicalInbox(
    preliminaryIntent.data(), uid, current.householdID, current.intentID,
  );
  const claimSummaryAuthority = await validateSummaryAuthorityAt({
    db, uid, inbox: preliminaryInbox, now: trustedNow,
    cutoff: Math.max(
      gates.generation.cutoverAt.toMillis(), gates.dispatch.cutoverAt.toMillis(),
    ),
  });
  const manifest = db.doc(
    `users/${uid}/notificationDeliveryManifests/${current.intentID}`,
  );
  const installation = db.doc(
    `users/${uid}/notificationTokens/${current.installationHash}`,
  );
  const member = db.doc(`households/${current.householdID}/members/${uid}`);
  const household = db.doc(`households/${current.householdID}`);
  const revocation = db.doc(
    `households/${current.householdID}/membershipRevocations/${uid}`,
  );
  const preference = db.doc(
    `users/${uid}/householdNotificationPreferences/${current.householdID}`,
  );
  const leaseID = randomUUID();
  const leaseExpiresAt = Timestamp.fromMillis(trustedNow.toMillis() + 60_000);
  const claim = revocation.collection("notificationClaims").doc(deliveryID);
  const generationGate = db.doc("systemConfig/notificationIntentGenerationV2");
  const dispatchGate = db.doc("systemConfig/notificationDispatchV2");
  const attempt = await db.runTransaction(async (transaction) => {
    const [freshDelivery, intentSnapshot, manifestSnapshot, installationSnapshot,
      memberSnapshot, householdSnapshot, revocationSnapshot, preferenceSnapshot,
      generationSnapshot, dispatchSnapshot, originalIntentSnapshot,
      originalSourceSnapshot] = await Promise.all([
        transaction.get(delivery), transaction.get(intent), transaction.get(manifest),
        transaction.get(installation), transaction.get(member),
        transaction.get(household), transaction.get(revocation),
        transaction.get(preference), transaction.get(generationGate),
        transaction.get(dispatchGate),
        claimSummaryAuthority.status === "valid"
          ? transaction.get(claimSummaryAuthority.intent)
          : null,
        claimSummaryAuthority.status === "valid"
          ? transaction.get(claimSummaryAuthority.source)
          : null,
      ]);
    const value = canonicalDelivery(freshDelivery.data(), uid, deliveryID);
    const inbox = canonicalInbox(
      intentSnapshot.data(), uid, current.householdID, current.intentID,
    );
    const tokenData = installationSnapshot.data();
    const joinedAt = memberSnapshot.data()?.joinedAt;
    const zone = householdSnapshot.data()?.timeZoneIdentifier;
    const prefs = canonicalCurrentPreference(
      preferenceSnapshot.data(), uid, current.householdID, joinedAt, zone,
    );
    const manifestData = inbox == null ? null : canonicalManifest(
      manifestSnapshot.data(), uid, current.intentID, inbox,
    );
    const generation = canonicalGate(generationSnapshot.data(), projectID);
    const dispatch = canonicalGate(dispatchSnapshot.data(), projectID);
    const summaryAuthorityValid = inbox?.sourceType !== "notificationDigest" ||
      (claimSummaryAuthority.status === "valid" &&
        originalIntentSnapshot?.exists && originalSourceSnapshot?.exists &&
        canonicalInbox(
          originalIntentSnapshot.data(), uid, current.householdID,
          originalIntentSnapshot.id,
        )?.status === "active" && sourceMatchesInbox(
          originalSourceSnapshot.data(), claimSummaryAuthority.inbox, trustedNow,
          householdSnapshot.data()?.ownerID,
        ) && semanticInstantForSource(
          claimSummaryAuthority.inbox, originalSourceSnapshot.data(),
        ).toMillis() >= Math.max(
          generation?.cutoverAt?.toMillis() ?? Number.MAX_SAFE_INTEGER,
          dispatch?.cutoverAt?.toMillis() ?? Number.MAX_SAFE_INTEGER,
        ));
    if (value == null || !["queued", "retryableFailure"].includes(value.status) ||
        value.nextAttemptAt.toMillis() > trustedNow.toMillis()) return null;
    const sourceSnapshot = inbox == null
      ? null
      : await transaction.get(sourceReference(
        db, uid, current.householdID, inbox,
      ));
    if (inbox == null || inbox.status !== "active" ||
        inbox.expiresAt.toMillis() <= trustedNow.toMillis() ||
        generation == null || dispatch == null ||
        sourceSnapshot == null || !sourceSnapshot.exists ||
        !sourceMatchesInbox(
          sourceSnapshot.data(), inbox, trustedNow, householdSnapshot.data()?.ownerID,
        ) || !summaryAuthorityValid ||
        semanticInstantForSource(inbox, sourceSnapshot.data()).toMillis() <
          Math.max(generation.cutoverAt.toMillis(), dispatch.cutoverAt.toMillis()) ||
        manifestData?.status !== "complete" ||
        !manifestData.selectedInstallationHashes.includes(current.installationHash) ||
        !(joinedAt instanceof Timestamp) ||
        !joinedAt.isEqual(current.recipientJoinedAtSnapshot) ||
        revocationSnapshot.exists || tokenData?.enabled !== true ||
        tokenData?.householdID !== current.householdID ||
        !validToken(tokenData?.token) || prefs == null ||
        prefs.revision !== inbox.preferenceRevision ||
        !preferenceAllowsPush(prefs, inbox.category)) {
      const membershipInvalid = !(joinedAt instanceof Timestamp) ||
        !joinedAt.isEqual(current.recipientJoinedAtSnapshot) ||
        revocationSnapshot.exists;
      const preferenceInvalid = prefs == null ||
        prefs.revision !== inbox?.preferenceRevision ||
        !preferenceAllowsPush(prefs, inbox?.category);
      if (inbox?.sourceType === "notificationDigest" && sourceSnapshot?.exists &&
          (!summaryAuthorityValid || membershipInvalid || preferenceInvalid)) {
        const digest = canonicalDigest(sourceSnapshot.data(), uid, inbox.sourceID);
        if (digest?.status === "ready") {
          if (!summaryAuthorityValid && claimSummaryAuthority.status === "blocked") {
            transaction.update(sourceSnapshot.ref, {
              status: "blocked", safeErrorCode: "tooManyCandidates",
              cancelReason: null, nextFinalizeAt: null, readyAt: null,
              cancelledAt: null, blockedAt: trustedNow, updatedAt: trustedNow,
            });
          } else {
            const cancelReason = membershipInvalid
              ? "membershipEnded"
              : preferenceInvalid
                ? "policyChanged"
                : "noValidSource";
            transaction.update(sourceSnapshot.ref, {
              status: "cancelled", cancelReason,
              safeErrorCode: null, nextFinalizeAt: null, readyAt: null,
              cancelledAt: trustedNow, blockedAt: null, updatedAt: trustedNow,
            });
            transaction.update(intent, {
              status: "cancelled", cancelReason,
              cancelledAt: trustedNow, nextDispatchAt: null, updatedAt: trustedNow,
            });
          }
          if (!summaryAuthorityValid && claimSummaryAuthority.status === "blocked") {
            transaction.update(intent, {
              status: "cancelled", cancelReason: "sourceChanged",
              cancelledAt: trustedNow, nextDispatchAt: null, updatedAt: trustedNow,
            });
          }
        }
      }
      transaction.update(delivery, terminalDelivery({
        current: value,
        now: trustedNow,
        status: "cancelled",
        safeErrorCode: !memberSnapshot.exists || revocationSnapshot.exists
          ? "membershipEnded"
          : "policyChanged",
      }));
      return null;
    }
    const attemptCount = value.attemptCount + 1;
    transaction.update(delivery, {
      status: "attempting", attemptCount, nextAttemptAt: null,
      leaseID, leaseExpiresAt, providerRequestStartedAt: null,
      providerAcceptedAt: null, providerUnknownAt: null, terminalAt: null,
      safeErrorCode: null, updatedAt: trustedNow,
    });
    transaction.create(claim, {
      schemaVersion: 1, deliveryID, leaseID,
      leaseUntil: leaseExpiresAt, createdAt: trustedNow, updatedAt: trustedNow,
    });
    return {
      inbox,
      token: tokenData.token,
      attemptCount,
      leaseID,
      bindingKeyVersion: manifestData.bindingKeyVersion,
    };
  });
  if (attempt == null) {
    const afterClaim = await delivery.get();
    if (afterClaim.data()?.status === "cancelled") {
      await cancelWinningBindingsForDeliveryAt({
        db, householdID: current.householdID, deliveryID, now: trustedNow,
      });
    }
    return { status: "skipped", reason: "ineligible" };
  }

  const finalGates = await readNotificationGatesAt(db, projectID);
  if (!finalGates.enabled) {
    await releaseAttempt({
      db, delivery, claim, current, expectedLeaseID: attempt.leaseID,
      now: trustedNow,
    });
    return { status: "deferred", reason: "gatesDisabled" };
  }
  const secret = keyRing?.get(attempt.bindingKeyVersion);
  if (typeof secret !== "string" || secret.length === 0) {
    await releaseAttempt({
      db, delivery, claim, current, expectedLeaseID: attempt.leaseID,
      now: trustedNow,
    });
    return { status: "deferred", reason: "bindingKeyUnavailable" };
  }
  const start = await startProviderAttempt({
    db,
    uid,
    delivery,
    claim,
    current,
    attempt,
    projectID,
    secret,
    now: trustedNow,
  });
  if (start.status !== "started") return start;
  const startedAt = start.startedAt;
  let outcome;
  try {
    outcome = await provider(providerMessage({
      inbox: attempt.inbox,
      token: attempt.token,
      secret,
      startedAt,
    }));
  } catch {
    outcome = { kind: "ambiguous" };
  }
  const normalized = normalizeProviderOutcome(outcome);
  if (normalized.kind === "definitePermanentRejection" &&
      normalized.reason === "tokenInvalid") {
    await disableInvalidTokenInstallationsAt({
      db, uid, householdID: current.householdID, token: attempt.token,
      now: trustedNow,
    });
  }
  await completeProviderAttempt({
    db, delivery, claim, binding: start.binding,
    current, attemptCount: attempt.attemptCount,
    expectedLeaseID: attempt.leaseID,
    outcome: normalized, now: trustedNow,
  });
  return { status: normalized.kind };
}

async function cancelWinningBindingsForDeliveryAt({
  db, householdID, deliveryID, now,
}) {
  const bindings = await db.collection(
    `households/${householdID}/notificationEndpointBindings`,
  ).where("winningDeliveryID", "==", deliveryID).get();
  for (const binding of bindings.docs) {
    await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(binding.ref);
      if (snapshot.data()?.winningDeliveryID !== deliveryID ||
          !["reserved", "retryableFailure"].includes(snapshot.data()?.status)) return;
      transaction.update(binding.ref, {
        status: "cancelled", leaseExpiresAt: null, updatedAt: now,
      });
    });
  }
}

export async function dispatchReadyNotificationDeliveriesAt({
  db,
  projectID,
  keyRing,
  provider,
  now = new Date(),
}) {
  const gates = await readNotificationGatesAt(db, projectID);
  if (!gates.enabled || typeof provider !== "function") {
    return { processed: 0, disabled: true };
  }
  const trustedNow = trustedTimestamp(now);
  const ready = await db.collectionGroup("notificationDeliveries")
    .where("status", "in", ["queued", "retryableFailure"])
    .where("nextAttemptAt", "<=", trustedNow)
    .orderBy("nextAttemptAt")
    .orderBy(FieldPath.documentId())
    .limit(100)
    .get();
  let processed = 0;
  for (const document of ready.docs) {
    const uid = document.ref.parent.parent?.id;
    if (uid == null) continue;
    await dispatchNotificationDeliveryAt({
      db, uid, deliveryID: document.id, projectID, keyRing, provider, now,
    });
    processed += 1;
  }
  await recoverAttemptingDeliveriesAt({ db, now });
  return { processed, disabled: false };
}

export async function recoverAttemptingDeliveriesAt({ db, now = new Date() }) {
  const trustedNow = trustedTimestamp(now);
  const expired = await db.collectionGroup("notificationDeliveries")
    .where("status", "==", "attempting")
    .where("leaseExpiresAt", "<=", trustedNow)
    .orderBy("leaseExpiresAt")
    .orderBy(FieldPath.documentId())
    .limit(100)
    .get();
  for (const document of expired.docs) {
    const before = document.data();
    const bindingCandidates = validStoredID(before?.householdID)
      ? await db.collection(
        `households/${before.householdID}/notificationEndpointBindings`,
      ).where("winningDeliveryID", "==", document.id).get()
      : { docs: [] };
    const bindingDocument = bindingCandidates.docs.find((candidate) => {
      const data = candidate.data();
      return data.status === "reserved" && data.leaseExpiresAt instanceof Timestamp &&
        before.leaseExpiresAt instanceof Timestamp &&
        data.leaseExpiresAt.isEqual(before.leaseExpiresAt);
    }) ?? null;
    await db.runTransaction(async (transaction) => {
      const [snapshot, bindingSnapshot] = await Promise.all([
        transaction.get(document.ref),
        bindingDocument == null ? null : transaction.get(bindingDocument.ref),
      ]);
      const data = snapshot.data();
      if (data?.status !== "attempting" ||
          !(data.leaseExpiresAt instanceof Timestamp) ||
          data.leaseExpiresAt.toMillis() > trustedNow.toMillis()) return;
      const claim = db.doc(
        `households/${data.householdID}/membershipRevocations/` +
        `${data.recipientID}/notificationClaims/${document.id}`,
      );
      const claimSnapshot = await transaction.get(claim);
      if (data.providerRequestStartedAt instanceof Timestamp) {
        transaction.update(document.ref, terminalDelivery({
          current: data, now: trustedNow, status: "providerUnknown",
          safeErrorCode: "providerAmbiguous",
        }));
        if (bindingSnapshot?.exists &&
            bindingSnapshot.data()?.winningDeliveryID === document.id &&
            bindingSnapshot.data()?.status === "reserved" &&
            bindingSnapshot.data()?.leaseExpiresAt instanceof Timestamp &&
            bindingSnapshot.data().leaseExpiresAt.isEqual(data.leaseExpiresAt)) {
          transaction.update(bindingDocument.ref, {
            status: "providerUnknown", leaseExpiresAt: null, updatedAt: trustedNow,
          });
        }
      } else if (data.attemptCount >= 3) {
        transaction.update(document.ref, terminalDelivery({
          current: data, now: trustedNow, status: "permanentFailure",
          safeErrorCode: "providerRejected",
        }));
        if (bindingSnapshot?.exists &&
            bindingSnapshot.data()?.winningDeliveryID === document.id &&
            bindingSnapshot.data()?.status === "reserved") {
          transaction.update(bindingDocument.ref, {
            status: "permanentFailure", leaseExpiresAt: null, updatedAt: trustedNow,
          });
        }
      } else {
        transaction.update(document.ref, {
          status: "retryableFailure", nextAttemptAt: Timestamp.fromMillis(
            trustedNow.toMillis() + 300_000,
          ), leaseID: null, leaseExpiresAt: null,
          providerRequestStartedAt: null, providerAcceptedAt: null,
          providerUnknownAt: null, terminalAt: null,
          safeErrorCode: "leaseExpired", updatedAt: trustedNow,
        });
        if (bindingSnapshot?.exists &&
            bindingSnapshot.data()?.winningDeliveryID === document.id &&
            bindingSnapshot.data()?.status === "reserved") {
          transaction.update(bindingDocument.ref, {
            status: "retryableFailure", leaseExpiresAt: null, updatedAt: trustedNow,
          });
        }
      }
      if (claimSnapshot.exists) transaction.delete(claim);
    });
  }
  return { recovered: expired.size };
}

export async function recoverNotificationManifestsAt({ db, now = new Date() }) {
  const trustedNow = trustedTimestamp(now);
  const due = await db.collectionGroup("notificationDeliveryManifests")
    .where("status", "==", "materializing")
    .where("nextRecoveryAt", "<=", trustedNow)
    .orderBy("nextRecoveryAt")
    .orderBy(FieldPath.documentId())
    .limit(100)
    .get();
  let resumed = 0;
  for (const document of due.docs) {
    const uid = document.ref.parent.parent?.id;
    const intentID = document.id;
    if (!validStoredID(uid) || !canonicalInstallationID.test(intentID)) continue;
    const itemSnapshot = await db.doc(`users/${uid}/notificationInbox/${intentID}`).get();
    const inbox = canonicalInbox(
      itemSnapshot.data(), uid, itemSnapshot.data()?.householdID, intentID,
    );
    if (inbox == null) continue;
    await resumeNotificationManifestAt({
      db, uid, intentID, inbox, now: trustedNow,
    });
    resumed += 1;
  }
  return { due: due.size, resumed };
}

export async function recoverNotificationDigestsAt({
  db,
  projectID,
  bindingKeyVersion = null,
  now = new Date(),
}) {
  const trustedNow = trustedTimestamp(now);
  const due = await db.collectionGroup("notificationDigests")
    .where("status", "==", "collecting")
    .where("nextFinalizeAt", "<=", trustedNow)
    .orderBy("nextFinalizeAt")
    .orderBy(FieldPath.documentId())
    .limit(100)
    .get();
  let finalized = 0;
  for (const document of due.docs) {
    const uid = document.ref.parent.parent?.id;
    if (!validStoredID(uid)) continue;
    const result = await finalizeNotificationDigestAt({
      db, uid, digestID: document.id, projectID, bindingKeyVersion, now,
    });
    if (["ready", "cancelled", "blocked"].includes(result.status)) finalized += 1;
  }
  let recoveredReady = 0;
  if (Number.isInteger(bindingKeyVersion) && bindingKeyVersion > 0) {
    const cursorRef = db.doc("systemConfig/notificationDigestReadyRecoveryV2");
    const cursorSnapshot = await cursorRef.get();
    const cursor = canonicalReadyRecoveryCursor(cursorSnapshot.data());
    let query = db.collectionGroup("notificationDigests")
      .where("status", "==", "ready")
      .where("readyAt", ">=", Timestamp.fromMillis(0))
      .orderBy("readyAt", "desc")
      .orderBy(FieldPath.documentId(), "desc");
    if (cursor != null) {
      query = query.startAfter(cursor.cursorReadyAt, cursor.cursorDocumentPath);
    }
    const ready = await query.limit(100).get();
    for (const document of ready.docs) {
      try {
        const uid = document.ref.parent.parent?.id;
        const digest = validStoredID(uid)
          ? canonicalDigest(document.data(), uid, document.id)
          : null;
        if (digest?.status !== "ready") continue;
        const summaryID = intentIDFor({
          householdID: digest.householdID,
          sourceType: "notificationDigest",
          sourcePath: `notificationDigests/${document.id}`,
          sourceRevision: 1,
          level: digest.mode === "burst" ? "burstSummary" : "dailySummary",
          recipientID: uid,
          recipientJoinedAtSnapshot: digest.recipientJoinedAtSnapshot,
        });
        const summary = db.doc(`users/${uid}/notificationInbox/${summaryID}`);
        const manifest = db.doc(
          `users/${uid}/notificationDeliveryManifests/${summaryID}`,
        );
        const [summarySnapshot, manifestSnapshot] = await Promise.all([
          summary.get(), manifest.get(),
        ]);
        const inbox = canonicalInbox(
          summarySnapshot.data(), uid, digest.householdID, summaryID,
        );
        if (inbox?.status !== "active" || inbox.sourceType !== "notificationDigest" ||
            inbox.sourceID !== document.id ||
            (manifestSnapshot.exists &&
              manifestSnapshot.data()?.status !== "materializing")) continue;
        const result = await materializeNotificationDeliveriesAt({
          db, uid, intentID: summaryID, now, bindingKeyVersion,
        });
        if (result.status === "complete") recoveredReady += 1;
      } catch {
        // One malformed recovery candidate must not starve later ready summaries.
      }
    }
    const last = ready.docs.at(-1);
    const nextReadyAt = last?.data()?.readyAt;
    if (last != null && nextReadyAt instanceof Timestamp) {
      await db.runTransaction(async (transaction) => {
        const freshSnapshot = await transaction.get(cursorRef);
        const fresh = canonicalReadyRecoveryCursor(freshSnapshot.data());
        if (!sameReadyRecoveryCursor(fresh, cursor)) return;
        if (ready.size === 100) {
          transaction.set(cursorRef, {
            schemaVersion: 1,
            cursorReadyAt: nextReadyAt,
            cursorDocumentPath: last.ref.path,
            updatedAt: trustedNow,
          });
        } else if (freshSnapshot.exists) {
          transaction.delete(cursorRef);
        }
      });
    } else if (ready.empty && cursor != null) {
      await db.runTransaction(async (transaction) => {
        const freshSnapshot = await transaction.get(cursorRef);
        const fresh = canonicalReadyRecoveryCursor(freshSnapshot.data());
        if (sameReadyRecoveryCursor(fresh, cursor)) transaction.delete(cursorRef);
      });
    }
  }
  return { due: due.size, finalized, recoveredReady };
}

export function deliveryIDFor(intentID, installationHash) {
  return sha256(stableJSON([intentID, installationHash]));
}

export function intentIDFor({
  householdID,
  sourceType,
  sourcePath,
  sourceRevision,
  level,
  recipientID,
  recipientJoinedAtSnapshot,
}) {
  return sha256(stableJSON([
    householdID, sourceType, sourcePath, sourceRevision, level, recipientID,
    recipientJoinedAtSnapshot.seconds, recipientJoinedAtSnapshot.nanoseconds,
  ]));
}

function collectionForSource(sourceType) {
  return {
    medicationOccurrence: "medicationOccurrences",
    task: "tasks",
    taskResponsibilityTransfer: "taskResponsibilityTransfers",
    handoffSession: "handoffSessions",
  }[sourceType];
}

function positiveKeyVersion(keyRing) {
  if (!(keyRing instanceof Map)) return null;
  const versions = [...keyRing.entries()]
    .filter(([version, secret]) => Number.isInteger(version) && version > 0 &&
      typeof secret === "string" && secret.length > 0)
    .map(([version]) => version);
  return versions.length === 0 ? null : Math.max(...versions);
}

function notificationCandidates({ sourceType, sourceID, sourceData, ownerID, now }) {
  const canonical = canonicalNotificationSource(
    sourceType, sourceID ?? sourceData?.id, sourceData, ownerID,
  );
  if (canonical == null) return [];
  sourceData = canonical;
  if (sourceType === "medicationOccurrence") {
    if (sourceData.outcomeStatus !== "unresolved" ||
        !(sourceData.dueAt instanceof Timestamp) ||
        !["claimed", "unclaimed"].includes(sourceData.responsibilityStatus) ||
        (sourceData.responsibilityStatus === "claimed" &&
          !validStoredID(sourceData.responsibleByID)) ||
        (sourceData.responsibilityStatus === "unclaimed" &&
          sourceData.responsibleByID != null)) return [];
    const definitions = [
      ["due", 0, 15], ["overdue15", 15, 30], ["overdue30", 30, 45],
    ];
    return definitions.flatMap(([level, start, end]) => {
      const semanticAt = Timestamp.fromMillis(sourceData.dueAt.toMillis() + start * 60_000);
      const expiresAt = Timestamp.fromMillis(sourceData.dueAt.toMillis() + end * 60_000);
      return now.toMillis() >= semanticAt.toMillis() && now.toMillis() < expiresAt.toMillis()
        ? [{ category: "medication", level, semanticAt, expiresAt }]
        : [];
    });
  }
  if (sourceType === "taskResponsibilityTransfer") {
    if (sourceData.status !== "pending" || !validStoredID(sourceData.consentByID) ||
        !(sourceData.createdAt instanceof Timestamp)) return [];
    return [{
      category: "assignment", level: "responsibilityProposal",
      semanticAt: sourceData.createdAt,
      expiresAt: Timestamp.fromMillis(sourceData.createdAt.toMillis() + 86_400_000),
    }];
  }
  if (sourceType === "handoffSession") {
    if (sourceData.status !== "offered" || !validStoredID(sourceData.recipientID) ||
        !(sourceData.offeredAt instanceof Timestamp) ||
        !(sourceData.plannedEndAt instanceof Timestamp) ||
        sourceData.offeredAt.toMillis() >= sourceData.plannedEndAt.toMillis()) return [];
    return [{
      category: "assignment", level: "handoffOffer",
      semanticAt: sourceData.offeredAt,
      expiresAt: Timestamp.fromMillis(Math.min(
        sourceData.plannedEndAt.toMillis(),
        sourceData.offeredAt.toMillis() + 86_400_000,
      )),
    }];
  }
  if (sourceType === "task") {
    if (sourceData.status !== "unclaimed") return [];
    const result = [];
    if (sourceData.kind === "oneOff" && sourceData.priority === "urgent" &&
        sourceData.createdAt instanceof Timestamp) {
      result.push({
        category: "urgent", level: "urgentUnclaimed",
        semanticAt: sourceData.createdAt,
        expiresAt: Timestamp.fromMillis(sourceData.createdAt.toMillis() + 86_400_000),
      });
    }
    if (sourceData.assignmentMode === "direct" &&
        validStoredID(sourceData.assignmentRequestID) &&
        validStoredID(sourceData.requestedToID) &&
        sourceData.assignmentRequestedAt instanceof Timestamp) {
      result.push({
        category: "assignment", level: "directAssignment",
        semanticAt: sourceData.assignmentRequestedAt,
        expiresAt: Timestamp.fromMillis(
          sourceData.assignmentRequestedAt.toMillis() + 86_400_000,
        ),
      });
    }
    return result;
  }
  return [];
}

function recipientsForCandidate({ candidate, sourceData, members, preferences }) {
  const memberIDs = [...members.keys()];
  if (candidate.level === "responsibilityProposal") {
    return [mandatoryRecipient(sourceData.consentByID, "directTarget", (preference) =>
      preference?.assignmentAlertsEnabled === true && preference.pushEnabled === true)];
  }
  if (candidate.level === "handoffOffer") {
    return [mandatoryRecipient(sourceData.recipientID, "handoffRecipient", (preference) =>
      preference?.assignmentAlertsEnabled === true && preference.pushEnabled === true)];
  }
  if (candidate.level === "directAssignment") {
    return [mandatoryRecipient(sourceData.requestedToID, "directTarget", (preference) =>
      preference?.assignmentAlertsEnabled === true && preference.pushEnabled === true)];
  }
  if (candidate.category === "urgent") {
    return memberIDs.filter((uid) => preferences.get(uid)?.urgentAlertsEnabled === true)
      .map((uid) => optInRecipient(
        uid, "urgentOptIn", (preference) => preference?.urgentAlertsEnabled === true,
      ));
  }
  if (sourceData.responsibilityStatus === "claimed") {
    const responsible = mandatoryRecipient(
      sourceData.responsibleByID,
      "responsible",
      (preference) => preference?.medicationRemindersEnabled === true &&
        preference.pushEnabled === true,
    );
    if (candidate.level === "due") return [responsible];
    const backups = memberIDs.filter((uid) => {
      const preference = preferences.get(uid);
      return uid !== sourceData.responsibleByID &&
        preference?.medicationRemindersEnabled === true &&
        preference.backupForMemberIDs.includes(sourceData.responsibleByID);
    }).map((uid) => optInRecipient(
      uid,
      "backup",
      (preference) => preference?.medicationRemindersEnabled === true &&
        preference.pushEnabled === true &&
        preference.backupForMemberIDs.includes(sourceData.responsibleByID),
    ));
    return [responsible, ...backups];
  }
  return memberIDs.filter((uid) =>
    preferences.get(uid)?.medicationRemindersEnabled === true)
    .map((uid) => optInRecipient(
      uid,
      "medicationOptIn",
      (preference) => preference?.medicationRemindersEnabled === true,
    ));
}

function mandatoryRecipient(uid, routeReason, pushEligible) {
  return {
    uid,
    routeReason,
    requiresOptIn: false,
    inboxEligible: () => true,
    pushEligible,
  };
}

function optInRecipient(uid, routeReason, inboxEligible) {
  return {
    uid,
    routeReason,
    requiresOptIn: true,
    inboxEligible,
    pushEligible: (preference) => inboxEligible(preference) &&
      preference?.pushEnabled === true,
  };
}

function sourceMatchesCandidate(
  sourceType, sourceID, source, candidate, recipientID, ownerID,
) {
  const matching = notificationCandidates({
    sourceType,
    sourceID,
    sourceData: source,
    ownerID,
    now: candidate.semanticAt,
  }).some((item) => item.level === candidate.level &&
    item.semanticAt.isEqual(candidate.semanticAt));
  if (!matching) return false;
  if (candidate.level === "responsibilityProposal") return source.consentByID === recipientID;
  if (candidate.level === "handoffOffer") return source.recipientID === recipientID;
  if (candidate.level === "directAssignment") return source.requestedToID === recipientID;
  if (source.responsibilityStatus === "claimed" && candidate.level === "due") {
    return source.responsibleByID === recipientID;
  }
  return true;
}

async function cancelTerminalSourceIntentsAt({
  db, householdID, sourceType, sourceID, source, memberIDs, ownerID, now,
}) {
  const sourceData = (await source.get()).data();
  if (notificationCandidates({
    sourceType, sourceID, sourceData, ownerID, now,
  }).length > 0) return 0;
  const sourcePath = `${collectionForSource(sourceType)}/${sourceID}`;
  let cancelled = 0;
  for (const uid of memberIDs) {
    const items = await db.collection(`users/${uid}/notificationInbox`)
      .where("sourcePath", "==", sourcePath)
      .get();
    for (const item of items.docs) {
      if (item.data()?.householdID !== householdID || item.data()?.status !== "active") {
        continue;
      }
      const changed = await db.runTransaction(async (transaction) => {
        const [freshSource, freshItem] = await Promise.all([
          transaction.get(source), transaction.get(item.ref),
        ]);
        if (notificationCandidates({
          sourceType, sourceID, sourceData: freshSource.data(), ownerID, now,
        }).length > 0 ||
            freshItem.data()?.status !== "active") return false;
        transaction.update(item.ref, {
          status: "cancelled", cancelReason: "sourceTerminal",
          cancelledAt: now, nextDispatchAt: null, updatedAt: now,
        });
        return true;
      });
      if (changed) cancelled += 1;
    }
  }
  return cancelled;
}

async function reconcileActiveSourceIntentsAt({
  db, householdID, sourceType, sourceID, source, sourceData, memberIDs,
  ownerID, now,
}) {
  const sourcePath = `${collectionForSource(sourceType)}/${sourceID}`;
  for (const uid of memberIDs) {
    const items = await db.collection(`users/${uid}/notificationInbox`)
      .where("sourcePath", "==", sourcePath).get();
    for (const document of items.docs) {
      const inbox = canonicalInbox(document.data(), uid, householdID, document.id);
      if (inbox == null || inbox.status !== "active" ||
          (inbox.sourceRevision === sourceData.revision &&
            sourceMatchesInbox(sourceData, inbox, now, ownerID))) continue;
      await db.runTransaction(async (transaction) => {
        const [freshSource, freshItem] = await Promise.all([
          transaction.get(source), transaction.get(document.ref),
        ]);
        const current = canonicalInbox(
          freshItem.data(), uid, householdID, document.id,
        );
        if (current == null || current.status !== "active" ||
            (current.sourceRevision === freshSource.data()?.revision &&
              sourceMatchesInbox(freshSource.data(), current, now, ownerID))) return;
        transaction.update(document.ref, {
          status: "cancelled", cancelReason: "sourceChanged",
          cancelledAt: now, nextDispatchAt: null, updatedAt: now,
        });
      });
    }
  }
}

function canonicalNotificationSource(sourceType, sourceID, data, ownerID) {
  try {
    if (sourceType === "task") return canonicalNotificationTask(sourceID, data);
    if (sourceType === "medicationOccurrence") {
      return canonicalMedicationOccurrence(sourceID, data);
    }
    if (sourceType === "taskResponsibilityTransfer") {
      return canonicalTransfer(sourceID, data);
    }
    if (sourceType === "handoffSession") {
      return canonicalSession(sourceID, data, ownerID);
    }
  } catch {
    return null;
  }
  return null;
}

function canonicalNotificationTask(taskID, data) {
  const allowed = new Set([
    "id", "title", "category", "dueTime", "kind", "priority", "routineID",
    "petID", "petName", "status", "assignmentRequestID", "requestedByID",
    "requestedByName", "assignmentMode", "requestedToID", "requestedToName",
    "assignmentRequestedAt", "assigneeID", "assigneeName", "claimedAt",
    "createdByID", "createdBy", "createdAt", "completedByID", "completedBy",
    "completedAt", "revision", "lastCollaborationAction",
    "lastCollaborationActorID", "lastCollaborationActorName",
    "lastCollaborationTargetID", "lastCollaborationTargetName",
    "lastCollaborationRequestID", "lastCollaborationAt",
  ]);
  const required = [
    "id", "title", "category", "dueTime", "kind", "priority", "routineID",
    "status", "assignmentRequestID", "requestedByID", "requestedByName",
    "assignmentMode", "requestedToID", "requestedToName", "assignmentRequestedAt",
    "assigneeID", "assigneeName", "claimedAt", "createdByID", "createdBy",
    "createdAt", "completedByID", "completedBy", "completedAt", "revision",
  ];
  if (data == null || Object.keys(data).some((key) => !allowed.has(key)) ||
      required.some((key) => !Object.hasOwn(data, key)) || data.id !== taskID ||
      !validStoredID(taskID) || typeof data.title !== "string" ||
      data.title.length === 0 || data.title.length > 120 ||
      !["feeding", "walking", "medication", "grooming", "other"].includes(
        data.category,
      ) || !(data.dueTime instanceof Timestamp) ||
      !["routine", "oneOff"].includes(data.kind) ||
      !["normal", "urgent"].includes(data.priority) ||
      !["unclaimed", "claimed", "completed"].includes(data.status) ||
      !validStoredID(data.createdByID) || !validStoredText(data.createdBy, 50) ||
      !(data.createdAt instanceof Timestamp) || !Number.isInteger(data.revision) ||
      data.revision < 0 || (data.routineID != null && !validStoredID(data.routineID)) ||
      (Object.hasOwn(data, "petID") !== Object.hasOwn(data, "petName")) ||
      (Object.hasOwn(data, "petID") &&
        (!validStoredID(data.petID) || !validStoredText(data.petName, 60)))) return null;
  const noAssignee = data.assigneeID == null && data.assigneeName == null &&
    data.claimedAt == null;
  const noCompletion = data.completedByID == null && data.completedBy == null &&
    data.completedAt == null;
  if (data.status !== "unclaimed" || !noAssignee || !noCompletion) return data;
  const noRequest = data.assignmentRequestID == null && data.assignmentMode == null &&
    data.requestedByID == null && data.requestedByName == null &&
    data.requestedToID == null && data.requestedToName == null &&
    data.assignmentRequestedAt == null;
  const direct = validStoredID(data.assignmentRequestID) &&
    data.assignmentMode === "direct" && validStoredID(data.requestedByID) &&
    validStoredText(data.requestedByName, 50) && validStoredID(data.requestedToID) &&
    validStoredText(data.requestedToName, 50) &&
    data.requestedByID !== data.requestedToID &&
    data.assignmentRequestedAt instanceof Timestamp;
  const open = validStoredID(data.assignmentRequestID) &&
    data.assignmentMode === "open" && validStoredID(data.requestedByID) &&
    validStoredText(data.requestedByName, 50) && data.requestedToID == null &&
    data.requestedToName == null && data.assignmentRequestedAt instanceof Timestamp;
  return noRequest || direct || open ? data : null;
}

function canonicalMedicationOccurrence(sourceID, data) {
  const keys = new Set([
    "schemaVersion", "id", "medicationID", "scheduleVersionID",
    "scheduleVersion", "slotID", "localDate", "dueAt", "timeZoneIdentifier",
    "petID", "petName", "medicationName", "doseText", "instructions",
    "responsibilityStatus", "responsibleByID", "responsibleByName", "claimedAt",
    "outcomeStatus", "outcomeByID", "outcomeByName", "outcomeAt",
    "skippedReasonCode", "skippedReasonNote", "materializedAt", "revision",
  ]);
  if (!exactKeys(data, keys) || data.schemaVersion !== 1 || data.id !== sourceID ||
      !validStoredID(sourceID) || !validStoredID(data.medicationID) ||
      !validStoredID(data.scheduleVersionID) || !Number.isInteger(data.scheduleVersion) ||
      data.scheduleVersion < 1 || !validStoredID(data.slotID) ||
      typeof data.localDate !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(data.localDate) ||
      !(data.dueAt instanceof Timestamp) || !validTimeZone(data.timeZoneIdentifier) ||
      !validStoredID(data.petID) || !validStoredText(data.petName, 60) ||
      !validStoredText(data.medicationName, 120) || !validStoredText(data.doseText, 80) ||
      !(data.instructions == null || validStoredText(data.instructions, 500)) ||
      !(data.materializedAt instanceof Timestamp) || !Number.isInteger(data.revision) ||
      data.revision < 0 || !["claimed", "unclaimed"].includes(
        data.responsibilityStatus,
      ) || !["unresolved", "administered", "skipped"].includes(data.outcomeStatus)) {
    return null;
  }
  const responsibilityValid = data.responsibilityStatus === "unclaimed"
    ? data.responsibleByID == null && data.responsibleByName == null &&
      data.claimedAt == null
    : validStoredID(data.responsibleByID) &&
      validStoredText(data.responsibleByName, 50) && data.claimedAt instanceof Timestamp;
  const unresolved = data.outcomeStatus === "unresolved" &&
    data.outcomeByID == null && data.outcomeByName == null && data.outcomeAt == null &&
    data.skippedReasonCode == null && data.skippedReasonNote == null;
  const terminal = data.outcomeStatus !== "unresolved" &&
    validStoredID(data.outcomeByID) && validStoredText(data.outcomeByName, 50) &&
    data.outcomeAt instanceof Timestamp;
  return responsibilityValid && (unresolved || terminal) ? data : null;
}

function validStoredText(value, max) {
  return typeof value === "string" && value.trim().length > 0 && value.length <= max;
}

function notificationDispatchPlan({
  household, preference, recipientID, joinedAt, candidate, baseAt, now,
}) {
  if (candidate.category !== "assignment") {
    return { nextDispatchAt: now, coalescingKey: null, digest: null };
  }
  const window = digestWindow({ household, preference, now: baseAt });
  const digestID = sha256(stableJSON([
    household.id ?? null,
    recipientID,
    joinedAt.seconds,
    joinedAt.nanoseconds,
    window.mode,
    window.startAt.toMillis(),
    window.endAt.toMillis(),
    preference.revision,
  ]));
  return {
    nextDispatchAt: null,
    coalescingKey: digestID,
    digest: {
      id: digestID,
      payload: {
        schemaVersion: 1,
        id: digestID,
        householdID: household.id,
        recipientID,
        recipientJoinedAtSnapshot: joinedAt,
        mode: window.mode,
        coalescingKey: digestID,
        windowStartAt: window.startAt,
        windowEndAt: window.endAt,
        catchUpUntilAt: window.catchUpUntilAt,
        preferenceRevision: preference.revision,
        status: "collecting",
        cancelReason: null,
        safeErrorCode: null,
        createdAt: now,
        updatedAt: now,
        nextFinalizeAt: Timestamp.fromMillis(window.endAt.toMillis() + 5_000),
        readyAt: null,
        cancelledAt: null,
        blockedAt: null,
      },
    },
  };
}

function digestWindow({ household, preference, now }) {
  if (preference.summaryEnabled !== true) {
    const start = Math.floor(now.toMillis() / 120_000) * 120_000;
    const end = start + 120_000;
    return {
      mode: "burst",
      startAt: Timestamp.fromMillis(start),
      endAt: Timestamp.fromMillis(end),
      catchUpUntilAt: Timestamp.fromMillis(end + 600_000),
    };
  }
  const zone = household.timeZoneIdentifier;
  const localNow = DateTime.fromMillis(now.toMillis(), { zone });
  const hour = Math.floor(preference.summaryMinute / 60);
  const minute = preference.summaryMinute % 60;
  let end = DateTime.fromObject({
    year: localNow.year, month: localNow.month, day: localNow.day, hour, minute,
  }, { zone });
  if (end.toMillis() <= now.toMillis()) end = end.plus({ days: 1 });
  const start = end.minus({ days: 1 });
  return {
    mode: "daily",
    startAt: Timestamp.fromMillis(start.toUTC().toMillis()),
    endAt: Timestamp.fromMillis(end.toUTC().toMillis()),
    catchUpUntilAt: Timestamp.fromMillis(end.plus({ days: 1 }).toUTC().toMillis()),
  };
}

function plannedMedicationOccurrences({
  medicationID, medicationData, versionID, versionData, now,
}) {
  medicationData = canonicalMedicationPlan(medicationID, medicationData);
  versionData = canonicalMedicationVersion(
    medicationID, versionID, versionData,
  );
  if (medicationData == null || versionData == null ||
      !validTimeZone(versionData.timeZoneIdentifier) ||
      !Array.isArray(versionData.weekdays) || !Array.isArray(versionData.slots) ||
      typeof versionData.effectiveFromLocalDate !== "string") return [];
  const localNow = DateTime.fromMillis(now.toMillis(), {
    zone: versionData.timeZoneIdentifier,
  });
  const result = [];
  for (const day of [localNow, localNow.minus({ days: 1 })]) {
    const localDate = day.toFormat("yyyy-MM-dd");
    if (localDate < versionData.effectiveFromLocalDate ||
        (typeof versionData.effectiveUntilLocalDate === "string" &&
          localDate >= versionData.effectiveUntilLocalDate) ||
        !versionData.weekdays.includes(day.weekday % 7 + 1)) continue;
    for (const slot of versionData.slots) {
      if (!validMedicationSlot(slot)) continue;
      const due = DateTime.fromObject({
        year: day.year, month: day.month, day: day.day,
        hour: slot.hour, minute: slot.minute,
      }, { zone: versionData.timeZoneIdentifier });
      if (!due.isValid || due.getPossibleOffsets().length !== 1) continue;
      const dueAt = Timestamp.fromMillis(due.toUTC().toMillis());
      if (now.toMillis() < dueAt.toMillis() ||
          now.toMillis() >= dueAt.toMillis() + 45 * 60_000) continue;
      result.push({
        id: `${medicationID}_${versionID}_${localDate}_${slot.slotID}`,
        medicationID,
        versionID,
        localDate,
        slot,
        dueAt,
        versionData,
      });
    }
  }
  return result;
}

function canonicalMedicationPlan(medicationID, data) {
  const keys = new Set([
    "schemaVersion", "id", "petID", "displayName", "purpose",
    "possibleSideEffects", "isActive", "currentScheduleVersion",
    "currentScheduleVersionID", "revision", "createdAt", "createdByID",
    "createdByName", "updatedAt", "updatedByID",
  ]);
  return exactKeys(data, keys) && data.schemaVersion === 1 &&
    data.id === medicationID && validStoredID(medicationID) &&
    validStoredID(data.petID) && validStoredText(data.displayName, 120) &&
    (data.purpose == null || validStoredText(data.purpose, 500)) &&
    (data.possibleSideEffects == null || validStoredText(data.possibleSideEffects, 500)) &&
    typeof data.isActive === "boolean" &&
    Number.isInteger(data.currentScheduleVersion) && data.currentScheduleVersion >= 1 &&
    validStoredID(data.currentScheduleVersionID) && Number.isInteger(data.revision) &&
    data.revision >= 0 && data.createdAt instanceof Timestamp &&
    validStoredID(data.createdByID) && validStoredText(data.createdByName, 50) &&
    data.updatedAt instanceof Timestamp && validStoredID(data.updatedByID)
    ? data
    : null;
}

function canonicalMedicationVersion(medicationID, versionID, data) {
  const keys = new Set([
    "schemaVersion", "id", "medicationID", "version", "petID", "petName",
    "medicationName", "weekdays", "slots", "timeZoneIdentifier", "dstPolicy",
    "effectiveFromLocalDate", "effectiveUntilLocalDate", "createdAt",
    "createdByID", "createdByName", "closedAt", "closedByID",
    "replacedByVersionID", "revision",
  ]);
  if (!exactKeys(data, keys) || data.schemaVersion !== 1 || data.id !== versionID ||
      data.medicationID !== medicationID || !Number.isInteger(data.version) ||
      data.version < 1 || !validStoredID(data.petID) ||
      !validStoredText(data.petName, 60) || !validStoredText(data.medicationName, 120) ||
      !Array.isArray(data.weekdays) || data.weekdays.length < 1 ||
      data.weekdays.length > 7 || new Set(data.weekdays).size !== data.weekdays.length ||
      data.weekdays.some((day) => !Number.isInteger(day) || day < 1 || day > 7) ||
      !Array.isArray(data.slots) || data.slots.length < 1 ||
      data.slots.some((slot) => !validMedicationSlot(slot)) ||
      !validTimeZone(data.timeZoneIdentifier) || data.dstPolicy !== "reject" ||
      typeof data.effectiveFromLocalDate !== "string" ||
      !/^\d{4}-\d{2}-\d{2}$/.test(data.effectiveFromLocalDate) ||
      !(data.effectiveUntilLocalDate == null ||
        (typeof data.effectiveUntilLocalDate === "string" &&
          /^\d{4}-\d{2}-\d{2}$/.test(data.effectiveUntilLocalDate))) ||
      !(data.createdAt instanceof Timestamp) || !validStoredID(data.createdByID) ||
      !validStoredText(data.createdByName, 50) ||
      !(data.closedAt == null || data.closedAt instanceof Timestamp) ||
      !(data.closedByID == null || validStoredID(data.closedByID)) ||
      !(data.replacedByVersionID == null || validStoredID(data.replacedByVersionID)) ||
      !Number.isInteger(data.revision) || data.revision < 0) return null;
  return data;
}

function canonicalMedicationOccurrenceRelation({
  occurrenceID, occurrence, medication, version,
}) {
  occurrence = canonicalMedicationOccurrence(occurrenceID, occurrence);
  if (occurrence == null) return false;
  medication = canonicalMedicationPlan(occurrence.medicationID, medication);
  version = canonicalMedicationVersion(
    occurrence.medicationID, occurrence.scheduleVersionID, version,
  );
  if (medication == null || version == null ||
      version.version !== occurrence.scheduleVersion ||
      occurrenceID !== `${occurrence.medicationID}_${occurrence.scheduleVersionID}_` +
        `${occurrence.localDate}_${occurrence.slotID}`) return false;
  const day = DateTime.fromFormat(
    occurrence.localDate, "yyyy-MM-dd",
    { zone: version.timeZoneIdentifier, setZone: true },
  );
  const slot = version.slots.find((candidate) => candidate.slotID === occurrence.slotID);
  if (!day.isValid || day.toFormat("yyyy-MM-dd") !== occurrence.localDate ||
      slot == null || !version.weekdays.includes(day.weekday % 7 + 1) ||
      occurrence.localDate < version.effectiveFromLocalDate ||
      (version.effectiveUntilLocalDate != null &&
        occurrence.localDate >= version.effectiveUntilLocalDate)) return false;
  const due = DateTime.fromObject({
    year: day.year, month: day.month, day: day.day,
    hour: slot.hour, minute: slot.minute,
  }, { zone: version.timeZoneIdentifier });
  return due.isValid && due.getPossibleOffsets().length === 1 &&
    occurrence.dueAt.toMillis() === due.toUTC().toMillis() &&
    occurrence.timeZoneIdentifier === version.timeZoneIdentifier &&
    occurrence.petID === version.petID && occurrence.petName === version.petName &&
    occurrence.medicationName === version.medicationName &&
    occurrence.doseText === slot.doseText &&
    occurrence.instructions === slot.instructions;
}

function canonicalReadyRecoveryCursor(data) {
  const keys = new Set([
    "schemaVersion", "cursorReadyAt", "cursorDocumentPath", "updatedAt",
  ]);
  const path = typeof data?.cursorDocumentPath === "string"
    ? data.cursorDocumentPath.split("/")
    : [];
  return exactKeys(data, keys) && data.schemaVersion === 1 &&
    data.cursorReadyAt instanceof Timestamp &&
    path.length === 4 && path[0] === "users" && validStoredID(path[1]) &&
    path[2] === "notificationDigests" && canonicalInstallationID.test(path[3]) &&
    data.updatedAt instanceof Timestamp
    ? data
    : null;
}

function sameReadyRecoveryCursor(left, right) {
  if (left == null || right == null) return left == null && right == null;
  return left.cursorDocumentPath === right.cursorDocumentPath &&
    left.cursorReadyAt.isEqual(right.cursorReadyAt);
}

function validMedicationSlot(slot) {
  return slot != null && typeof slot === "object" &&
    validStoredID(slot.slotID) && Number.isInteger(slot.hour) &&
    slot.hour >= 0 && slot.hour <= 23 && Number.isInteger(slot.minute) &&
    slot.minute >= 0 && slot.minute <= 59 &&
    typeof slot.doseText === "string" && slot.doseText.length > 0 &&
    slot.doseText.length <= 80 &&
    (slot.instructions == null ||
      (typeof slot.instructions === "string" && slot.instructions.length <= 500));
}

function sameMedicationVersion(current, planned) {
  const left = canonicalMedicationVersion(planned.medicationID, planned.id, current);
  const right = canonicalMedicationVersion(planned.medicationID, planned.id, planned);
  return left != null && right != null && stableJSON(left) === stableJSON(right);
}

function medicationOccurrencePayload(plan, now) {
  const version = plan.versionData;
  return {
    schemaVersion: 1,
    id: plan.id,
    medicationID: plan.medicationID,
    scheduleVersionID: plan.versionID,
    scheduleVersion: version.version,
    slotID: plan.slot.slotID,
    localDate: plan.localDate,
    dueAt: plan.dueAt,
    timeZoneIdentifier: version.timeZoneIdentifier,
    petID: version.petID,
    petName: version.petName,
    medicationName: version.medicationName,
    doseText: plan.slot.doseText,
    instructions: plan.slot.instructions,
    responsibilityStatus: "unclaimed",
    responsibleByID: null,
    responsibleByName: null,
    claimedAt: null,
    outcomeStatus: "unresolved",
    outcomeByID: null,
    outcomeByName: null,
    outcomeAt: null,
    skippedReasonCode: null,
    skippedReasonNote: null,
    materializedAt: now,
    revision: 0,
  };
}

function canonicalDigest(data, uid, id) {
  const keys = new Set([
    "schemaVersion", "id", "householdID", "recipientID",
    "recipientJoinedAtSnapshot", "mode", "coalescingKey", "windowStartAt",
    "windowEndAt", "catchUpUntilAt", "preferenceRevision", "status",
    "cancelReason", "safeErrorCode", "createdAt", "updatedAt",
    "nextFinalizeAt", "readyAt", "cancelledAt", "blockedAt",
  ]);
  if (!exactKeys(data, keys) || data.schemaVersion !== 1 || data.id !== id ||
      data.recipientID !== uid || !validStoredID(data.householdID) ||
      !(data.recipientJoinedAtSnapshot instanceof Timestamp) ||
      !["burst", "daily"].includes(data.mode) || data.coalescingKey !== id ||
      !(data.windowStartAt instanceof Timestamp) ||
      !(data.windowEndAt instanceof Timestamp) ||
      !(data.catchUpUntilAt instanceof Timestamp) ||
      data.windowStartAt.toMillis() >= data.windowEndAt.toMillis() ||
      data.windowEndAt.toMillis() >= data.catchUpUntilAt.toMillis() ||
      !Number.isInteger(data.preferenceRevision) || data.preferenceRevision < 1 ||
      !["collecting", "ready", "cancelled", "blocked"].includes(data.status) ||
      !(data.createdAt instanceof Timestamp) || !(data.updatedAt instanceof Timestamp)) {
    return null;
  }
  if (data.status === "collecting") return data.nextFinalizeAt instanceof Timestamp &&
    data.readyAt == null && data.cancelledAt == null && data.blockedAt == null &&
    data.cancelReason == null && data.safeErrorCode == null ? data : null;
  if (data.status === "ready") return data.nextFinalizeAt == null &&
    data.readyAt instanceof Timestamp && data.cancelledAt == null &&
    data.blockedAt == null && data.cancelReason == null && data.safeErrorCode == null
    ? data : null;
  if (data.status === "cancelled") return data.nextFinalizeAt == null &&
    ["noValidSource", "availabilityExpired", "policyChanged",
      "membershipEnded"].includes(data.cancelReason) &&
    data.cancelledAt instanceof Timestamp && data.readyAt == null &&
    data.blockedAt == null && data.safeErrorCode == null ? data : null;
  return data.nextFinalizeAt == null && data.safeErrorCode === "tooManyCandidates" &&
    data.blockedAt instanceof Timestamp && data.readyAt == null &&
    data.cancelledAt == null && data.cancelReason == null ? data : null;
}

async function validateDigestOriginalsAt({ db, uid, digest, now, cutoff }) {
  let last = null;
  let examined = 0;
  while (examined < 1000) {
    let query = db.collection(`users/${uid}/notificationInbox`)
      .where("householdID", "==", digest.householdID)
      .where("recipientJoinedAtSnapshot", "==", digest.recipientJoinedAtSnapshot)
      .where("category", "==", "assignment")
      .where("sourceType", "in", ["task", "taskResponsibilityTransfer", "handoffSession"])
      .where("coalescingKey", "==", digest.coalescingKey)
      .orderBy("createdAt")
      .orderBy(FieldPath.documentId())
      .limit(Math.min(100, 1000 - examined));
    if (last != null) query = query.startAfter(last);
    const page = await query.get();
    for (const candidate of page.docs) {
      examined += 1;
      const inbox = canonicalInbox(
        candidate.data(), uid, digest.householdID, candidate.id,
      );
      if (inbox == null || inbox.status !== "active") continue;
      const source = sourceReference(db, uid, digest.householdID, inbox);
      const sourceSnapshot = await source.get();
      const semanticAt = sourceSnapshot.exists
        ? semanticInstantForSource(inbox, sourceSnapshot.data())
        : null;
      if (sourceSnapshot.exists && sourceMatchesInbox(
        sourceSnapshot.data(), inbox, now,
      ) && semanticAt instanceof Timestamp && semanticAt.toMillis() >= cutoff) {
        return { status: "valid", inbox, intent: candidate.ref, source };
      }
    }
    last = page.docs.at(-1) ?? last;
    if (page.size < 100) return { status: "noValidSource" };
  }
  if (last != null) {
    const overflow = await db.collection(`users/${uid}/notificationInbox`)
      .where("householdID", "==", digest.householdID)
      .where("recipientJoinedAtSnapshot", "==", digest.recipientJoinedAtSnapshot)
      .where("category", "==", "assignment")
      .where("sourceType", "in", ["task", "taskResponsibilityTransfer", "handoffSession"])
      .where("coalescingKey", "==", digest.coalescingKey)
      .orderBy("createdAt").orderBy(FieldPath.documentId())
      .startAfter(last).limit(1).get();
    if (!overflow.empty) return { status: "blocked" };
  }
  return { status: "noValidSource" };
}

async function validateSummaryAuthorityAt({ db, uid, inbox, now, cutoff }) {
  if (inbox?.sourceType !== "notificationDigest") return { status: "notSummary" };
  const digestRef = sourceReference(db, uid, inbox.householdID, inbox);
  const digestSnapshot = await digestRef.get();
  const digest = canonicalDigest(digestSnapshot.data(), uid, inbox.sourceID);
  if (digest?.status !== "ready") return { status: "noValidSource", digestRef };
  const result = await validateDigestOriginalsAt({
    db, uid, digest, now, cutoff,
  });
  return { ...result, digestRef };
}

function matchingSummary(data, expected, uid, householdID, id) {
  const current = canonicalInbox(data, uid, householdID, id);
  if (current == null) return false;
  return Object.entries(expected).every(([key, value]) => {
    const actual = current[key];
    return value instanceof Timestamp
      ? actual instanceof Timestamp && actual.isEqual(value)
      : actual === value;
  });
}

async function cancelDigest(reference, expected, reason, now) {
  await reference.firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const current = canonicalDigest(snapshot.data(), expected.recipientID, expected.id);
    if (current?.status !== "collecting") return;
    transaction.update(reference, {
      status: "cancelled", cancelReason: reason, safeErrorCode: null,
      nextFinalizeAt: null, readyAt: null, cancelledAt: now, blockedAt: null,
      updatedAt: now,
    });
  });
}

async function blockDigest(reference, expected, now) {
  await reference.firestore.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const current = canonicalDigest(snapshot.data(), expected.recipientID, expected.id);
    if (current?.status !== "collecting") return;
    transaction.update(reference, {
      status: "blocked", cancelReason: null, safeErrorCode: "tooManyCandidates",
      nextFinalizeAt: null, readyAt: null, cancelledAt: null, blockedAt: now,
      updatedAt: now,
    });
  });
}

function quietEndAvailability({ preference, zone, now }) {
  if (preference.quietHoursEnabled !== true) return now;
  const local = DateTime.fromMillis(now.toMillis(), { zone });
  const minute = local.hour * 60 + local.minute;
  const start = preference.quietStartMinute;
  const end = preference.quietEndMinute;
  const inside = start < end
    ? minute >= start && minute < end
    : minute >= start || minute < end;
  if (!inside) return now;
  const endHour = Math.floor(end / 60);
  const endMinute = end % 60;
  let endLocal = DateTime.fromObject({
    year: local.year, month: local.month, day: local.day,
    hour: endHour, minute: endMinute,
  }, { zone });
  if (endLocal.toMillis() <= now.toMillis()) endLocal = endLocal.plus({ days: 1 });
  return Timestamp.fromMillis(endLocal.toUTC().toMillis());
}

function requireAuth(request) {
  const uid = request.auth?.uid;
  if (typeof uid !== "string" || uid.length === 0) {
    throw new HttpsError("unauthenticated", "Sign in before managing notifications.");
  }
  return uid;
}

function parsePreferenceInput(data) {
  exactObject(data, preferenceKeys);
  const backup = data.backupForMemberIDs;
  if (!Array.isArray(backup) || backup.length > 20 ||
      backup.some((value) => typeof value !== "string") ||
      [...new Set(backup)].length !== backup.length ||
      [...backup].sort().some((value, index) => value !== backup[index])) {
    throw new HttpsError("invalid-argument", "backupForMemberIDs is invalid.");
  }
  const input = {
    householdID: boundedID(data.householdID, "householdID"),
    expectedRevision: integerRange(data.expectedRevision, 0, Number.MAX_SAFE_INTEGER,
      "expectedRevision"),
    clientMutationID: mutationID(data.clientMutationID),
    medicationRemindersEnabled: boolean(data.medicationRemindersEnabled,
      "medicationRemindersEnabled"),
    assignmentAlertsEnabled: boolean(data.assignmentAlertsEnabled,
      "assignmentAlertsEnabled"),
    urgentAlertsEnabled: boolean(data.urgentAlertsEnabled, "urgentAlertsEnabled"),
    pushEnabled: boolean(data.pushEnabled, "pushEnabled"),
    backupForMemberIDs: backup.map((value) => boundedID(value, "backupForMemberIDs")),
    quietHoursEnabled: boolean(data.quietHoursEnabled, "quietHoursEnabled"),
    quietStartMinute: integerRange(data.quietStartMinute, 0, 1439,
      "quietStartMinute"),
    quietEndMinute: integerRange(data.quietEndMinute, 0, 1439, "quietEndMinute"),
    summaryEnabled: boolean(data.summaryEnabled, "summaryEnabled"),
    summaryMinute: integerRange(data.summaryMinute, 0, 1439, "summaryMinute"),
  };
  if (input.quietHoursEnabled && input.quietStartMinute === input.quietEndMinute) {
    throw new HttpsError("invalid-argument", "Quiet hours must have an end.");
  }
  return input;
}

function preferencePayload({ uid, input, joinedAt, zone, revision, createdAt, now }) {
  return {
    schemaVersion: 1,
    uid,
    householdID: input.householdID,
    memberJoinedAtSnapshot: joinedAt,
    medicationRemindersEnabled: input.medicationRemindersEnabled,
    assignmentAlertsEnabled: input.assignmentAlertsEnabled,
    urgentAlertsEnabled: input.urgentAlertsEnabled,
    pushEnabled: input.pushEnabled,
    backupForMemberIDs: input.backupForMemberIDs,
    quietHoursEnabled: input.quietHoursEnabled,
    quietStartMinute: input.quietStartMinute,
    quietEndMinute: input.quietEndMinute,
    summaryEnabled: input.summaryEnabled,
    summaryMinute: input.summaryMinute,
    timeZoneIdentifierSnapshot: zone,
    revision,
    createdAt,
    updatedAt: now,
  };
}

function conservativePreferenceInput(householdID) {
  return {
    householdID,
    medicationRemindersEnabled: false,
    assignmentAlertsEnabled: false,
    urgentAlertsEnabled: false,
    pushEnabled: false,
    backupForMemberIDs: [],
    quietHoursEnabled: false,
    quietStartMinute: 1320,
    quietEndMinute: 420,
    summaryEnabled: false,
    summaryMinute: 1080,
  };
}

function canonicalPreference(data, uid, householdID) {
  if (!exactKeys(data, preferenceStoredKeys) || data.schemaVersion !== 1 ||
      data.uid !== uid || data.householdID !== householdID ||
      !(data.memberJoinedAtSnapshot instanceof Timestamp) ||
      !["medicationRemindersEnabled", "assignmentAlertsEnabled",
        "urgentAlertsEnabled", "pushEnabled", "quietHoursEnabled",
        "summaryEnabled"].every((key) => typeof data[key] === "boolean") ||
      !Array.isArray(data.backupForMemberIDs) || data.backupForMemberIDs.length > 20 ||
      data.backupForMemberIDs.includes(uid) ||
      [...data.backupForMemberIDs].sort().some((value, index) =>
        value !== data.backupForMemberIDs[index]) ||
      new Set(data.backupForMemberIDs).size !== data.backupForMemberIDs.length ||
      data.backupForMemberIDs.some((value) => !validStoredID(value)) ||
      !validMinute(data.quietStartMinute) || !validMinute(data.quietEndMinute) ||
      (data.quietHoursEnabled && data.quietStartMinute === data.quietEndMinute) ||
      !validMinute(data.summaryMinute) || !validTimeZone(data.timeZoneIdentifierSnapshot) ||
      !Number.isInteger(data.revision) || data.revision < 1 ||
      !(data.createdAt instanceof Timestamp) || !(data.updatedAt instanceof Timestamp) ||
      data.updatedAt.toMillis() < data.createdAt.toMillis()) return null;
  return data;
}

function canonicalCurrentPreference(data, uid, householdID, joinedAt, zone) {
  const preference = canonicalPreference(data, uid, householdID);
  if (preference == null || !(joinedAt instanceof Timestamp) ||
      !preference.memberJoinedAtSnapshot.isEqual(joinedAt) ||
      preference.timeZoneIdentifierSnapshot !== zone) return null;
  return preference;
}

function preferenceAllowsPush(preference, category) {
  if (preference?.pushEnabled !== true) return false;
  return (category === "medication" &&
      preference.medicationRemindersEnabled === true) ||
    ((category === "assignment" || category === "summary") &&
      preference.assignmentAlertsEnabled === true) ||
    (category === "urgent" && preference.urgentAlertsEnabled === true);
}

function canonicalPreferenceReceipt({
  uid, householdID, joinedAt, action, fingerprint: expected, data,
}) {
  const keys = new Set([
    "schemaVersion", "uid", "householdID", "memberJoinedAtSnapshot",
    "action", "fingerprint", "result", "createdAt",
  ]);
  if (!exactKeys(data, keys) || data.schemaVersion !== 1 || data.uid !== uid ||
      data.householdID !== householdID || data.action !== action ||
      data.fingerprint !== expected ||
      !(data.memberJoinedAtSnapshot instanceof Timestamp) ||
      !data.memberJoinedAtSnapshot.isEqual(joinedAt) ||
      !(data.createdAt instanceof Timestamp) ||
      data.result == null || Object.keys(data.result).length !== 3 ||
      data.result.householdID !== householdID ||
      !Number.isInteger(data.result.revision) || data.result.revision < 1 ||
      data.result.existing !== false) {
    throw new HttpsError(
      "invalid-argument",
      "clientMutationID was already used for another request.",
    );
  }
  return data;
}

async function validateBackupMembers({ transaction, household, uid, memberIDs }) {
  if (memberIDs.includes(uid)) {
    throw new HttpsError("invalid-argument", "A member cannot back up themselves.");
  }
  const snapshots = await Promise.all(memberIDs.map((memberID) =>
    transaction.get(household.collection("members").doc(memberID))));
  if (snapshots.some((snapshot) => !snapshot.exists)) {
    throw new HttpsError("failed-precondition", "A backup member is unavailable.");
  }
}

function canonicalGate(data, projectID) {
  const keys = new Set([
    "schemaVersion", "enabled", "projectID", "cutoverAt", "updatedBy", "updatedAt",
  ]);
  if (!exactKeys(data, keys) || data.schemaVersion !== 1 || data.enabled !== true ||
      typeof projectID !== "string" || data.projectID !== projectID ||
      !(data.cutoverAt instanceof Timestamp) || !(data.updatedAt instanceof Timestamp) ||
      !validStoredID(data.updatedBy)) return null;
  return data;
}

function canonicalInbox(data, uid, householdID, id) {
  if (!exactKeys(data, inboxKeys) || data.schemaVersion !== 1 || data.id !== id ||
      data.householdID !== householdID || data.recipientID !== uid ||
      !(data.recipientJoinedAtSnapshot instanceof Timestamp) ||
      !categories.has(data.category) || !levels.has(data.level) ||
      !routeReasons.has(data.routeReason) || !sourceTypes.has(data.sourceType) ||
      !validStoredID(data.sourceID) || data.sourcePath !== sourcePathFor(data) ||
      !Number.isInteger(data.sourceRevision) || data.sourceRevision < 0 ||
      !(data.preferenceRevision == null ||
        (Number.isInteger(data.preferenceRevision) && data.preferenceRevision > 0)) ||
      !["active", "cancelled"].includes(data.status) ||
      !(data.availableAt instanceof Timestamp) || !(data.expiresAt instanceof Timestamp) ||
      data.availableAt.toMillis() >= data.expiresAt.toMillis() ||
      !(data.nextDispatchAt == null || data.nextDispatchAt instanceof Timestamp) ||
      !(data.coalescingKey == null || canonicalInstallationID.test(data.coalescingKey)) ||
      !(data.createdAt instanceof Timestamp) || !(data.updatedAt instanceof Timestamp)) {
    return null;
  }
  if (data.status === "active" && (data.cancelReason != null || data.cancelledAt != null)) {
    return null;
  }
  if (data.status === "cancelled" &&
      (!new Set(["sourceTerminal", "sourceChanged", "membershipEnded",
        "policyChanged", "expired"]).has(data.cancelReason) ||
       !(data.cancelledAt instanceof Timestamp))) return null;
  return data;
}

function sourceReference(db, uid, householdID, inbox) {
  if (inbox.sourceType === "notificationDigest") {
    return db.doc(`users/${uid}/notificationDigests/${inbox.sourceID}`);
  }
  return db.doc(`households/${householdID}/${inbox.sourcePath}`);
}

function sourceMatchesInbox(data, inbox, now, ownerID = null) {
  if (inbox.sourceType !== "notificationDigest") {
    data = canonicalNotificationSource(
      inbox.sourceType, inbox.sourceID, data, ownerID,
    );
    if (data == null) return false;
  }
  if (inbox.sourceType === "task") {
    if (data?.id !== inbox.sourceID || data.revision !== inbox.sourceRevision ||
        data.status !== "unclaimed") return false;
    if (inbox.level === "urgentUnclaimed") {
      return data.kind === "oneOff" && data.priority === "urgent" &&
        data.createdAt instanceof Timestamp;
    }
    return inbox.level === "directAssignment" &&
      data.assignmentMode === "direct" && validStoredID(data.assignmentRequestID) &&
      validStoredID(data.requestedByID) && data.requestedToID === inbox.recipientID &&
      data.assignmentRequestedAt instanceof Timestamp;
  }
  if (inbox.sourceType === "taskResponsibilityTransfer") {
    return data?.id === inbox.sourceID && data.revision === inbox.sourceRevision &&
      data.status === "pending" && data.consentByID === inbox.recipientID &&
      data.createdAt instanceof Timestamp && validStoredID(data.taskID) &&
      validStoredID(data.requestedByID);
  }
  if (inbox.sourceType === "handoffSession") {
    return data?.id === inbox.sourceID && data.revision === inbox.sourceRevision &&
      data.status === "offered" &&
      data.recipientID === inbox.recipientID && data.plannedEndAt instanceof Timestamp &&
      data.offeredAt instanceof Timestamp &&
      data.offeredAt.toMillis() < data.plannedEndAt.toMillis() &&
      data.plannedEndAt.toMillis() > now.toMillis();
  }
  if (inbox.sourceType === "medicationOccurrence") {
    if (data?.id !== inbox.sourceID || data.revision !== inbox.sourceRevision ||
        data.outcomeStatus !== "unresolved" || !(data.dueAt instanceof Timestamp) ||
        !["claimed", "unclaimed"].includes(data.responsibilityStatus)) return false;
    if (inbox.routeReason === "responsible") {
      return data.responsibilityStatus === "claimed" &&
        data.responsibleByID === inbox.recipientID;
    }
    if (inbox.routeReason === "backup") {
      return data.responsibilityStatus === "claimed" &&
        validStoredID(data.responsibleByID) &&
        data.responsibleByID !== inbox.recipientID;
    }
    return inbox.routeReason === "medicationOptIn" &&
      data.responsibilityStatus === "unclaimed" && data.responsibleByID == null;
  }
  return canonicalDigest(data, inbox.recipientID, inbox.sourceID)?.status === "ready" &&
    inbox.sourceRevision === 1;
}

function sourcePathFor(data) {
  const collections = {
    medicationOccurrence: "medicationOccurrences",
    task: "tasks",
    taskResponsibilityTransfer: "taskResponsibilityTransfers",
    handoffSession: "handoffSessions",
    notificationDigest: "notificationDigests",
  };
  return `${collections[data.sourceType]}/${data.sourceID}`;
}

async function cancelExpiredInboxItem(db, reference, inbox, now) {
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const current = snapshot.data();
    if (!snapshot.exists || current?.status !== "active" ||
        !(current.expiresAt instanceof Timestamp) ||
        current.expiresAt.toMillis() > now.toMillis()) return;
    transaction.update(reference, {
      status: "cancelled", cancelReason: "expired", cancelledAt: now,
      nextDispatchAt: null, updatedAt: now,
    });
  });
}

function rejectRoute(householdID, inboxItemID, reason, serverCheckedAt) {
  return { disposition: "reject", householdID, inboxItemID, reason, serverCheckedAt };
}

function manifestPayload({
  inbox, intentID, bindingKeyVersion, selected, now, status, safeErrorCode,
}) {
  return {
    schemaVersion: 1,
    intentID,
    householdID: inbox.householdID,
    recipientID: inbox.recipientID,
    recipientJoinedAtSnapshot: inbox.recipientJoinedAtSnapshot,
    selectedInstallationHashes: selected,
    selectedCount: selected.length,
    bindingKeyVersion,
    status,
    safeErrorCode,
    cursorInstallationHash: null,
    createdAt: now,
    updatedAt: now,
    nextRecoveryAt: status === "materializing"
      ? Timestamp.fromMillis(now.toMillis() + 300_000)
      : null,
    completedAt: null,
    blockedAt: status === "blocked" ? now : null,
  };
}

function canonicalManifest(data, uid, intentID, inbox) {
  const keys = new Set([
    "schemaVersion", "intentID", "householdID", "recipientID",
    "recipientJoinedAtSnapshot", "selectedInstallationHashes", "selectedCount",
    "bindingKeyVersion", "status", "safeErrorCode", "cursorInstallationHash",
    "createdAt", "updatedAt", "nextRecoveryAt", "completedAt", "blockedAt",
  ]);
  if (!exactKeys(data, keys) || data.schemaVersion !== 1 ||
      data.intentID !== intentID || data.householdID !== inbox.householdID ||
      data.recipientID !== uid || !(data.recipientJoinedAtSnapshot instanceof Timestamp) ||
      !data.recipientJoinedAtSnapshot.isEqual(inbox.recipientJoinedAtSnapshot) ||
      !Array.isArray(data.selectedInstallationHashes) ||
      data.selectedInstallationHashes.length > maxInstallations ||
      data.selectedInstallationHashes.some((value) =>
        !canonicalInstallationID.test(value)) ||
      [...data.selectedInstallationHashes].sort().some((value, index) =>
        value !== data.selectedInstallationHashes[index]) ||
      new Set(data.selectedInstallationHashes).size !==
        data.selectedInstallationHashes.length ||
      data.selectedCount !== data.selectedInstallationHashes.length ||
      !Number.isInteger(data.bindingKeyVersion) || data.bindingKeyVersion < 1 ||
      !["materializing", "complete", "blocked"].includes(data.status) ||
      !(data.createdAt instanceof Timestamp) || !(data.updatedAt instanceof Timestamp) ||
      data.updatedAt.toMillis() < data.createdAt.toMillis()) return null;
  if (data.status === "materializing") {
    return data.safeErrorCode == null &&
      (data.cursorInstallationHash == null ||
        data.selectedInstallationHashes.includes(data.cursorInstallationHash)) &&
      data.nextRecoveryAt instanceof Timestamp && data.completedAt == null &&
      data.blockedAt == null ? data : null;
  }
  if (data.status === "complete") {
    return data.safeErrorCode == null && data.cursorInstallationHash == null &&
      data.nextRecoveryAt == null && data.completedAt instanceof Timestamp &&
      data.blockedAt == null ? data : null;
  }
  return ["tooManyInstallations", "conflictingDelivery"].includes(
    data.safeErrorCode,
  ) && data.cursorInstallationHash == null && data.nextRecoveryAt == null &&
    data.completedAt == null && data.blockedAt instanceof Timestamp ? data : null;
}

function deliveryPayload({ id, intentID, inbox, installationHash, now }) {
  return {
    schemaVersion: 2,
    id,
    intentID,
    householdID: inbox.householdID,
    recipientID: inbox.recipientID,
    recipientJoinedAtSnapshot: inbox.recipientJoinedAtSnapshot,
    installationHash,
    status: "queued",
    attemptCount: 0,
    nextAttemptAt: inbox.nextDispatchAt,
    leaseID: null,
    leaseExpiresAt: null,
    providerRequestStartedAt: null,
    providerAcceptedAt: null,
    providerUnknownAt: null,
    terminalAt: null,
    safeErrorCode: null,
    createdAt: now,
    updatedAt: now,
  };
}

function canonicalDelivery(data, uid, id) {
  const keys = new Set([
    "schemaVersion", "id", "intentID", "householdID", "recipientID",
    "recipientJoinedAtSnapshot", "installationHash", "status", "attemptCount",
    "nextAttemptAt", "leaseID", "leaseExpiresAt", "providerRequestStartedAt",
    "providerAcceptedAt", "providerUnknownAt", "terminalAt", "safeErrorCode",
    "createdAt", "updatedAt",
  ]);
  if (!exactKeys(data, keys) || data.schemaVersion !== 2 || data.id !== id ||
      data.recipientID !== uid || !validStoredID(data.householdID) ||
      !canonicalInstallationID.test(data.intentID) ||
      !canonicalInstallationID.test(data.installationHash) ||
      !(data.recipientJoinedAtSnapshot instanceof Timestamp) ||
      !Number.isInteger(data.attemptCount) || data.attemptCount < 0 ||
      data.attemptCount > 3 ||
      !(data.createdAt instanceof Timestamp) || !(data.updatedAt instanceof Timestamp) ||
      data.updatedAt.toMillis() < data.createdAt.toMillis() ||
      !["queued", "attempting", "providerAccepted", "providerUnknown",
        "retryableFailure", "permanentFailure", "cancelled", "expired"].includes(
        data.status,
      )) return null;
  const nullScheduling = data.nextAttemptAt == null && data.leaseID == null &&
    data.leaseExpiresAt == null && data.providerRequestStartedAt == null;
  const nullResults = data.providerAcceptedAt == null &&
    data.providerUnknownAt == null && data.terminalAt == null;
  if (data.status === "queued") {
    return data.attemptCount <= 2 && data.nextAttemptAt instanceof Timestamp &&
      data.leaseID == null && data.leaseExpiresAt == null &&
      data.providerRequestStartedAt == null && nullResults &&
      data.safeErrorCode == null ? data : null;
  }
  if (data.status === "attempting") {
    return data.attemptCount >= 1 && data.nextAttemptAt == null &&
      validStoredID(data.leaseID) && data.leaseExpiresAt instanceof Timestamp &&
      (data.providerRequestStartedAt == null ||
        data.providerRequestStartedAt instanceof Timestamp) &&
      nullResults && data.safeErrorCode == null ? data : null;
  }
  if (data.status === "retryableFailure") {
    return data.attemptCount >= 1 && data.attemptCount <= 2 &&
      data.nextAttemptAt instanceof Timestamp && data.leaseID == null &&
      data.leaseExpiresAt == null && data.providerRequestStartedAt == null &&
      nullResults && ["providerRejected", "leaseExpired"].includes(data.safeErrorCode)
      ? data : null;
  }
  if (data.status === "providerAccepted") {
    return data.attemptCount >= 1 && nullScheduling &&
      data.providerAcceptedAt instanceof Timestamp &&
      data.terminalAt instanceof Timestamp &&
      data.providerAcceptedAt.isEqual(data.terminalAt) &&
      data.providerUnknownAt == null && data.safeErrorCode == null ? data : null;
  }
  if (data.status === "providerUnknown") {
    return data.attemptCount >= 1 && nullScheduling &&
      data.providerUnknownAt instanceof Timestamp && data.terminalAt instanceof Timestamp &&
      data.providerUnknownAt.isEqual(data.terminalAt) &&
      data.providerAcceptedAt == null && data.safeErrorCode === "providerAmbiguous"
      ? data : null;
  }
  if (data.status === "permanentFailure") {
    return data.attemptCount >= 1 && nullScheduling && nullResults === false &&
      data.providerAcceptedAt == null && data.providerUnknownAt == null &&
      data.terminalAt instanceof Timestamp &&
      ["tokenInvalid", "providerRejected"].includes(data.safeErrorCode) ? data : null;
  }
  if (data.status === "cancelled") {
    return nullScheduling && data.providerAcceptedAt == null &&
      data.providerUnknownAt == null && data.terminalAt instanceof Timestamp &&
      ["sourceTerminal", "policyChanged", "membershipEnded",
        "installationDisabled", "installationDuplicate"].includes(data.safeErrorCode)
      ? data : null;
  }
  return nullScheduling && data.providerAcceptedAt == null &&
    data.providerUnknownAt == null && data.terminalAt instanceof Timestamp &&
    data.safeErrorCode == null ? data : null;
}

function semanticInstant(inbox) {
  return inbox.sourceType === "notificationDigest"
    ? inbox.availableAt
    : inbox.createdAt;
}

async function startProviderAttempt({
  db,
  uid,
  delivery,
  claim,
  current,
  attempt,
  projectID,
  secret,
  now,
}) {
  const generationGate = db.doc("systemConfig/notificationIntentGenerationV2");
  const dispatchGate = db.doc("systemConfig/notificationDispatchV2");
  const intent = db.doc(`users/${uid}/notificationInbox/${current.intentID}`);
  const manifest = db.doc(
    `users/${uid}/notificationDeliveryManifests/${current.intentID}`,
  );
  const installation = db.doc(
    `users/${uid}/notificationTokens/${current.installationHash}`,
  );
  const member = db.doc(`households/${current.householdID}/members/${uid}`);
  const household = db.doc(`households/${current.householdID}`);
  const revocation = db.doc(
    `households/${current.householdID}/membershipRevocations/${uid}`,
  );
  const preference = db.doc(
    `users/${uid}/householdNotificationPreferences/${current.householdID}`,
  );
  const source = sourceReference(db, uid, current.householdID, attempt.inbox);
  const bindingID = createHmac("sha256", secret)
    .update(stableJSON([
      current.intentID,
      uid,
      attempt.token,
    ]))
    .digest("hex");
  const binding = db.doc(
    `households/${current.householdID}/notificationEndpointBindings/${bindingID}`,
  );
  const startGates = await readNotificationGatesAt(db, projectID);
  const startSummaryAuthority = startGates.enabled
    ? await validateSummaryAuthorityAt({
      db, uid, inbox: attempt.inbox, now,
      cutoff: Math.max(
        startGates.generation.cutoverAt.toMillis(),
        startGates.dispatch.cutoverAt.toMillis(),
      ),
    })
    : { status: "notSummary" };
  return db.runTransaction(async (transaction) => {
    const [deliverySnapshot, claimSnapshot, generationSnapshot, dispatchSnapshot,
      intentSnapshot, manifestSnapshot, installationSnapshot, memberSnapshot,
      householdSnapshot, revocationSnapshot, preferenceSnapshot, sourceSnapshot,
      bindingSnapshot, originalIntentSnapshot, originalSourceSnapshot] =
      await Promise.all([
        transaction.get(delivery), transaction.get(claim),
        transaction.get(generationGate), transaction.get(dispatchGate),
        transaction.get(intent), transaction.get(manifest),
        transaction.get(installation), transaction.get(member),
        transaction.get(household), transaction.get(revocation),
        transaction.get(preference),
        transaction.get(source), transaction.get(binding),
        startSummaryAuthority.status === "valid"
          ? transaction.get(startSummaryAuthority.intent)
          : null,
        startSummaryAuthority.status === "valid"
          ? transaction.get(startSummaryAuthority.source)
          : null,
      ]);
    const value = canonicalDelivery(deliverySnapshot.data(), uid, delivery.id);
    const inbox = canonicalInbox(
      intentSnapshot.data(), uid, current.householdID, current.intentID,
    );
    const generation = canonicalGate(generationSnapshot.data(), projectID);
    const dispatch = canonicalGate(dispatchSnapshot.data(), projectID);
    const tokenData = installationSnapshot.data();
    const joinedAt = memberSnapshot.data()?.joinedAt;
    const zone = householdSnapshot.data()?.timeZoneIdentifier;
    const prefs = canonicalCurrentPreference(
      preferenceSnapshot.data(), uid, current.householdID, joinedAt, zone,
    );
    const manifestData = inbox == null ? null : canonicalManifest(
      manifestSnapshot.data(), uid, current.intentID, inbox,
    );
    const gatesAvailable = generation != null && dispatch != null;
    const claimData = claimSnapshot.data();
    if (value?.status !== "attempting" || value.leaseID !== attempt.leaseID ||
        !claimSnapshot.exists || claimData?.leaseID !== attempt.leaseID ||
        !(claimData.leaseUntil instanceof Timestamp) ||
        !(value.leaseExpiresAt instanceof Timestamp) ||
        !claimData.leaseUntil.isEqual(value.leaseExpiresAt)) {
      return { status: "skipped", reason: "leaseChanged" };
    }
    if (!gatesAvailable) {
      transaction.update(delivery, {
        status: "queued", attemptCount: current.attemptCount,
        nextAttemptAt: Timestamp.fromMillis(now.toMillis() + 300_000),
        leaseID: null, leaseExpiresAt: null, providerRequestStartedAt: null,
        providerAcceptedAt: null, providerUnknownAt: null, terminalAt: null,
        safeErrorCode: null, updatedAt: now,
      });
      transaction.delete(claim);
      return { status: "deferred", reason: "gatesDisabled" };
    }
    const cutoff = Math.max(
      generation.cutoverAt.toMillis(), dispatch.cutoverAt.toMillis(),
    );
    const semanticAt = inbox == null || !sourceSnapshot.exists
      ? null
      : semanticInstantForSource(inbox, sourceSnapshot.data());
    const summaryAuthorityValid = inbox?.sourceType !== "notificationDigest" ||
      (startSummaryAuthority.status === "valid" &&
        originalIntentSnapshot?.exists && originalSourceSnapshot?.exists &&
        canonicalInbox(
          originalIntentSnapshot.data(), uid, current.householdID,
          originalIntentSnapshot.id,
        )?.status === "active" && sourceMatchesInbox(
          originalSourceSnapshot.data(), startSummaryAuthority.inbox, now,
          householdSnapshot.data()?.ownerID,
        ) && semanticInstantForSource(
          startSummaryAuthority.inbox, originalSourceSnapshot.data(),
        ).toMillis() >= cutoff);
    const membershipInvalid = !memberSnapshot.exists ||
      !(joinedAt instanceof Timestamp) ||
      !joinedAt.isEqual(current.recipientJoinedAtSnapshot) ||
      revocationSnapshot.exists;
    const preferenceInvalid = prefs == null ||
      prefs.revision !== inbox?.preferenceRevision ||
      !preferenceAllowsPush(prefs, inbox?.category);
    const installationInvalid = tokenData?.enabled !== true ||
      tokenData?.householdID !== current.householdID ||
      tokenData?.token !== attempt.token;
    const authorityValid = inbox != null && inbox.status === "active" &&
      inbox.expiresAt.toMillis() > now.toMillis() &&
      sourceSnapshot.exists && sourceMatchesInbox(
        sourceSnapshot.data(), inbox, now, householdSnapshot.data()?.ownerID,
      ) && summaryAuthorityValid &&
      semanticAt instanceof Timestamp && semanticAt.toMillis() >= cutoff &&
      manifestData?.status === "complete" &&
      manifestData.bindingKeyVersion === attempt.bindingKeyVersion &&
      Array.isArray(manifestData.selectedInstallationHashes) &&
      manifestData.selectedInstallationHashes.includes(current.installationHash) &&
      tokenData?.enabled === true && tokenData.householdID === current.householdID &&
      tokenData.token === attempt.token && memberSnapshot.exists &&
      joinedAt instanceof Timestamp && joinedAt.isEqual(current.recipientJoinedAtSnapshot) &&
      !revocationSnapshot.exists && prefs != null &&
      prefs.revision === inbox.preferenceRevision &&
      preferenceAllowsPush(prefs, inbox.category);
    if (!authorityValid) {
      transaction.update(delivery, terminalDelivery({
        current: value,
        now,
        status: "cancelled",
        safeErrorCode: membershipInvalid
          ? "membershipEnded"
          : preferenceInvalid
            ? "policyChanged"
            : installationInvalid
              ? "installationDisabled"
              : "policyChanged",
      }));
      const existingBinding = bindingSnapshot.exists
        ? canonicalBinding(
          bindingSnapshot.data(), current, attempt.bindingKeyVersion,
        )
        : null;
      if (existingBinding?.winningDeliveryID === delivery.id &&
          ["reserved", "retryableFailure"].includes(existingBinding.status)) {
        transaction.update(binding, {
          status: "cancelled", leaseExpiresAt: null, updatedAt: now,
        });
      }
      if (inbox?.sourceType === "notificationDigest" && sourceSnapshot.exists &&
          (!summaryAuthorityValid || membershipInvalid || preferenceInvalid)) {
        const digest = canonicalDigest(sourceSnapshot.data(), uid, inbox.sourceID);
        if (digest?.status === "ready") {
          if (!summaryAuthorityValid && startSummaryAuthority.status === "blocked") {
            transaction.update(source, {
              status: "blocked", safeErrorCode: "tooManyCandidates",
              cancelReason: null, nextFinalizeAt: null, readyAt: null,
              cancelledAt: null, blockedAt: now, updatedAt: now,
            });
            transaction.update(intent, {
              status: "cancelled", cancelReason: "sourceChanged",
              cancelledAt: now, nextDispatchAt: null, updatedAt: now,
            });
          } else {
            const cancelReason = membershipInvalid
              ? "membershipEnded"
              : preferenceInvalid
                ? "policyChanged"
                : "noValidSource";
            transaction.update(source, {
              status: "cancelled", cancelReason,
              safeErrorCode: null, nextFinalizeAt: null, readyAt: null,
              cancelledAt: now, blockedAt: null, updatedAt: now,
            });
            transaction.update(intent, {
              status: "cancelled",
              cancelReason: membershipInvalid || preferenceInvalid
                ? cancelReason
                : "sourceChanged",
              cancelledAt: now, nextDispatchAt: null, updatedAt: now,
            });
          }
        }
      }
      transaction.delete(claim);
      return { status: "cancelled", reason: "authorityChanged" };
    }
    if (bindingSnapshot.exists) {
      const existingBinding = canonicalBinding(
        bindingSnapshot.data(), current, attempt.bindingKeyVersion,
      );
      if (existingBinding == null) {
        transaction.update(delivery, terminalDelivery({
          current: value,
          now,
          status: "cancelled",
          safeErrorCode: "installationDuplicate",
        }));
        transaction.delete(claim);
        return { status: "cancelled", reason: "bindingMalformed" };
      }
      if (existingBinding.winningDeliveryID !== delivery.id) {
        transaction.update(delivery, terminalDelivery({
          current: value,
          now,
          status: "cancelled",
          safeErrorCode: "installationDuplicate",
        }));
        transaction.delete(claim);
        return { status: "cancelled", reason: "installationDuplicate" };
      }
      if (!["reserved", "retryableFailure"].includes(existingBinding.status)) {
        transaction.update(delivery, terminalDelivery({
          current: value,
          now,
          status: "cancelled",
          safeErrorCode: "installationDuplicate",
        }));
        transaction.delete(claim);
        return { status: "cancelled", reason: "bindingTerminal" };
      }
      transaction.update(binding, {
        status: "reserved", leaseExpiresAt: value.leaseExpiresAt, updatedAt: now,
      });
    } else {
      transaction.create(binding, {
        schemaVersion: 1,
        intentID: current.intentID,
        recipientID: uid,
        recipientJoinedAtSnapshot: current.recipientJoinedAtSnapshot,
        winningDeliveryID: delivery.id,
        bindingKeyVersion: attempt.bindingKeyVersion,
        status: "reserved",
        leaseExpiresAt: value.leaseExpiresAt,
        expiresAt: Timestamp.fromMillis(inbox.expiresAt.toMillis() + 86_400_000),
        createdAt: now,
        updatedAt: now,
      });
    }
    transaction.update(delivery, {
      providerRequestStartedAt: now,
      updatedAt: now,
    });
    return { status: "started", startedAt: now, binding };
  });
}

function semanticInstantForSource(inbox, source) {
  if (inbox.sourceType === "medicationOccurrence" && source.dueAt instanceof Timestamp) {
    const offsets = { due: 0, overdue15: 15, overdue30: 30 };
    return Timestamp.fromMillis(
      source.dueAt.toMillis() + (offsets[inbox.level] ?? 0) * 60_000,
    );
  }
  if (inbox.sourceType === "taskResponsibilityTransfer" &&
      source.createdAt instanceof Timestamp) return source.createdAt;
  if (inbox.sourceType === "handoffSession" && source.offeredAt instanceof Timestamp) {
    return source.offeredAt;
  }
  if (inbox.sourceType === "task" && inbox.level === "directAssignment" &&
      source.assignmentRequestedAt instanceof Timestamp) return source.assignmentRequestedAt;
  if (inbox.sourceType === "task" && source.createdAt instanceof Timestamp) {
    return source.createdAt;
  }
  if (inbox.sourceType === "notificationDigest" &&
      source.windowEndAt instanceof Timestamp) return source.windowEndAt;
  return null;
}

function canonicalBinding(data, delivery, bindingKeyVersion) {
  const keys = new Set([
    "schemaVersion", "intentID", "recipientID", "recipientJoinedAtSnapshot",
    "winningDeliveryID", "bindingKeyVersion", "status", "leaseExpiresAt",
    "expiresAt", "createdAt", "updatedAt",
  ]);
  if (!exactKeys(data, keys) || data.schemaVersion !== 1 ||
      data.intentID !== delivery.intentID || data.recipientID !== delivery.recipientID ||
      !(data.recipientJoinedAtSnapshot instanceof Timestamp) ||
      !data.recipientJoinedAtSnapshot.isEqual(delivery.recipientJoinedAtSnapshot) ||
      !canonicalInstallationID.test(data.winningDeliveryID) ||
      data.bindingKeyVersion !== bindingKeyVersion ||
      !["reserved", "providerAccepted", "providerUnknown", "retryableFailure",
        "permanentFailure", "cancelled"].includes(data.status) ||
      !(data.expiresAt instanceof Timestamp) || !(data.createdAt instanceof Timestamp) ||
      !(data.updatedAt instanceof Timestamp) ||
      !(data.leaseExpiresAt == null || data.leaseExpiresAt instanceof Timestamp)) return null;
  return data;
}

function providerMessage({ inbox, token, secret, startedAt }) {
  const ttl = Math.max(1, Math.min(86_400,
    Math.ceil((inbox.expiresAt.toMillis() - startedAt.toMillis()) / 1000)));
  return {
    token,
    notification: {
      title: "CoPaw",
      body: "ケアの更新があります / Care update available",
    },
    data: {
      schemaVersion: "1",
      destination: "notificationInbox",
      householdID: inbox.householdID,
      inboxItemID: inbox.id,
    },
    collapseKey: `copaw-${createHmac("sha256", secret)
      .update(`collapse|${inbox.id}`).digest("hex").slice(0, 32)}`,
    ttl,
  };
}

function normalizeProviderOutcome(outcome) {
  if (outcome != null && ["accepted", "definiteRetryableRejection",
    "ambiguous"].includes(outcome.kind)) return { kind: outcome.kind };
  if (outcome?.kind === "definitePermanentRejection") {
    return {
      kind: outcome.kind,
      reason: outcome.reason === "tokenInvalid" ? "tokenInvalid" : "providerRejected",
    };
  }
  return { kind: "ambiguous" };
}

async function disableInvalidTokenInstallationsAt({
  db, uid, householdID, token, now,
}) {
  while (true) {
    const matching = await db.collection(`users/${uid}/notificationTokens`)
      .where("householdID", "==", householdID)
      .where("token", "==", token)
      .where("enabled", "==", true)
      .limit(400)
      .get();
    if (matching.empty) return;
    const batch = db.batch();
    for (const document of matching.docs) {
      batch.update(document.ref, { enabled: false, updatedAt: now });
    }
    await batch.commit();
  }
}

async function completeProviderAttempt({
  db, delivery, claim, binding, current, attemptCount, expectedLeaseID,
  outcome, now,
}) {
  await db.runTransaction(async (transaction) => {
    const [deliverySnapshot, claimSnapshot, bindingSnapshot] = await Promise.all([
      transaction.get(delivery), transaction.get(claim), transaction.get(binding),
    ]);
    const value = deliverySnapshot.data();
    if (value?.status !== "attempting" || value.leaseID !== expectedLeaseID ||
        claimSnapshot.data()?.leaseID !== expectedLeaseID) return;
    if (outcome.kind === "accepted") {
      transaction.update(delivery, terminalDelivery({
        current: { ...current, attemptCount }, now,
        status: "providerAccepted", safeErrorCode: null,
      }));
      if (bindingSnapshot.exists) transaction.update(binding, {
        status: "providerAccepted", leaseExpiresAt: null, updatedAt: now,
      });
    } else if (outcome.kind === "ambiguous") {
      transaction.update(delivery, terminalDelivery({
        current: { ...current, attemptCount }, now,
        status: "providerUnknown", safeErrorCode: "providerAmbiguous",
      }));
      if (bindingSnapshot.exists) transaction.update(binding, {
        status: "providerUnknown", leaseExpiresAt: null, updatedAt: now,
      });
    } else if (outcome.kind === "definiteRetryableRejection" && attemptCount < 3) {
      transaction.update(delivery, {
        status: "retryableFailure", attemptCount,
        nextAttemptAt: Timestamp.fromMillis(now.toMillis() + 300_000),
        leaseID: null, leaseExpiresAt: null, providerRequestStartedAt: null,
        providerAcceptedAt: null, providerUnknownAt: null, terminalAt: null,
        safeErrorCode: "providerRejected", updatedAt: now,
      });
      if (bindingSnapshot.exists) transaction.update(binding, {
        status: "retryableFailure", leaseExpiresAt: null, updatedAt: now,
      });
    } else {
      const safeErrorCode = outcome.kind === "definitePermanentRejection" &&
          outcome.reason === "tokenInvalid"
        ? "tokenInvalid"
        : "providerRejected";
      transaction.update(delivery, terminalDelivery({
        current: { ...current, attemptCount }, now,
        status: "permanentFailure", safeErrorCode,
      }));
      if (bindingSnapshot.exists) transaction.update(binding, {
        status: "permanentFailure", leaseExpiresAt: null, updatedAt: now,
      });
    }
    if (claimSnapshot.exists) transaction.delete(claim);
  });
}

async function releaseAttempt({
  db, delivery, claim, current, expectedLeaseID, now,
}) {
  await db.runTransaction(async (transaction) => {
    const [snapshot, claimSnapshot] = await Promise.all([
      transaction.get(delivery), transaction.get(claim),
    ]);
    if (snapshot.data()?.status === "attempting" &&
        snapshot.data()?.leaseID === expectedLeaseID &&
        claimSnapshot.data()?.leaseID === expectedLeaseID) {
      transaction.update(delivery, {
        status: "queued", attemptCount: current.attemptCount,
        nextAttemptAt: Timestamp.fromMillis(now.toMillis() + 300_000),
        leaseID: null, leaseExpiresAt: null, providerRequestStartedAt: null,
        providerAcceptedAt: null, providerUnknownAt: null, terminalAt: null,
        safeErrorCode: null, updatedAt: now,
      });
      transaction.delete(claim);
    }
  });
}

async function cancelAttempt({
  db, delivery, claim, current, expectedLeaseID, now, safeErrorCode,
}) {
  await db.runTransaction(async (transaction) => {
    const [snapshot, claimSnapshot] = await Promise.all([
      transaction.get(delivery), transaction.get(claim),
    ]);
    if (snapshot.data()?.status === "attempting" &&
        snapshot.data()?.leaseID === expectedLeaseID &&
        claimSnapshot.data()?.leaseID === expectedLeaseID) {
      transaction.update(delivery, terminalDelivery({
        current, now, status: "cancelled", safeErrorCode,
      }));
      transaction.delete(claim);
    }
  });
}

function terminalDelivery({ current, now, status, safeErrorCode }) {
  return {
    status,
    attemptCount: current.attemptCount,
    nextAttemptAt: null,
    leaseID: null,
    leaseExpiresAt: null,
    providerRequestStartedAt: null,
    providerAcceptedAt: status === "providerAccepted" ? now : null,
    providerUnknownAt: status === "providerUnknown" ? now : null,
    terminalAt: now,
    safeErrorCode,
    updatedAt: now,
  };
}

function serializableDelivery(data) {
  return Object.fromEntries(Object.entries(data).map(([key, value]) => [
    key,
    value instanceof Timestamp ? value.toMillis() : value,
  ]));
}

function trustedTimestamp(value) {
  if (!(value instanceof Date) || Number.isNaN(value.getTime())) {
    throw new HttpsError("internal", "The server clock is unavailable.");
  }
  return Timestamp.fromDate(value);
}

function rfc3339(value) {
  return new Date(value.toMillis()).toISOString();
}

function exactKeys(value, keys) {
  return value != null && typeof value === "object" && !Array.isArray(value) &&
    Object.keys(value).length === keys.size &&
    Object.keys(value).every((key) => keys.has(key));
}

function validStoredID(value) {
  return typeof value === "string" && value.length > 0 &&
    value.length <= 128 && !value.includes("/");
}

function hexID(value, field) {
  if (typeof value !== "string" || !canonicalInstallationID.test(value)) {
    throw new HttpsError("invalid-argument", `${field} is invalid.`);
  }
  return value;
}

function boolean(value, field) {
  if (typeof value !== "boolean") {
    throw new HttpsError("invalid-argument", `${field} is invalid.`);
  }
  return value;
}

function integerRange(value, min, max, field) {
  if (!Number.isInteger(value) || value < min || value > max) {
    throw new HttpsError("invalid-argument", `${field} is invalid.`);
  }
  return value;
}

function validMinute(value) {
  return Number.isInteger(value) && value >= 0 && value <= 1439;
}

function validTimeZone(value) {
  if (typeof value !== "string" || value.length === 0 || value.length > 128) return false;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: value }).format();
    return true;
  } catch {
    return false;
  }
}

function validToken(value) {
  return typeof value === "string" && value.length > 0 && value.length <= 4096;
}

function safeRevision(value) {
  return Number.isInteger(value) && value >= 0 ? value : null;
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function stableJSON(value) {
  if (Array.isArray(value)) return `[${value.map(stableJSON).join(",")}]`;
  if (value != null && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) =>
      `${JSON.stringify(key)}:${stableJSON(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}
