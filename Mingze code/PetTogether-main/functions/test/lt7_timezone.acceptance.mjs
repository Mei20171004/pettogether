import assert from "node:assert/strict";
import { after, test } from "node:test";

import { deleteApp, initializeApp } from "firebase-admin/app";
import { Timestamp, getFirestore } from "firebase-admin/firestore";

import {
  finalizeNotificationDigestAt,
  generateNotificationSourceAt,
  setHouseholdNotificationPreferencesAt,
} from "../notifications_v2.js";

// Run separately from the main suite: this file drives the shared systemConfig
// generation gate, which the other notification suites also own, so mixing them
// in one process makes both sets order-dependent.
//   npm run lt7:timezone
//
// LT7-AC08 freezes how household-local wall time behaves across the Tokyo day
// boundary and both New York DST discontinuities. The dispatch availability and
// summary windows are derived from local wall clock values, so a library or
// runtime change that silently moved a quiet-hours boundary would otherwise
// shift real reminder times without failing any test.

const projectId = process.env.COPAW_TEST_PROJECT_ID ?? "demo-copaw";
const app = initializeApp({ projectId }, "lt7-timezone-tests-admin");
const db = getFirestore(app);
let sequence = 0;

after(async () => {
  // systemConfig gates are global documents shared with the other suites, so
  // this file must not leave its enabled generation gate behind.
  await Promise.all([
    db.doc("systemConfig/notificationIntentGenerationV2").delete(),
    db.doc("systemConfig/notificationDispatchV2").delete(),
  ]);
  await deleteApp(app);
});

test("LT7-AC08 New York spring gap resolves to the first valid instant", async () => {
  // 2026-03-08: local 02:00 through 02:59 does not exist in America/New_York.
  const availableAt = await summaryAvailabilityAt({
    zone: "America/New_York",
    quietStartMinute: 1260,
    quietEndMinute: 150,
    now: new Date("2026-03-08T06:00:00.000Z"),
  });
  assert.equal(availableAt.toISOString(), "2026-03-08T07:30:00.000Z");
});

test("LT7-AC08 New York autumn fold resolves to the first occurrence", async () => {
  // 2026-11-01: local 01:00 through 01:59 happens twice in America/New_York.
  const availableAt = await summaryAvailabilityAt({
    zone: "America/New_York",
    quietStartMinute: 1260,
    quietEndMinute: 90,
    now: new Date("2026-11-01T04:30:00.000Z"),
  });
  assert.equal(availableAt.toISOString(), "2026-11-01T05:30:00.000Z");
});

test("LT7-AC08 Tokyo quiet hours cross midnight on the household day", async () => {
  const availableAt = await summaryAvailabilityAt({
    zone: "Asia/Tokyo",
    quietStartMinute: 1380,
    quietEndMinute: 420,
    now: new Date("2026-08-17T15:00:00.000Z"),
  });
  assert.equal(availableAt.toISOString(), "2026-08-17T22:00:00.000Z");
});

test("LT7-AC08 a malformed household timezone fails closed without repair", async () => {
  const householdID = unique("tz-broken-home");
  const household = db.doc(`households/${householdID}`);
  await household.set({ ownerID: "lt7tz-member-a", timeZoneIdentifier: "Not/AZone" });
  await db.doc(`households/${householdID}/members/lt7tz-member-a`).set({
    displayName: "lt7tz-member-a", joinedAt: Timestamp.fromMillis(500),
  });
  const before = (await household.get()).data();
  await assert.rejects(
    setHouseholdNotificationPreferencesAt(
      db,
      { auth: { uid: "lt7tz-member-a" }, data: preferenceInput(householdID) },
      new Date("2026-08-17T00:00:00.000Z"),
    ),
    /timezone/i,
  );
  const after = (await household.get()).data();
  assert.deepEqual(after, before, "an invalid zone must not be repaired in place");
  const preferences = await db.collection(
    `users/lt7tz-member-a/householdNotificationPreferences`,
  ).where("householdID", "==", householdID).get();
  assert.equal(preferences.empty, true, "no inferred preference may be written");
});

async function summaryAvailabilityAt({
  zone,
  quietStartMinute,
  quietEndMinute,
  now,
}) {
  const householdID = unique("tz-home");
  await seedHousehold(householdID, zone);
  await db.doc(
    `users/lt7tz-member-a/householdNotificationPreferences/${householdID}`,
  ).set({
    schemaVersion: 1, uid: "lt7tz-member-a", householdID,
    memberJoinedAtSnapshot: Timestamp.fromMillis(500),
    medicationRemindersEnabled: true, assignmentAlertsEnabled: true,
    urgentAlertsEnabled: true, pushEnabled: true, backupForMemberIDs: [],
    quietHoursEnabled: true, quietStartMinute, quietEndMinute,
    summaryEnabled: false, summaryMinute: 1080,
    timeZoneIdentifierSnapshot: zone, revision: 1,
    createdAt: Timestamp.fromMillis(1_000), updatedAt: Timestamp.fromMillis(1_000),
  });
  const taskID = unique("tz-task");
  await db.doc(`households/${householdID}/tasks/${taskID}`).set(
    directTask(taskID, 1, now.getTime()),
  );
  const generation = await generateNotificationSourceAt({
    db, householdID, sourceType: "task", sourceID: taskID,
    projectID: projectId, now,
  });
  assert.equal(generation.created, 1);
  const digests = await db.collection("users/lt7tz-member-a/notificationDigests")
    .where("householdID", "==", householdID).get();
  assert.equal(digests.size, 1);
  const digest = digests.docs[0];
  const finalized = await finalizeNotificationDigestAt({
    db, uid: "lt7tz-member-a", digestID: digest.id, projectID: projectId,
    now: new Date(digest.data().nextFinalizeAt.toMillis()),
  });
  assert.equal(finalized.status, "ready");
  const summary = await db.collection("users/lt7tz-member-a/notificationInbox")
    .where("householdID", "==", householdID)
    .where("sourceType", "==", "notificationDigest").get();
  assert.equal(summary.size, 1);
  return summary.docs[0].data().availableAt.toDate();
}

async function seedHousehold(householdID, zone) {
  await db.doc(`households/${householdID}`).set({
    ownerID: "lt7tz-member-a", timeZoneIdentifier: zone,
  });
  await Promise.all(["lt7tz-member-a", "lt7tz-member-b"].map((uid) =>
    db.doc(`households/${householdID}/members/${uid}`).set({
      displayName: uid, joinedAt: Timestamp.fromMillis(500),
    })));
  await db.doc("systemConfig/notificationIntentGenerationV2").set({
    schemaVersion: 1, enabled: true, projectID: projectId,
    cutoverAt: Timestamp.fromMillis(1_000), updatedBy: "lt7-timezone-test",
    updatedAt: Timestamp.fromMillis(1_000),
  });
  await db.doc("systemConfig/notificationDispatchV2").delete();
}

function preferenceInput(householdID) {
  return {
    householdID, expectedRevision: 0, clientMutationID: unique("preference"),
    medicationRemindersEnabled: true, assignmentAlertsEnabled: true,
    urgentAlertsEnabled: true, pushEnabled: true, backupForMemberIDs: [],
    quietHoursEnabled: false, quietStartMinute: 1320, quietEndMinute: 420,
    summaryEnabled: false, summaryMinute: 1080,
  };
}

function directTask(id, revision, requestedAt) {
  return {
    id, title: "Private care", category: "other",
    dueTime: Timestamp.fromMillis(requestedAt + 3_600_000), kind: "oneOff",
    priority: "normal", routineID: null, status: "unclaimed", revision,
    assignmentMode: "direct", assignmentRequestID: `request-${revision}`,
    requestedByID: "lt7tz-member-b", requestedByName: "lt7tz-member-b",
    requestedToID: "lt7tz-member-a", requestedToName: "lt7tz-member-a",
    assignmentRequestedAt: Timestamp.fromMillis(requestedAt),
    assigneeID: null, assigneeName: null, claimedAt: null,
    createdByID: "lt7tz-member-b", createdBy: "lt7tz-member-b",
    createdAt: Timestamp.fromMillis(1_000),
    completedByID: null, completedBy: null, completedAt: null,
  };
}

function unique(prefix) {
  sequence += 1;
  return `${prefix}-${process.pid}-${sequence}`;
}
