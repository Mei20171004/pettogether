import assert from "node:assert/strict";
import { after, test } from "node:test";

import { deleteApp, initializeApp } from "firebase-admin/app";
import { Timestamp, getFirestore } from "firebase-admin/firestore";

import {
  deliveryIDFor,
  dispatchNotificationDeliveryAt,
  expireNotificationInboxAt,
  finalizeNotificationDigestAt,
  generateMedicationNotificationIntentsAt,
  generateNotificationSourceAt,
  intentIDFor,
  materializeNotificationDeliveriesAt,
  readNotificationGatesAt,
  recoverAttemptingDeliveriesAt,
  recoverNotificationDigestsAt,
  recoverNotificationManifestsAt,
  resetMalformedNotificationPreferencesAt,
  resolveNotificationInboxRouteAt,
  setHouseholdNotificationPreferencesAt,
} from "../notifications_v2.js";
import * as legacyNotifications from "../notifications.js";

const projectId = process.env.COPAW_TEST_PROJECT_ID ?? "demo-copaw";
const app = initializeApp({ projectId }, "notification-v2-tests-admin");
const db = getFirestore(app);
let sequence = 0;

after(() => deleteApp(app));

test("both exact gates fail closed when missing, malformed, disabled, or mismatched", async () => {
  const missing = await readNotificationGatesAt(db, projectId);
  assert.deepEqual(missing, { generation: null, dispatch: null, enabled: false });

  await db.doc("systemConfig/notificationIntentGenerationV2").set(gate({
    projectID: projectId,
  }));
  await db.doc("systemConfig/notificationDispatchV2").set(gate({
    projectID: "another-project",
  }));
  const mismatch = await readNotificationGatesAt(db, projectId);
  assert.equal(mismatch.enabled, false);

  await db.doc("systemConfig/notificationDispatchV2").set(gate({
    projectID: projectId,
  }));
  const enabled = await readNotificationGatesAt(db, projectId);
  assert.equal(enabled.enabled, true);
  assert.equal(enabled.generation.cutoverAt.toMillis(), 1_000);
  assert.equal(enabled.dispatch.cutoverAt.toMillis(), 1_000);
});

test("preference callable writes exact canonical shape and receipt replay is idempotent", async () => {
  const householdID = unique("preference-home");
  await seedHousehold(householdID);
  const input = preferenceInput(householdID);
  const first = await setHouseholdNotificationPreferencesAt(
    db,
    request("member-a", input),
    new Date(10_000),
  );
  const replay = await setHouseholdNotificationPreferencesAt(
    db,
    request("member-a", input),
    new Date(20_000),
  );
  assert.deepEqual(first, { householdID, revision: 1, existing: false });
  assert.deepEqual(replay, { householdID, revision: 1, existing: true });
  const stored = (await db.doc(
    `users/member-a/householdNotificationPreferences/${householdID}`,
  ).get()).data();
  assert.deepEqual(Object.keys(stored).sort(), [
    "assignmentAlertsEnabled", "backupForMemberIDs", "createdAt", "householdID",
    "medicationRemindersEnabled", "memberJoinedAtSnapshot", "pushEnabled",
    "quietEndMinute", "quietHoursEnabled", "quietStartMinute", "revision",
    "schemaVersion", "summaryEnabled", "summaryMinute",
    "timeZoneIdentifierSnapshot", "uid", "updatedAt", "urgentAlertsEnabled",
  ].sort());
  assert.equal(stored.uid, "member-a");
  assert.equal(stored.timeZoneIdentifierSnapshot, "Asia/Tokyo");
  assert.equal(stored.createdAt.toMillis(), 10_000);
  assert.equal(stored.updatedAt.toMillis(), 10_000);
});

test("preference callable rejects extra input, stale revision, non-member backup, and mutation reuse", async () => {
  const householdID = unique("preference-invalid");
  await seedHousehold(householdID);
  await assert.rejects(
    setHouseholdNotificationPreferencesAt(db, request("member-a", {
      ...preferenceInput(householdID), extra: true,
    })), hasCode("invalid-argument"),
  );
  await assert.rejects(
    setHouseholdNotificationPreferencesAt(db, request("member-a", {
      ...preferenceInput(householdID), backupForMemberIDs: ["missing"],
    })), hasCode("failed-precondition"),
  );
  const initial = preferenceInput(householdID);
  await setHouseholdNotificationPreferencesAt(db, request("member-a", initial));
  await assert.rejects(
    setHouseholdNotificationPreferencesAt(db, request("member-a", {
      ...initial, pushEnabled: false,
    })), hasCode("invalid-argument"),
  );
  await assert.rejects(
    setHouseholdNotificationPreferencesAt(db, request("member-a", {
      ...preferenceInput(householdID),
      clientMutationID: unique("stale"), expectedRevision: 0,
    })), hasCode("aborted"),
  );
});

test("route resolver returns open, rejects changed source, and server-cancels expiry", async () => {
  const householdID = unique("route-home");
  await seedHousehold(householdID);
  const intentID = "a".repeat(64);
  await db.doc(`households/${householdID}/tasks/task-a`).set(urgentTask("task-a", 2));
  await db.doc(`users/member-a/notificationInbox/${intentID}`).set(inbox({
    householdID, intentID, sourceRevision: 2,
    expiresAt: Timestamp.fromMillis(100_000),
  }));
  const opened = await resolveNotificationInboxRouteAt(
    db, request("member-a", { householdID, inboxItemID: intentID }),
    new Date(50_000),
  );
  assert.deepEqual(opened, {
    disposition: "open", householdID, inboxItemID: intentID,
    category: "urgent", level: "urgentUnclaimed",
    serverCheckedAt: "1970-01-01T00:00:50.000Z",
  });
  await db.doc(`households/${householdID}/tasks/task-a`).update({ revision: 3 });
  assert.equal((await resolveNotificationInboxRouteAt(
    db, request("member-a", { householdID, inboxItemID: intentID }),
    new Date(60_000),
  )).reason, "sourceChanged");
  await db.doc(`users/member-a/notificationInbox/${intentID}`).update({
    expiresAt: Timestamp.fromMillis(59_000),
  });
  const expired = await resolveNotificationInboxRouteAt(
    db, request("member-a", { householdID, inboxItemID: intentID }),
    new Date(60_000),
  );
  assert.equal(expired.reason, "expired");
  const stored = (await db.doc(`users/member-a/notificationInbox/${intentID}`).get()).data();
  assert.equal(stored.status, "cancelled");
  assert.equal(stored.cancelReason, "expired");
});

test("expiry sweeper cancels only active expired items without either gate", async () => {
  const householdID = unique("expiry-home");
  await seedHousehold(householdID);
  const expiredID = "b".repeat(64);
  const futureID = "c".repeat(64);
  await db.doc(`users/member-a/notificationInbox/${expiredID}`).set(inbox({
    householdID, intentID: expiredID, expiresAt: Timestamp.fromMillis(5_000),
  }));
  await db.doc(`users/member-a/notificationInbox/${futureID}`).set(inbox({
    householdID, intentID: futureID, expiresAt: Timestamp.fromMillis(50_000),
  }));
  const result = await expireNotificationInboxAt(db, new Date(10_000));
  assert.deepEqual(result, { cancelled: 1 });
  assert.equal((await db.doc(`users/member-a/notificationInbox/${expiredID}`).get()).data().status, "cancelled");
  assert.equal((await db.doc(`users/member-a/notificationInbox/${futureID}`).get()).data().status, "active");
});

test("manifest freezes canonical enabled installation selection and deduplicates one token", async () => {
  const householdID = unique("manifest-home");
  await seedHousehold(householdID);
  const intentID = "d".repeat(64);
  await db.doc(`users/member-a/notificationInbox/${intentID}`).set(inbox({
    householdID, intentID, sourceRevision: 2,
    expiresAt: Timestamp.fromMillis(100_000), nextDispatchAt: Timestamp.fromMillis(2_000),
  }));
  const first = "1".repeat(64);
  const duplicate = "2".repeat(64);
  const second = "3".repeat(64);
  await Promise.all([
    seedToken("member-a", first, householdID, "token-1"),
    seedToken("member-a", duplicate, householdID, "token-1"),
    seedToken("member-a", second, householdID, "token-2"),
  ]);
  const result = await materializeNotificationDeliveriesAt({
    db, uid: "member-a", intentID, now: new Date(5_000), bindingKeyVersion: 7,
  });
  assert.deepEqual(result, { status: "complete", selectedCount: 2 });
  const manifest = (await db.doc(
    `users/member-a/notificationDeliveryManifests/${intentID}`,
  ).get()).data();
  assert.deepEqual(manifest.selectedInstallationHashes, [first, second]);
  assert.equal(manifest.bindingKeyVersion, 7);
  const deliveries = await db.collection(`users/member-a/notificationDeliveries`).get();
  assert.equal(deliveries.size, 2);
  assert.ok(deliveries.docs.every((item) => item.data().status === "queued"));
});

test("dispatch stays queued when either gate is off and fake provider sees no call", async () => {
  await Promise.all([
    db.doc("systemConfig/notificationIntentGenerationV2").delete(),
    db.doc("systemConfig/notificationDispatchV2").delete(),
  ]);
  const householdID = unique("dispatch-off-home");
  await seedHousehold(householdID);
  const intentID = "e".repeat(64);
  const installationHash = "4".repeat(64);
  const deliveryID = await seedDispatchGraph({ householdID, intentID, installationHash });
  const calls = [];
  const result = await dispatchNotificationDeliveryAt({
    db, uid: "member-a", deliveryID, projectID: projectId,
    keyRing: new Map([[1, "test-secret"]]),
    provider: async (message) => { calls.push(message); return { kind: "accepted" }; },
    now: new Date(20_000),
  });
  assert.deepEqual(result, { status: "deferred", reason: "gatesDisabled" });
  assert.equal(calls.length, 0);
  const stored = (await db.doc(`users/member-a/notificationDeliveries/${deliveryID}`).get()).data();
  assert.equal(stored.status, "queued");
  assert.equal(stored.attemptCount, 0);
});

test("enabled dispatch rechecks authority, reserves one endpoint, and emits only generic payload", async () => {
  await Promise.all([
    db.doc("systemConfig/notificationIntentGenerationV2").set(gate({
      projectID: projectId,
    })),
    db.doc("systemConfig/notificationDispatchV2").set(gate({
      projectID: projectId,
    })),
  ]);
  const householdID = unique("dispatch-on-home");
  await seedHousehold(householdID);
  const intentID = "f".repeat(64);
  const installationHash = "5".repeat(64);
  const deliveryID = await seedDispatchGraph({ householdID, intentID, installationHash });
  await db.doc(`users/member-a/notificationInbox/${intentID}`).update({
    preferenceRevision: 1,
  });
  await db.doc(
    `users/member-a/householdNotificationPreferences/${householdID}`,
  ).set(canonicalPreference(householdID));
  const calls = [];
  const result = await dispatchNotificationDeliveryAt({
    db, uid: "member-a", deliveryID, projectID: projectId,
    keyRing: new Map([[1, "test-secret"]]),
    provider: async (message) => {
      calls.push(message);
      return { kind: "accepted" };
    },
    now: new Date(20_000),
  });
  assert.deepEqual(result, { status: "accepted" });
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0].data, {
    schemaVersion: "1", destination: "notificationInbox",
    householdID, inboxItemID: intentID,
  });
  assert.equal(calls[0].notification.title, "CoPaw");
  assert.equal(calls[0].notification.body, "ケアの更新があります / Care update available");
  assert.match(calls[0].collapseKey, /^copaw-[a-f0-9]{32}$/);
  assert.equal(JSON.stringify(calls[0]).includes("Private"), false);
  const stored = (await db.doc(
    `users/member-a/notificationDeliveries/${deliveryID}`,
  ).get()).data();
  assert.equal(stored.status, "providerAccepted");
  const bindings = await db.collection(
    `households/${householdID}/notificationEndpointBindings`,
  ).get();
  assert.equal(bindings.size, 1);
  assert.equal(bindings.docs[0].data().winningDeliveryID, deliveryID);
  assert.equal(bindings.docs[0].data().status, "providerAccepted");
});

test("P1 lease re-entry and converged endpoint cannot double-call provider or overwrite a new lease", async () => {
  await enableGates();
  const householdID = unique("lease-reentry-home");
  await seedHousehold(householdID);
  const intentID = "6".repeat(64);
  const firstHash = "6".repeat(64);
  const secondHash = "7".repeat(64);
  const firstDeliveryID = await seedDispatchGraph({
    householdID, intentID, installationHash: firstHash,
  });
  const secondDeliveryID = deliveryIDFor(intentID, secondHash);
  await seedToken("member-a", secondHash, householdID, "token-1");
  await db.doc(`users/member-a/notificationInbox/${intentID}`).update({
    preferenceRevision: 1,
  });
  await db.doc(
    `users/member-a/householdNotificationPreferences/${householdID}`,
  ).set(canonicalPreference(householdID));
  await db.doc(
    `users/member-a/notificationDeliveryManifests/${intentID}`,
  ).update({
    selectedInstallationHashes: [firstHash, secondHash], selectedCount: 2,
  });
  await db.doc(`users/member-a/notificationDeliveries/${secondDeliveryID}`).set(
    queuedDelivery({
      deliveryID: secondDeliveryID, intentID, householdID,
      installationHash: secondHash,
    }),
  );
  let releaseProvider;
  let providerStarted;
  const started = new Promise((resolve) => { providerStarted = resolve; });
  const release = new Promise((resolve) => { releaseProvider = resolve; });
  let calls = 0;
  const first = dispatchNotificationDeliveryAt({
    db, uid: "member-a", deliveryID: firstDeliveryID, projectID: projectId,
    keyRing: new Map([[1, "test-secret"]]),
    provider: async () => {
      calls += 1;
      providerStarted();
      await release;
      return { kind: "accepted" };
    },
    now: new Date(20_000),
  });
  await started;
  const duplicate = await dispatchNotificationDeliveryAt({
    db, uid: "member-a", deliveryID: secondDeliveryID, projectID: projectId,
    keyRing: new Map([[1, "test-secret"]]),
    provider: async () => { calls += 1; return { kind: "accepted" }; },
    now: new Date(20_001),
  });
  assert.equal(duplicate.status, "cancelled");
  assert.equal(calls, 1);

  const replacementLease = "replacement-lease";
  const firstRef = db.doc(`users/member-a/notificationDeliveries/${firstDeliveryID}`);
  const claimRef = db.doc(
    `households/${householdID}/membershipRevocations/member-a/` +
    `notificationClaims/${firstDeliveryID}`,
  );
  await Promise.all([
    firstRef.update({ leaseID: replacementLease }),
    claimRef.update({ leaseID: replacementLease }),
  ]);
  releaseProvider();
  await first;
  const after = (await firstRef.get()).data();
  assert.equal(after.status, "attempting");
  assert.equal(after.leaseID, replacementLease);
});

test("P1 final pre-send full authority rejects malformed source and category policy without provider call", async () => {
  await enableGates();
  const householdID = unique("final-authority-home");
  await seedHousehold(householdID);
  const intentID = "8".repeat(64);
  const installationHash = "8".repeat(64);
  const deliveryID = await seedDispatchGraph({ householdID, intentID, installationHash });
  await db.doc(`users/member-a/notificationInbox/${intentID}`).update({
    category: "assignment", level: "directAssignment", routeReason: "directTarget",
    preferenceRevision: 1,
  });
  await db.doc(`households/${householdID}/tasks/task-a`).update({
    assignmentMode: "direct", assignmentRequestID: "request-1",
    requestedByID: "member-b", requestedToID: "member-a",
  });
  const preference = canonicalPreference(householdID);
  preference.assignmentAlertsEnabled = false;
  await db.doc(
    `users/member-a/householdNotificationPreferences/${householdID}`,
  ).set(preference);
  let calls = 0;
  const result = await dispatchNotificationDeliveryAt({
    db, uid: "member-a", deliveryID, projectID: projectId,
    keyRing: new Map([[1, "test-secret"]]),
    provider: async () => { calls += 1; return { kind: "accepted" }; },
    now: new Date(20_000),
  });
  assert.equal(result.status, "skipped");
  assert.equal(calls, 0);
  assert.equal((await db.doc(
    `users/member-a/notificationDeliveries/${deliveryID}`,
  ).get()).data().status, "cancelled");
});

test("P1 exact delivery state and null matrix rejects a fourth attempt and residual lease fields", async () => {
  await enableGates();
  const householdID = unique("delivery-matrix-home");
  await seedHousehold(householdID);
  const intentID = "9".repeat(64);
  const installationHash = "9".repeat(64);
  const deliveryID = await seedDispatchGraph({ householdID, intentID, installationHash });
  const delivery = db.doc(`users/member-a/notificationDeliveries/${deliveryID}`);
  await delivery.update({ attemptCount: 3 });
  let calls = 0;
  assert.deepEqual(await dispatchNotificationDeliveryAt({
    db, uid: "member-a", deliveryID, projectID: projectId,
    keyRing: new Map([[1, "test-secret"]]),
    provider: async () => { calls += 1; return { kind: "accepted" }; },
    now: new Date(20_000),
  }), { status: "skipped", reason: "notReady" });
  await delivery.update({
    attemptCount: 0, leaseID: "residual", leaseExpiresAt: Timestamp.fromMillis(30_000),
  });
  assert.deepEqual(await dispatchNotificationDeliveryAt({
    db, uid: "member-a", deliveryID, projectID: projectId,
    keyRing: new Map([[1, "test-secret"]]),
    provider: async () => { calls += 1; return { kind: "accepted" }; },
    now: new Date(20_000),
  }), { status: "skipped", reason: "notReady" });
  assert.equal(calls, 0);
});

test("P1 manifest crash resume uses persisted cursor and conflict blocks without partial batch writes", async () => {
  const householdID = unique("manifest-resume-home");
  await seedHousehold(householdID);
  const intentID = "a1".repeat(32);
  const hashes = ["a".repeat(64), "b".repeat(64), "c".repeat(64)];
  await db.doc(`users/member-a/notificationInbox/${intentID}`).set(inbox({
    householdID, intentID, expiresAt: Timestamp.fromMillis(100_000),
    nextDispatchAt: Timestamp.fromMillis(2_000),
  }));
  await seedMaterializingManifest({ householdID, intentID, hashes, cursor: hashes[0] });
  const firstID = deliveryIDFor(intentID, hashes[0]);
  await db.doc(`users/member-a/notificationDeliveries/${firstID}`).set(
    queuedDelivery({
      deliveryID: firstID, intentID, householdID, installationHash: hashes[0],
    }),
  );
  const conflictID = deliveryIDFor(intentID, hashes[1]);
  await db.doc(`users/member-a/notificationDeliveries/${conflictID}`).set({
    ...queuedDelivery({
      deliveryID: conflictID, intentID, householdID, installationHash: hashes[1],
    }),
    householdID: "wrong-household",
  });
  const result = await materializeNotificationDeliveriesAt({
    db, uid: "member-a", intentID, now: new Date(10_000), bindingKeyVersion: 1,
  });
  assert.deepEqual(result, { status: "blocked", selectedCount: 3 });
  assert.equal((await db.doc(
    `users/member-a/notificationDeliveries/${deliveryIDFor(intentID, hashes[2])}`,
  ).get()).exists, false);
  assert.equal((await db.doc(
    `users/member-a/notificationDeliveryManifests/${intentID}`,
  ).get()).data().safeErrorCode, "conflictingDelivery");

  const recoveryHome = unique("manifest-recovery-home");
  await seedHousehold(recoveryHome);
  const recoveryIntent = "d".repeat(64);
  const recoveryHashes = ["d".repeat(64), "e".repeat(64)];
  await db.doc(`users/member-a/notificationInbox/${recoveryIntent}`).set(inbox({
    householdID: recoveryHome, intentID: recoveryIntent,
    expiresAt: Timestamp.fromMillis(100_000),
    nextDispatchAt: Timestamp.fromMillis(2_000),
  }));
  await seedMaterializingManifest({
    householdID: recoveryHome, intentID: recoveryIntent,
    hashes: recoveryHashes, cursor: recoveryHashes[0], nextRecoveryAt: 5_000,
  });
  const recovered = await recoverNotificationManifestsAt({ db, now: new Date(10_000) });
  assert.ok(recovered.resumed >= 1);
  assert.equal((await db.doc(
    `users/member-a/notificationDeliveryManifests/${recoveryIntent}`,
  ).get()).data().status, "complete");
});

test("P1 generator resolves recipients, materializes medication, and cancels terminal source intent", async () => {
  await enableGenerationOnly();
  const householdID = unique("generator-home");
  await seedHousehold(householdID);
  await db.doc(
    `users/member-a/householdNotificationPreferences/${householdID}`,
  ).set(canonicalPreference(householdID));
  const medication = db.doc(`households/${householdID}/medications/medication-1`);
  await medication.set({
    schemaVersion: 1, id: "medication-1", petID: "legacy-primary",
    displayName: "Private medicine", purpose: null, possibleSideEffects: null,
    isActive: true, currentScheduleVersion: 1,
    currentScheduleVersionID: "v000001", revision: 0,
    createdAt: Timestamp.fromMillis(1_000), createdByID: "member-a",
    createdByName: "member-a", updatedAt: Timestamp.fromMillis(1_000),
    updatedByID: "member-a",
  });
  await medication.collection("scheduleVersions").doc("v000001").set({
    schemaVersion: 1, id: "v000001", medicationID: "medication-1", version: 1,
    petID: "legacy-primary", petName: "Mochi", medicationName: "Private medicine",
    weekdays: [2], slots: [{
      slotID: "morning", hour: 9, minute: 0,
      doseText: "Private dose", instructions: null,
    }],
    timeZoneIdentifier: "Asia/Tokyo", dstPolicy: "reject",
    effectiveFromLocalDate: "2026-08-01", effectiveUntilLocalDate: null,
    createdAt: Timestamp.fromMillis(1_000), createdByID: "member-a",
    createdByName: "member-a", closedAt: null, closedByID: null,
    replacedByVersionID: null, revision: 0,
  });
  const generated = await generateMedicationNotificationIntentsAt({
    db, projectID: projectId, now: new Date("2026-08-17T00:00:00.000Z"),
  });
  assert.equal(generated.materialized, 1);
  assert.equal(generated.created, 1);
  const occurrences = await db.collection(
    `households/${householdID}/medicationOccurrences`,
  ).get();
  assert.equal(occurrences.size, 1);
  const inboxItems = await db.collection(`users/member-a/notificationInbox`)
    .where("householdID", "==", householdID).get();
  assert.equal(inboxItems.size, 1);
  await occurrences.docs[0].ref.update({
    outcomeStatus: "administered", outcomeByID: "member-a",
    outcomeByName: "member-a", outcomeAt: Timestamp.fromMillis(
      Date.parse("2026-08-17T00:01:00.000Z"),
    ), revision: 1,
  });
  await generateNotificationSourceAt({
    db, householdID, sourceType: "medicationOccurrence",
    sourceID: occurrences.docs[0].id, projectID: projectId,
    now: new Date("2026-08-17T00:01:00.000Z"),
  });
  assert.equal((await inboxItems.docs[0].ref.get()).data().status, "cancelled");
});

test("P1 digest finalizes, late-valid source reopens noValidSource, and candidate cap blocks", async () => {
  await enableGenerationOnly();
  const householdID = unique("digest-home");
  await seedHousehold(householdID);
  await db.doc(
    `users/member-a/householdNotificationPreferences/${householdID}`,
  ).set(canonicalPreference(householdID));
  const task = db.doc(`households/${householdID}/tasks/direct-task`);
  await task.set(directTask("direct-task", 1, 2_000));
  const generation = await generateNotificationSourceAt({
    db, householdID, sourceType: "task", sourceID: "direct-task",
    projectID: projectId, now: new Date(20_000),
  });
  assert.equal(generation.created, 1);
  const digests = await db.collection(`users/member-a/notificationDigests`).get();
  assert.equal(digests.size, 1);
  const digest = digests.docs[0];
  const ready = await finalizeNotificationDigestAt({
    db, uid: "member-a", digestID: digest.id, projectID: projectId,
    now: new Date(digest.data().nextFinalizeAt.toMillis()),
  });
  assert.equal(ready.status, "ready");

  const reopenHome = unique("digest-reopen-home");
  await seedHousehold(reopenHome);
  await db.doc(
    `users/member-a/householdNotificationPreferences/${reopenHome}`,
  ).set(canonicalPreference(reopenHome));
  const reopenTask = db.doc(`households/${reopenHome}/tasks/reopen-task`);
  await reopenTask.set(directTask("reopen-task", 1, 2_000));
  await generateNotificationSourceAt({
    db, householdID: reopenHome, sourceType: "task", sourceID: "reopen-task",
    projectID: projectId, now: new Date(20_000),
  });
  const reopenDigest = (await db.collection(
    `users/member-a/notificationDigests`,
  ).where("householdID", "==", reopenHome).get()).docs[0];
  await reopenTask.update({ status: "completed", revision: 2 });
  assert.equal((await finalizeNotificationDigestAt({
    db, uid: "member-a", digestID: reopenDigest.id, projectID: projectId,
    now: new Date(reopenDigest.data().nextFinalizeAt.toMillis()),
  })).status, "cancelled");
  await reopenTask.set(directTask("reopen-task", 3,
    reopenDigest.data().windowStartAt.toMillis() + 30_000));
  await generateNotificationSourceAt({
    db, householdID: reopenHome, sourceType: "task", sourceID: "reopen-task",
    projectID: projectId,
    now: new Date(reopenDigest.data().windowEndAt.toMillis() + 1),
  });
  assert.equal((await reopenDigest.ref.get()).data().status, "collecting");

  const capHome = unique("digest-cap-home");
  await seedHousehold(capHome);
  await db.doc(
    `users/member-a/householdNotificationPreferences/${capHome}`,
  ).set(canonicalPreference(capHome));
  const capDigestID = "f1".repeat(32);
  await db.doc(`users/member-a/notificationDigests/${capDigestID}`).set(
    digestDocument({ householdID: capHome, digestID: capDigestID }),
  );
  for (let offset = 0; offset < 1001; offset += 400) {
    const batch = db.batch();
    for (let index = offset; index < Math.min(offset + 400, 1001); index += 1) {
      const id = index.toString(16).padStart(64, "0");
      batch.set(db.doc(`users/member-a/notificationInbox/${id}`), {
        householdID: capHome,
        recipientJoinedAtSnapshot: Timestamp.fromMillis(500),
        category: "assignment", sourceType: "task",
        coalescingKey: capDigestID, createdAt: Timestamp.fromMillis(index + 1),
      });
    }
    await batch.commit();
  }
  assert.equal((await finalizeNotificationDigestAt({
    db, uid: "member-a", digestID: capDigestID, projectID: projectId,
    now: new Date(20_000),
  })).status, "blocked");
});

test("P1 stale preference is rejected by exact epoch and legacy broad dispatch export is absent", async () => {
  const householdID = unique("stale-preference-home");
  await seedHousehold(householdID);
  const stale = canonicalPreference(householdID);
  stale.memberJoinedAtSnapshot = Timestamp.fromMillis(499);
  await db.doc(
    `users/member-a/householdNotificationPreferences/${householdID}`,
  ).set(stale);
  await assert.rejects(setHouseholdNotificationPreferencesAt(
    db,
    request("member-a", {
      ...preferenceInput(householdID), expectedRevision: 1,
      clientMutationID: unique("stale-epoch-save"),
    }),
  ), hasCode("failed-precondition"));
  const reset = await resetMalformedNotificationPreferencesAt(
    db,
    request("member-a", {
      householdID, clientMutationID: unique("stale-epoch-reset"),
    }),
    new Date(10_000),
  );
  assert.equal(reset.revision, 2);
  assert.deepEqual(Object.keys(legacyNotifications).sort(), [
    "plannedMedicationReminderWindows",
  ]);
});

test("P1 digest dispatch revalidates every original source and the effective cutoff", async () => {
  await enableGates();
  const terminal = await seedReadyDigestDelivery("digest-terminal");
  await terminal.task.update({ status: "completed", revision: 2 });
  let calls = 0;
  const terminalResult = await dispatchNotificationDeliveryAt({
    db, uid: "member-a", deliveryID: terminal.deliveryID, projectID: projectId,
    keyRing: new Map([[1, "test-secret"]]),
    provider: async () => { calls += 1; return { kind: "accepted" }; },
    now: new Date(terminal.dispatchAt),
  });
  assert.equal(terminalResult.status, "skipped");
  assert.equal((await db.doc(
    `users/member-a/notificationDeliveries/${terminal.deliveryID}`,
  ).get()).data().status, "cancelled");
  assert.equal(calls, 0);

  const cutover = await seedReadyDigestDelivery("digest-cutover");
  await db.doc("systemConfig/notificationDispatchV2").set({
    ...gate({ projectID: projectId }),
    cutoverAt: Timestamp.fromMillis(cutover.semanticAt + 1),
  });
  const cutoverResult = await dispatchNotificationDeliveryAt({
    db, uid: "member-a", deliveryID: cutover.deliveryID, projectID: projectId,
    keyRing: new Map([[1, "test-secret"]]),
    provider: async () => { calls += 1; return { kind: "accepted" }; },
    now: new Date(cutover.dispatchAt),
  });
  assert.equal(cutoverResult.status, "skipped");
  assert.equal((await db.doc(
    `users/member-a/notificationDeliveries/${cutover.deliveryID}`,
  ).get()).data().status, "cancelled");
  assert.equal(calls, 0);
});

test("P1 endpoint binding recovery, authority cancellation, and tokenInvalid stay consistent", async () => {
  await enableGates();
  const expiredHome = unique("binding-expired-home");
  await seedHousehold(expiredHome);
  const expiredIntent = "b1".repeat(32);
  const expiredHash = "b".repeat(64);
  const expiredDelivery = await seedDispatchGraph({
    householdID: expiredHome, intentID: expiredIntent,
    installationHash: expiredHash,
  });
  await seedDispatchPreference(expiredHome, expiredIntent);
  let releaseProvider;
  let providerStarted;
  const started = new Promise((resolve) => { providerStarted = resolve; });
  const release = new Promise((resolve) => { releaseProvider = resolve; });
  const inFlight = dispatchNotificationDeliveryAt({
    db, uid: "member-a", deliveryID: expiredDelivery, projectID: projectId,
    keyRing: new Map([[1, "test-secret"]]),
    provider: async () => {
      providerStarted();
      await release;
      return { kind: "accepted" };
    },
    now: new Date(20_000),
  });
  await started;
  await recoverAttemptingDeliveriesAt({ db, now: new Date(80_001) });
  const expiredBinding = (await db.collection(
    `households/${expiredHome}/notificationEndpointBindings`,
  ).get()).docs[0];
  assert.equal(expiredBinding.data().status, "providerUnknown");
  releaseProvider();
  await inFlight;

  const retryHome = unique("binding-retry-home");
  await seedHousehold(retryHome);
  const retryIntent = "b2".repeat(32);
  const retryHash = "c".repeat(64);
  const retryDelivery = await seedDispatchGraph({
    householdID: retryHome, intentID: retryIntent, installationHash: retryHash,
  });
  await seedDispatchPreference(retryHome, retryIntent);
  await db.doc(`users/member-a/notificationInbox/${retryIntent}`).update({
    expiresAt: Timestamp.fromMillis(1_000_000),
  });
  assert.equal((await dispatchNotificationDeliveryAt({
    db, uid: "member-a", deliveryID: retryDelivery, projectID: projectId,
    keyRing: new Map([[1, "test-secret"]]),
    provider: async () => ({ kind: "definiteRetryableRejection" }),
    now: new Date(20_000),
  })).status, "definiteRetryableRejection");
  await db.doc(`households/${retryHome}/tasks/task-a`).update({
    status: "completed", revision: 3,
  });
  await dispatchNotificationDeliveryAt({
    db, uid: "member-a", deliveryID: retryDelivery, projectID: projectId,
    keyRing: new Map([[1, "test-secret"]]),
    provider: async () => ({ kind: "accepted" }),
    now: new Date(320_000),
  });
  const retryBinding = (await db.collection(
    `households/${retryHome}/notificationEndpointBindings`,
  ).get()).docs[0];
  assert.equal(retryBinding.data().status, "cancelled");

  const invalidHome = unique("binding-invalid-token-home");
  await seedHousehold(invalidHome);
  const invalidIntent = "b3".repeat(32);
  const invalidHash = "d".repeat(64);
  const duplicateHash = "e".repeat(64);
  const invalidDelivery = await seedDispatchGraph({
    householdID: invalidHome, intentID: invalidIntent,
    installationHash: invalidHash,
  });
  await seedDispatchPreference(invalidHome, invalidIntent);
  await seedToken("member-a", duplicateHash, invalidHome, "token-1");
  await dispatchNotificationDeliveryAt({
    db, uid: "member-a", deliveryID: invalidDelivery, projectID: projectId,
    keyRing: new Map([[1, "test-secret"]]),
    provider: async () => ({
      kind: "definitePermanentRejection", reason: "tokenInvalid",
    }),
    now: new Date(20_000),
  });
  assert.equal((await db.doc(
    `users/member-a/notificationDeliveries/${invalidDelivery}`,
  ).get()).data().safeErrorCode, "tokenInvalid");
  assert.deepEqual((await Promise.all([invalidHash, duplicateHash].map(async (hash) =>
    (await db.doc(`users/member-a/notificationTokens/${hash}`).get()).data().enabled))),
  [false, false]);
});

test("P1 generator rejects malformed sources and reconciles revision or recipient changes", async () => {
  await enableGenerationOnly();
  const malformedHome = unique("generator-malformed-home");
  await seedHousehold(malformedHome);
  await db.doc(
    `households/${malformedHome}/taskResponsibilityTransfers/bad-transfer`,
  ).set({
    id: "bad-transfer", revision: 1, status: "pending",
    consentByID: "member-a", requestedByID: "member-b",
    taskID: "task-a", createdAt: Timestamp.fromMillis(2_000),
  });
  assert.equal((await generateNotificationSourceAt({
    db, householdID: malformedHome, sourceType: "taskResponsibilityTransfer",
    sourceID: "bad-transfer", projectID: projectId, now: new Date(20_000),
  })).created, 0);
  await db.doc(
    `households/${malformedHome}/medicationOccurrences/bad-occurrence`,
  ).set({
    id: "bad-occurrence", revision: 0, outcomeStatus: "unresolved",
    dueAt: Timestamp.fromMillis(2_000), responsibilityStatus: "unclaimed",
    responsibleByID: null,
  });
  assert.equal((await generateNotificationSourceAt({
    db, householdID: malformedHome, sourceType: "medicationOccurrence",
    sourceID: "bad-occurrence", projectID: projectId, now: new Date(2_001),
  })).created, 0);

  const reconcileHome = unique("generator-reconcile-home");
  await seedHousehold(reconcileHome);
  const task = db.doc(`households/${reconcileHome}/tasks/direct-task`);
  await task.set(directTask("direct-task", 1, 2_000));
  await generateNotificationSourceAt({
    db, householdID: reconcileHome, sourceType: "task", sourceID: "direct-task",
    projectID: projectId, now: new Date(20_000),
  });
  await task.set(directTask("direct-task", 2, 3_000, {
    requestedByID: "member-a", requestedToID: "member-b",
  }));
  await generateNotificationSourceAt({
    db, householdID: reconcileHome, sourceType: "task", sourceID: "direct-task",
    projectID: projectId, now: new Date(21_000),
  });
  const oldItems = await db.collection("users/member-a/notificationInbox")
    .where("householdID", "==", reconcileHome).get();
  const newItems = await db.collection("users/member-b/notificationInbox")
    .where("householdID", "==", reconcileHome).get();
  assert.equal(oldItems.docs.filter((item) => item.data().status === "active").length, 0);
  assert.equal(newItems.docs.filter((item) => item.data().status === "active").length, 1);
});

test("P1 digest finalizer does not report ready after a transaction no-op or malformed summary", async () => {
  await enableGenerationOnly();
  const race = await seedCollectingDigest("digest-finalize-race");
  const racingDb = new Proxy(db, {
    get(target, property) {
      if (property === "runTransaction") {
        return async (callback) => {
          await target.doc("systemConfig/notificationIntentGenerationV2").delete();
          return target.runTransaction(callback);
        };
      }
      const value = Reflect.get(target, property);
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
  const raced = await finalizeNotificationDigestAt({
    db: racingDb, uid: "member-a", digestID: race.digest.id,
    projectID: projectId, now: new Date(race.digest.data().nextFinalizeAt.toMillis()),
  });
  assert.notEqual(raced.status, "ready");
  assert.equal((await race.digest.ref.get()).data().status, "collecting");

  await enableGenerationOnly();
  const malformed = await seedCollectingDigest("digest-finalize-malformed");
  const summaryID = digestSummaryID(malformed.householdID, malformed.digest);
  await db.doc(`users/member-a/notificationInbox/${summaryID}`).set({ malformed: true });
  const result = await finalizeNotificationDigestAt({
    db, uid: "member-a", digestID: malformed.digest.id, projectID: projectId,
    now: new Date(malformed.digest.data().nextFinalizeAt.toMillis()),
  });
  assert.notEqual(result.status, "ready");
  assert.equal((await malformed.digest.ref.get()).data().status, "collecting");
});

test("P1 claim-stage digest rejection atomically converges digest summary and delivery", async () => {
  await enableGates();
  const invalid = await seedReadyDigestDelivery("claim-digest-invalid");
  await invalid.task.update({ status: "completed", revision: 2 });
  await dispatchNotificationDeliveryAt({
    db, uid: "member-a", deliveryID: invalid.deliveryID, projectID: projectId,
    keyRing: new Map([[1, "test-secret"]]),
    provider: async () => ({ kind: "accepted" }),
    now: new Date(invalid.dispatchAt),
  });
  assert.equal((await invalid.digest.ref.get()).data().status, "cancelled");
  assert.equal((await invalid.digest.ref.get()).data().cancelReason, "noValidSource");
  const invalidSummary = (await db.collection("users/member-a/notificationInbox")
    .where("householdID", "==", invalid.householdID)
    .where("sourceType", "==", "notificationDigest").get()).docs[0];
  assert.equal(invalidSummary.data().status, "cancelled");
  assert.equal((await db.doc(
    `users/member-a/notificationDeliveries/${invalid.deliveryID}`,
  ).get()).data().status, "cancelled");

  const blocked = await seedReadyDigestDelivery("claim-digest-blocked");
  await blocked.task.update({ status: "completed", revision: 2 });
  for (let offset = 0; offset < 1001; offset += 400) {
    const batch = db.batch();
    for (let index = offset; index < Math.min(offset + 400, 1001); index += 1) {
      const id = uniqueHexID(index + 20_000);
      batch.set(db.doc(`users/member-a/notificationInbox/${id}`), {
        householdID: blocked.householdID,
        recipientJoinedAtSnapshot: Timestamp.fromMillis(500),
        category: "assignment", sourceType: "task",
        coalescingKey: blocked.digest.id,
        createdAt: Timestamp.fromMillis(index + 1),
      });
    }
    await batch.commit();
  }
  await dispatchNotificationDeliveryAt({
    db, uid: "member-a", deliveryID: blocked.deliveryID, projectID: projectId,
    keyRing: new Map([[1, "test-secret"]]),
    provider: async () => ({ kind: "accepted" }),
    now: new Date(blocked.dispatchAt),
  });
  assert.equal((await blocked.digest.ref.get()).data().status, "blocked");
  assert.equal((await blocked.digest.ref.get()).data().safeErrorCode,
    "tooManyCandidates");
  const blockedSummary = (await db.collection("users/member-a/notificationInbox")
    .where("householdID", "==", blocked.householdID)
    .where("sourceType", "==", "notificationDigest").get()).docs[0];
  assert.equal(blockedSummary.data().status, "cancelled");
});

test("P1 existing medication occurrence must match its plan version and snapshots", async () => {
  await enableGenerationOnly();
  const householdID = unique("medication-relation-home");
  await seedHousehold(householdID);
  await db.doc(
    `users/member-a/householdNotificationPreferences/${householdID}`,
  ).set(canonicalPreference(householdID));
  await seedCanonicalMedicationPlan(householdID);
  const occurrenceID = "medication-1_v000001_2026-08-17_morning";
  await db.doc(
    `households/${householdID}/medicationOccurrences/${occurrenceID}`,
  ).set(canonicalMedicationOccurrence(occurrenceID, {
    petName: "Wrong snapshot",
  }));
  const result = await generateMedicationNotificationIntentsAt({
    db, projectID: projectId, now: new Date("2026-08-17T00:00:01.000Z"),
  });
  assert.equal(result.materialized, 0);
  assert.equal(result.created, 0);
  const items = await db.collection("users/member-a/notificationInbox")
    .where("householdID", "==", householdID).get();
  assert.equal(items.size, 0);
});

test("P1 ready digest without a manifest is recovered by the bounded scanner", async () => {
  await enableGenerationOnly();
  const graph = await seedCollectingDigest(
    "digest-ready-recovery", Date.now(),
  );
  const installationHash = "c4".repeat(32);
  await seedToken("member-a", installationHash, graph.householdID, "token-recovery");
  const ready = await finalizeNotificationDigestAt({
    db, uid: "member-a", digestID: graph.digest.id, projectID: projectId,
    bindingKeyVersion: null,
    now: new Date(graph.digest.data().nextFinalizeAt.toMillis()),
  });
  assert.equal(ready.status, "ready");
  assert.equal((await db.doc(
    `users/member-a/notificationDeliveryManifests/${ready.summaryID}`,
  ).get()).exists, false);
  const recovered = await recoverNotificationDigestsAt({
    db, projectID: projectId, bindingKeyVersion: 1,
    now: new Date(graph.digest.data().windowEndAt.toMillis() + 6_000),
  });
  assert.ok(recovered.recoveredReady >= 1);
  assert.equal((await db.doc(
    `users/member-a/notificationDeliveryManifests/${ready.summaryID}`,
  ).get()).data().status, "complete");
});

test("P1 ready digest recovery paginates past completed rows and isolates malformed rows", async () => {
  await enableGenerationOnly();
  const graph = await seedCollectingDigest("digest-ready-cursor", Date.now());
  const installationHash = "c5".repeat(32);
  await seedToken("member-a", installationHash, graph.householdID, "token-cursor");
  const ready = await finalizeNotificationDigestAt({
    db, uid: "member-a", digestID: graph.digest.id, projectID: projectId,
    bindingKeyVersion: null,
    now: new Date(graph.digest.data().nextFinalizeAt.toMillis()),
  });
  const baseDigest = (await graph.digest.ref.get()).data();
  const baseSummary = (await db.doc(
    `users/member-a/notificationInbox/${ready.summaryID}`,
  ).get()).data();
  const firstReadyAt = baseDigest.readyAt.toMillis() + 1;
  for (let offset = 0; offset < 100; offset += 25) {
    const batch = db.batch();
    for (let index = offset; index < offset + 25; index += 1) {
      const digestID = uniqueHexID(40_000 + index);
      const clonedDigest = {
        ...baseDigest,
        id: digestID,
        coalescingKey: digestID,
        readyAt: Timestamp.fromMillis(firstReadyAt + index),
        updatedAt: Timestamp.fromMillis(firstReadyAt + index),
      };
      const digestRef = db.doc(`users/member-a/notificationDigests/${digestID}`);
      const summaryID = intentIDFor({
        householdID: graph.householdID,
        sourceType: "notificationDigest",
        sourcePath: `notificationDigests/${digestID}`,
        sourceRevision: 1,
        level: "burstSummary",
        recipientID: "member-a",
        recipientJoinedAtSnapshot: clonedDigest.recipientJoinedAtSnapshot,
      });
      batch.set(digestRef, clonedDigest);
      batch.set(db.doc(`users/member-a/notificationInbox/${summaryID}`), {
        ...baseSummary,
        id: summaryID,
        sourceID: digestID,
        sourcePath: `notificationDigests/${digestID}`,
        coalescingKey: digestID,
      });
      batch.set(db.doc(
        `users/member-a/notificationDeliveryManifests/${summaryID}`,
      ), { status: "complete" });
    }
    await batch.commit();
  }
  const malformedDigestID = uniqueHexID(50_000);
  const malformedDigest = {
    ...baseDigest,
    id: malformedDigestID,
    coalescingKey: malformedDigestID,
    readyAt: Timestamp.fromMillis(firstReadyAt + 101),
    updatedAt: Timestamp.fromMillis(firstReadyAt + 101),
  };
  const malformedSummaryID = intentIDFor({
    householdID: graph.householdID,
    sourceType: "notificationDigest",
    sourcePath: `notificationDigests/${malformedDigestID}`,
    sourceRevision: 1,
    level: "burstSummary",
    recipientID: "member-a",
    recipientJoinedAtSnapshot: malformedDigest.recipientJoinedAtSnapshot,
  });
  await Promise.all([
    db.doc(`users/member-a/notificationDigests/${malformedDigestID}`).set(
      malformedDigest,
    ),
    db.doc(`users/member-a/notificationInbox/${malformedSummaryID}`).set({
      ...baseSummary,
      id: malformedSummaryID,
      sourceID: malformedDigestID,
      sourcePath: `notificationDigests/${malformedDigestID}`,
      coalescingKey: malformedDigestID,
    }),
    db.doc(
      `users/member-a/notificationDeliveryManifests/${malformedSummaryID}`,
    ).set({ status: "materializing" }),
  ]);

  for (let attempt = 0; attempt < 3; attempt += 1) {
    await recoverNotificationDigestsAt({
      db, projectID: projectId, bindingKeyVersion: 1,
      now: new Date(baseDigest.windowEndAt.toMillis() + 6_000 + attempt),
    });
  }
  assert.equal((await db.doc(
    `users/member-a/notificationDeliveryManifests/${ready.summaryID}`,
  ).get()).data().status, "complete");
});

test("P1 ready recovery wraps an empty cursor page and excludes malformed readyAt", async () => {
  await enableGenerationOnly();
  const graph = await seedCollectingDigest("digest-ready-wrap", Date.now());
  const installationHash = "c6".repeat(32);
  await seedToken("member-a", installationHash, graph.householdID, "token-wrap");
  const firstReady = await finalizeNotificationDigestAt({
    db, uid: "member-a", digestID: graph.digest.id, projectID: projectId,
    bindingKeyVersion: 1,
    now: new Date(graph.digest.data().nextFinalizeAt.toMillis()),
  });
  const digest = (await graph.digest.ref.get()).data();
  await db.doc("systemConfig/notificationDigestReadyRecoveryV2").set({
    schemaVersion: 1,
    cursorReadyAt: digest.readyAt,
    cursorDocumentPath: graph.digest.ref.path,
    updatedAt: digest.readyAt,
  });
  await db.doc(
    `users/member-a/notificationDigests/${uniqueHexID(60_000)}`,
  ).set({ status: "ready", readyAt: null });
  await recoverNotificationDigestsAt({
    db, projectID: projectId, bindingKeyVersion: 1,
    now: new Date(digest.windowEndAt.toMillis() + 6_000),
  });
  assert.equal((await db.doc(
    "systemConfig/notificationDigestReadyRecoveryV2",
  ).get()).exists, false);

  const newer = await seedCollectingDigest(
    "digest-ready-after-wrap", Date.now() + 86_400_000,
  );
  const newerToken = "c7".repeat(32);
  await seedToken("member-a", newerToken, newer.householdID, "token-after-wrap");
  const newerReady = await finalizeNotificationDigestAt({
    db, uid: "member-a", digestID: newer.digest.id, projectID: projectId,
    bindingKeyVersion: null,
    now: new Date(newer.digest.data().nextFinalizeAt.toMillis()),
  });
  await recoverNotificationDigestsAt({
    db, projectID: projectId, bindingKeyVersion: 1,
    now: new Date(newer.digest.data().windowEndAt.toMillis() + 6_000),
  });
  assert.equal((await db.doc(
    `users/member-a/notificationDeliveryManifests/${newerReady.summaryID}`,
  ).get()).data().status, "complete");
  assert.equal((await db.doc(
    `users/member-a/notificationDeliveryManifests/${firstReady.summaryID}`,
  ).get()).data().status, "complete");
});

test("P1 ready recovery cursor accepts every valid non-slash UID path segment", async () => {
  await enableGenerationOnly();
  const graph = await seedCollectingDigest(
    "digest-ready-dotted-uid", Date.now() + 172_800_000,
  );
  const installationHash = "c8".repeat(32);
  await seedToken("member-a", installationHash, graph.householdID, "token-dotted");
  const ready = await finalizeNotificationDigestAt({
    db, uid: "member-a", digestID: graph.digest.id, projectID: projectId,
    bindingKeyVersion: null,
    now: new Date(graph.digest.data().nextFinalizeAt.toMillis()),
  });
  const digest = (await graph.digest.ref.get()).data();
  const boundaryAt = Timestamp.fromMillis(digest.readyAt.toMillis() + 1_000);
  const boundaryID = uniqueHexID(70_000);
  await db.doc("systemConfig/notificationDigestReadyRecoveryV2").set({
    schemaVersion: 1,
    cursorReadyAt: boundaryAt,
    cursorDocumentPath:
      `users/member.with.dot/notificationDigests/${boundaryID}`,
    updatedAt: boundaryAt,
  });
  for (let offset = 0; offset < 100; offset += 25) {
    const batch = db.batch();
    for (let index = offset; index < offset + 25; index += 1) {
      batch.set(db.doc(
        `users/member-a/notificationDigests/${uniqueHexID(71_000 + index)}`,
      ), {
        status: "ready",
        readyAt: Timestamp.fromMillis(boundaryAt.toMillis() + 1_000 + index),
      });
    }
    await batch.commit();
  }
  await recoverNotificationDigestsAt({
    db, projectID: projectId, bindingKeyVersion: 1,
    now: new Date(digest.windowEndAt.toMillis() + 6_000),
  });
  assert.equal((await db.doc(
    `users/member-a/notificationDeliveryManifests/${ready.summaryID}`,
  ).get()).data().status, "complete");
});

test("P1 future medication replace or stop preserves today effective version reminder", async () => {
  await enableGenerationOnly();
  for (const mode of ["replace", "stop"]) {
    const householdID = unique(`medication-${mode}-effective-home`);
    await seedHousehold(householdID);
    await db.doc(
      `users/member-a/householdNotificationPreferences/${householdID}`,
    ).set(canonicalPreference(householdID));
    await seedCanonicalMedicationPlan(householdID);
    const medication = db.doc(
      `households/${householdID}/medications/medication-1`,
    );
    const versionOne = medication.collection("scheduleVersions").doc("v000001");
    await versionOne.update({
      effectiveUntilLocalDate: "2026-08-18",
      closedAt: Timestamp.fromMillis(2_000), closedByID: "member-a",
      replacedByVersionID: mode === "replace" ? "v000002" : null,
      revision: 1,
    });
    if (mode === "replace") {
      const versionTwo = {
        ...(await versionOne.get()).data(),
        id: "v000002", version: 2,
        effectiveFromLocalDate: "2026-08-18",
        effectiveUntilLocalDate: null, createdAt: Timestamp.fromMillis(2_000),
        closedAt: null, closedByID: null, replacedByVersionID: null, revision: 0,
      };
      await medication.collection("scheduleVersions").doc("v000002").set(versionTwo);
      await medication.update({
        currentScheduleVersion: 2, currentScheduleVersionID: "v000002",
        revision: 1, updatedAt: Timestamp.fromMillis(2_000),
      });
    } else {
      await medication.update({
        isActive: false, revision: 1, updatedAt: Timestamp.fromMillis(2_000),
      });
    }
    const occurrenceID = "medication-1_v000001_2026-08-17_morning";
    await db.doc(
      `households/${householdID}/medicationOccurrences/${occurrenceID}`,
    ).set(canonicalMedicationOccurrence(occurrenceID));
  }

  const result = await generateMedicationNotificationIntentsAt({
    db, projectID: projectId, now: new Date("2026-08-17T00:00:01.000Z"),
  });
  assert.ok(result.created >= 2);
  for (const mode of ["replace", "stop"]) {
    const items = await db.collection("users/member-a/notificationInbox")
      .where("sourceType", "==", "medicationOccurrence")
      .where("sourceID", "==", "medication-1_v000001_2026-08-17_morning")
      .get();
    assert.ok(items.docs.some((document) =>
      document.data().householdID.includes(`medication-${mode}-effective-home`)));
  }
});

test("P1 digest claim membership or preference loss converges summary and delivery", async () => {
  await enableGates();
  const membership = await seedReadyDigestDelivery("claim-digest-membership");
  await db.doc(`households/${membership.householdID}/members/member-a`).delete();
  await dispatchNotificationDeliveryAt({
    db, uid: "member-a", deliveryID: membership.deliveryID, projectID: projectId,
    keyRing: new Map([[1, "test-secret"]]),
    provider: async () => ({ kind: "accepted" }),
    now: new Date(membership.dispatchAt),
  });
  assert.equal((await membership.digest.ref.get()).data().cancelReason,
    "membershipEnded");
  const membershipSummary = (await db.collection("users/member-a/notificationInbox")
    .where("householdID", "==", membership.householdID)
    .where("sourceType", "==", "notificationDigest").get()).docs[0];
  assert.equal(membershipSummary.data().cancelReason, "membershipEnded");

  const policy = await seedReadyDigestDelivery("claim-digest-policy");
  await db.doc(
    `users/member-a/householdNotificationPreferences/${policy.householdID}`,
  ).update({ pushEnabled: false, revision: 2, updatedAt: Timestamp.fromMillis(3_000) });
  await dispatchNotificationDeliveryAt({
    db, uid: "member-a", deliveryID: policy.deliveryID, projectID: projectId,
    keyRing: new Map([[1, "test-secret"]]),
    provider: async () => ({ kind: "accepted" }),
    now: new Date(policy.dispatchAt),
  });
  assert.equal((await policy.digest.ref.get()).data().cancelReason, "policyChanged");
  const policySummary = (await db.collection("users/member-a/notificationInbox")
    .where("householdID", "==", policy.householdID)
    .where("sourceType", "==", "notificationDigest").get()).docs[0];
  assert.equal(policySummary.data().cancelReason, "policyChanged");
});

test("P1 final provider start separates membership policy and installation authority", async () => {
  await enableGates();
  for (const scenario of ["membership", "policy", "installation"]) {
    const graph = await seedReadyDigestDelivery(`final-digest-${scenario}`);
    const deliveryRef = db.doc(
      `users/member-a/notificationDeliveries/${graph.deliveryID}`,
    );
    const installationHash = (await deliveryRef.get()).data().installationHash;
    let transactions = 0;
    const racingDb = new Proxy(db, {
      get(target, property) {
        if (property === "runTransaction") {
          return async (callback) => {
            transactions += 1;
            if (transactions === 2) {
              if (scenario === "membership") {
                await target.doc(
                  `households/${graph.householdID}/members/member-a`,
                ).delete();
              } else if (scenario === "policy") {
                await target.doc(
                  `users/member-a/householdNotificationPreferences/${graph.householdID}`,
                ).update({
                  pushEnabled: false, revision: 2,
                  updatedAt: Timestamp.fromMillis(3_000),
                });
              } else {
                await target.doc(
                  `users/member-a/notificationTokens/${installationHash}`,
                ).update({ enabled: false });
              }
            }
            return target.runTransaction(callback);
          };
        }
        const value = Reflect.get(target, property);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    let calls = 0;
    await dispatchNotificationDeliveryAt({
      db: racingDb, uid: "member-a", deliveryID: graph.deliveryID,
      projectID: projectId, keyRing: new Map([[1, "test-secret"]]),
      provider: async () => { calls += 1; return { kind: "accepted" }; },
      now: new Date(graph.dispatchAt),
    });
    assert.equal(calls, 0);
    const delivery = (await deliveryRef.get()).data();
    assert.equal(delivery.status, "cancelled");
    assert.equal(delivery.safeErrorCode, scenario === "membership"
      ? "membershipEnded"
      : scenario === "policy" ? "policyChanged" : "installationDisabled");
    const summary = (await db.collection("users/member-a/notificationInbox")
      .where("householdID", "==", graph.householdID)
      .where("sourceType", "==", "notificationDigest").get()).docs[0];
    if (scenario === "installation") {
      assert.equal((await graph.digest.ref.get()).data().status, "ready");
      assert.equal(summary.data().status, "active");
    } else {
      assert.equal((await graph.digest.ref.get()).data().cancelReason,
        scenario === "membership" ? "membershipEnded" : "policyChanged");
      assert.equal(summary.data().cancelReason,
        scenario === "membership" ? "membershipEnded" : "policyChanged");
    }
  }
});

function unique(prefix) {
  sequence += 1;
  return `${prefix}-${process.pid}-${sequence}`;
}

function uniqueHexID(value) {
  return value.toString(16).padStart(64, "0");
}

function request(uid, data) {
  return { auth: { uid }, data };
}

function hasCode(code) {
  return (error) => error?.code === code || error?.code === `functions/${code}`;
}

function gate({ projectID }) {
  return {
    schemaVersion: 1, enabled: true, projectID,
    cutoverAt: Timestamp.fromMillis(1_000), updatedBy: "test",
    updatedAt: Timestamp.fromMillis(1_000),
  };
}

async function enableGates() {
  await Promise.all([
    db.doc("systemConfig/notificationIntentGenerationV2").set(gate({
      projectID: projectId,
    })),
    db.doc("systemConfig/notificationDispatchV2").set(gate({
      projectID: projectId,
    })),
  ]);
}

async function enableGenerationOnly() {
  await Promise.all([
    db.doc("systemConfig/notificationIntentGenerationV2").set(gate({
      projectID: projectId,
    })),
    db.doc("systemConfig/notificationDispatchV2").delete(),
  ]);
}

async function seedHousehold(householdID) {
  const joinedAt = Timestamp.fromMillis(500);
  await db.doc(`households/${householdID}`).set({
    ownerID: "member-a", timeZoneIdentifier: "Asia/Tokyo",
  });
  await Promise.all(["member-a", "member-b"].map((uid) =>
    db.doc(`households/${householdID}/members/${uid}`).set({
      displayName: uid, joinedAt,
    })));
}

function preferenceInput(householdID) {
  return {
    householdID, expectedRevision: 0, clientMutationID: unique("preference"),
    medicationRemindersEnabled: true, assignmentAlertsEnabled: true,
    urgentAlertsEnabled: true, pushEnabled: true,
    backupForMemberIDs: ["member-b"], quietHoursEnabled: true,
    quietStartMinute: 1320, quietEndMinute: 420,
    summaryEnabled: false, summaryMinute: 1080,
  };
}

function canonicalPreference(householdID) {
  return {
    schemaVersion: 1, uid: "member-a", householdID,
    memberJoinedAtSnapshot: Timestamp.fromMillis(500),
    medicationRemindersEnabled: true, assignmentAlertsEnabled: true,
    urgentAlertsEnabled: true, pushEnabled: true, backupForMemberIDs: [],
    quietHoursEnabled: false, quietStartMinute: 1320, quietEndMinute: 420,
    summaryEnabled: false, summaryMinute: 1080,
    timeZoneIdentifierSnapshot: "Asia/Tokyo", revision: 1,
    createdAt: Timestamp.fromMillis(1_000), updatedAt: Timestamp.fromMillis(1_000),
  };
}

async function seedCanonicalMedicationPlan(householdID) {
  const medication = db.doc(`households/${householdID}/medications/medication-1`);
  await medication.set({
    schemaVersion: 1, id: "medication-1", petID: "legacy-primary",
    displayName: "Private medicine", purpose: null, possibleSideEffects: null,
    isActive: true, currentScheduleVersion: 1,
    currentScheduleVersionID: "v000001", revision: 0,
    createdAt: Timestamp.fromMillis(1_000), createdByID: "member-a",
    createdByName: "member-a", updatedAt: Timestamp.fromMillis(1_000),
    updatedByID: "member-a",
  });
  await medication.collection("scheduleVersions").doc("v000001").set({
    schemaVersion: 1, id: "v000001", medicationID: "medication-1", version: 1,
    petID: "legacy-primary", petName: "Mochi", medicationName: "Private medicine",
    weekdays: [2], slots: [{
      slotID: "morning", hour: 9, minute: 0,
      doseText: "Private dose", instructions: null,
    }],
    timeZoneIdentifier: "Asia/Tokyo", dstPolicy: "reject",
    effectiveFromLocalDate: "2026-08-01", effectiveUntilLocalDate: null,
    createdAt: Timestamp.fromMillis(1_000), createdByID: "member-a",
    createdByName: "member-a", closedAt: null, closedByID: null,
    replacedByVersionID: null, revision: 0,
  });
}

function canonicalMedicationOccurrence(id, overrides = {}) {
  return {
    schemaVersion: 1, id, medicationID: "medication-1",
    scheduleVersionID: "v000001", scheduleVersion: 1, slotID: "morning",
    localDate: "2026-08-17",
    dueAt: Timestamp.fromMillis(Date.parse("2026-08-17T00:00:00.000Z")),
    timeZoneIdentifier: "Asia/Tokyo", petID: "legacy-primary", petName: "Mochi",
    medicationName: "Private medicine", doseText: "Private dose", instructions: null,
    responsibilityStatus: "unclaimed", responsibleByID: null,
    responsibleByName: null, claimedAt: null, outcomeStatus: "unresolved",
    outcomeByID: null, outcomeByName: null, outcomeAt: null,
    skippedReasonCode: null, skippedReasonNote: null,
    materializedAt: Timestamp.fromMillis(1_000), revision: 0,
    ...overrides,
  };
}

function queuedDelivery({ deliveryID, intentID, householdID, installationHash }) {
  return {
    schemaVersion: 2, id: deliveryID, intentID, householdID,
    recipientID: "member-a", recipientJoinedAtSnapshot: Timestamp.fromMillis(500),
    installationHash, status: "queued", attemptCount: 0,
    nextAttemptAt: Timestamp.fromMillis(2_000), leaseID: null,
    leaseExpiresAt: null, providerRequestStartedAt: null,
    providerAcceptedAt: null, providerUnknownAt: null, terminalAt: null,
    safeErrorCode: null, createdAt: Timestamp.fromMillis(2_000),
    updatedAt: Timestamp.fromMillis(2_000),
  };
}

async function seedMaterializingManifest({
  householdID, intentID, hashes, cursor, nextRecoveryAt = 50_000,
}) {
  await db.doc(`users/member-a/notificationDeliveryManifests/${intentID}`).set({
    schemaVersion: 1, intentID, householdID, recipientID: "member-a",
    recipientJoinedAtSnapshot: Timestamp.fromMillis(500),
    selectedInstallationHashes: hashes, selectedCount: hashes.length,
    bindingKeyVersion: 1, status: "materializing", safeErrorCode: null,
    cursorInstallationHash: cursor, createdAt: Timestamp.fromMillis(2_000),
    updatedAt: Timestamp.fromMillis(2_000),
    nextRecoveryAt: Timestamp.fromMillis(nextRecoveryAt),
    completedAt: null, blockedAt: null,
  });
}

function directTask(id, revision, requestedAt, {
  requestedByID = "member-b",
  requestedToID = "member-a",
} = {}) {
  return {
    id, title: "Private care", category: "other",
    dueTime: Timestamp.fromMillis(50_000), kind: "oneOff", priority: "normal",
    routineID: null, status: "unclaimed", revision,
    assignmentMode: "direct",
    assignmentRequestID: `request-${revision}`, requestedByID,
    requestedByName: requestedByID, requestedToID,
    requestedToName: requestedToID,
    assignmentRequestedAt: Timestamp.fromMillis(requestedAt),
    assigneeID: null, assigneeName: null, claimedAt: null,
    createdByID: requestedByID, createdBy: requestedByID,
    createdAt: Timestamp.fromMillis(1_000),
    completedByID: null, completedBy: null, completedAt: null,
  };
}

function digestDocument({ householdID, digestID }) {
  return {
    schemaVersion: 1, id: digestID, householdID, recipientID: "member-a",
    recipientJoinedAtSnapshot: Timestamp.fromMillis(500), mode: "burst",
    coalescingKey: digestID, windowStartAt: Timestamp.fromMillis(1_000),
    windowEndAt: Timestamp.fromMillis(10_000),
    catchUpUntilAt: Timestamp.fromMillis(610_000), preferenceRevision: 1,
    status: "collecting", cancelReason: null, safeErrorCode: null,
    createdAt: Timestamp.fromMillis(1_000), updatedAt: Timestamp.fromMillis(1_000),
    nextFinalizeAt: Timestamp.fromMillis(5_000), readyAt: null,
    cancelledAt: null, blockedAt: null,
  };
}

function inbox({ householdID, intentID, sourceRevision = 2, expiresAt,
  nextDispatchAt = null }) {
  return {
    schemaVersion: 1, id: intentID, householdID, recipientID: "member-a",
    recipientJoinedAtSnapshot: Timestamp.fromMillis(500), category: "urgent",
    level: "urgentUnclaimed", routeReason: "urgentOptIn", sourceType: "task",
    sourceID: "task-a", sourcePath: "tasks/task-a", sourceRevision,
    preferenceRevision: null, status: "active",
    availableAt: Timestamp.fromMillis(1_000), expiresAt, nextDispatchAt,
    coalescingKey: null, cancelReason: null, cancelledAt: null,
    createdAt: Timestamp.fromMillis(1_000), updatedAt: Timestamp.fromMillis(1_000),
  };
}

async function seedToken(uid, id, householdID, token) {
  await db.doc(`users/${uid}/notificationTokens/${id}`).set({
    householdID, enabled: true, token,
    updatedAt: Timestamp.fromMillis(1_000),
  });
}

async function seedDispatchGraph({ householdID, intentID, installationHash }) {
  await db.doc(`households/${householdID}/tasks/task-a`).set(urgentTask("task-a", 2));
  await db.doc(`users/member-a/notificationInbox/${intentID}`).set(inbox({
    householdID, intentID, expiresAt: Timestamp.fromMillis(100_000),
    nextDispatchAt: Timestamp.fromMillis(2_000),
  }));
  await seedToken("member-a", installationHash, householdID, "token-1");
  const deliveryID = await import("../notifications_v2.js").then(({ deliveryIDFor }) =>
    deliveryIDFor(intentID, installationHash));
  await db.doc(`users/member-a/notificationDeliveryManifests/${intentID}`).set({
    schemaVersion: 1, intentID, householdID, recipientID: "member-a",
    recipientJoinedAtSnapshot: Timestamp.fromMillis(500),
    selectedInstallationHashes: [installationHash], selectedCount: 1,
    bindingKeyVersion: 1, status: "complete", safeErrorCode: null,
    cursorInstallationHash: null, createdAt: Timestamp.fromMillis(2_000),
    updatedAt: Timestamp.fromMillis(2_000), nextRecoveryAt: null,
    completedAt: Timestamp.fromMillis(2_000), blockedAt: null,
  });
  await db.doc(`users/member-a/notificationDeliveries/${deliveryID}`).set({
    schemaVersion: 2, id: deliveryID, intentID, householdID,
    recipientID: "member-a", recipientJoinedAtSnapshot: Timestamp.fromMillis(500),
    installationHash, status: "queued", attemptCount: 0,
    nextAttemptAt: Timestamp.fromMillis(2_000), leaseID: null,
    leaseExpiresAt: null, providerRequestStartedAt: null,
    providerAcceptedAt: null, providerUnknownAt: null, terminalAt: null,
    safeErrorCode: null, createdAt: Timestamp.fromMillis(2_000),
    updatedAt: Timestamp.fromMillis(2_000),
  });
  return deliveryID;
}

function urgentTask(id, revision) {
  return {
    id, title: "Private urgent care", category: "other",
    dueTime: Timestamp.fromMillis(50_000), kind: "oneOff", priority: "urgent",
    routineID: null, status: "unclaimed", revision,
    assignmentRequestID: null, assignmentMode: null,
    requestedByID: null, requestedByName: null,
    requestedToID: null, requestedToName: null, assignmentRequestedAt: null,
    assigneeID: null, assigneeName: null, claimedAt: null,
    createdByID: "member-a", createdBy: "member-a",
    createdAt: Timestamp.fromMillis(2_000),
    completedByID: null, completedBy: null, completedAt: null,
  };
}

async function seedDispatchPreference(householdID, intentID) {
  await db.doc(`users/member-a/notificationInbox/${intentID}`).update({
    preferenceRevision: 1,
  });
  await db.doc(
    `users/member-a/householdNotificationPreferences/${householdID}`,
  ).set(canonicalPreference(householdID));
}

async function seedCollectingDigest(prefix, semanticAt = 2_000) {
  const householdID = unique(`${prefix}-home`);
  await seedHousehold(householdID);
  await db.doc(
    `users/member-a/householdNotificationPreferences/${householdID}`,
  ).set(canonicalPreference(householdID));
  const task = db.doc(`households/${householdID}/tasks/direct-task`);
  await task.set(directTask("direct-task", 1, semanticAt));
  await generateNotificationSourceAt({
    db, householdID, sourceType: "task", sourceID: "direct-task",
    projectID: projectId, now: new Date(semanticAt + 1),
  });
  const digest = (await db.collection("users/member-a/notificationDigests")
    .where("householdID", "==", householdID).get()).docs[0];
  return { householdID, task, digest, semanticAt };
}

async function seedReadyDigestDelivery(prefix) {
  const graph = await seedCollectingDigest(prefix, Date.now());
  const installationHash = unique(prefix).replace(/[^a-f0-9]/g, "a")
    .padEnd(64, "a").slice(0, 64);
  await seedToken("member-a", installationHash, graph.householdID, "token-1");
  const ready = await finalizeNotificationDigestAt({
    db, uid: "member-a", digestID: graph.digest.id, projectID: projectId,
    bindingKeyVersion: 1,
    now: new Date(graph.digest.data().nextFinalizeAt.toMillis()),
  });
  assert.equal(ready.status, "ready");
  const deliveries = await db.collection("users/member-a/notificationDeliveries")
    .where("householdID", "==", graph.householdID).get();
  assert.equal(deliveries.size, 1);
  return {
    ...graph,
    deliveryID: deliveries.docs[0].id,
    dispatchAt: graph.digest.data().windowEndAt.toMillis() + 6_000,
  };
}

function digestSummaryID(householdID, digest) {
  return intentIDFor({
    householdID,
    sourceType: "notificationDigest",
    sourcePath: `notificationDigests/${digest.id}`,
    sourceRevision: 1,
    level: digest.data().mode === "burst" ? "burstSummary" : "dailySummary",
    recipientID: "member-a",
    recipientJoinedAtSnapshot: digest.data().recipientJoinedAtSnapshot,
  });
}
