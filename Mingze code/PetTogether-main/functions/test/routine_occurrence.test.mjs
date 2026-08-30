import assert from "node:assert/strict";
import { after, test } from "node:test";

import { deleteApp, initializeApp as initializeClientApp } from "firebase/app";
import {
  connectAuthEmulator,
  getAuth,
  signInAnonymously,
} from "firebase/auth";
import {
  connectFunctionsEmulator,
  getFunctions,
  httpsCallable,
} from "firebase/functions";
import { deleteApp as deleteAdminApp, initializeApp as initializeAdminApp } from "firebase-admin/app";
import { Timestamp, getFirestore } from "firebase-admin/firestore";

const projectId = process.env.COPAW_TEST_PROJECT_ID ?? "demo-copaw";
const authPort = Number(process.env.COPAW_AUTH_TEST_PORT ?? "9099");
const functionsPort = Number(process.env.COPAW_FUNCTIONS_TEST_PORT ?? "5001");
const adminApp = initializeAdminApp({ projectId }, "routine-tests-admin");
const adminFirestore = getFirestore(adminApp);
const clientApps = [];
let sequence = 0;

after(async () => {
  await Promise.all(clientApps.map((app) => deleteApp(app)));
  await deleteAdminApp(adminApp);
});

test("server derives the canonical local date, ID, and due time", async () => {
  const client = await newClient();
  const householdID = unique("tokyo-home");
  await seedRoutine({
    householdID,
    uid: client.uid,
    localZone: "Asia/Tokyo",
    routineID: "morning-meal",
    weekdays: [6],
    hour: 8,
    minute: 30,
    startDate: new Date("2026-08-01T00:00:00Z"),
  });

  const result = await client.call({
    householdID,
    routineID: "morning-meal",
    localDate: "2026-08-14",
    action: "claim",
  });

  assert.equal(result.data.taskID, "morning-meal_2026-08-14");
  const task = await adminFirestore
    .collection("households")
    .doc(householdID)
    .collection("tasks")
    .doc(result.data.taskID)
    .get();
  assert.equal(task.data().status, "claimed");
  assert.equal(task.data().assigneeID, client.uid);
  assert.equal(task.data().revision, 1);
  assert.equal(task.data().dueTime.toDate().toISOString(), "2026-08-13T23:30:00.000Z");
  assert.ok(task.data().claimedAt instanceof Timestamp);
  assert.equal(task.data().lastCollaborationAction, "taskClaimed");
  assert.equal(task.data().lastCollaborationActorID, client.uid);
  assert.equal(task.data().lastCollaborationRequestID, null);
  assert.ok(task.data().lastCollaborationAt instanceof Timestamp);
});

test("server rejects unscheduled, pre-start, impossible, and DST-gap dates", async () => {
  const client = await newClient();
  const selectedHome = unique("selected-home");
  await seedRoutine({
    householdID: selectedHome,
    uid: client.uid,
    localZone: "Asia/Tokyo",
    routineID: "selected-walk",
    weekdays: [6],
    hour: 8,
    minute: 0,
    startDate: new Date("2026-08-10T00:00:00Z"),
  });

  await rejectsCode(
    client.call({
      householdID: selectedHome,
      routineID: "selected-walk",
      localDate: "2026-08-15",
      action: "claim",
    }),
    "functions/failed-precondition",
  );
  await rejectsCode(
    client.call({
      householdID: selectedHome,
      routineID: "selected-walk",
      localDate: "2026-08-07",
      action: "claim",
    }),
    "functions/failed-precondition",
  );
  await rejectsCode(
    client.call({
      householdID: selectedHome,
      routineID: "selected-walk",
      localDate: "2026-02-30",
      action: "claim",
    }),
    "functions/invalid-argument",
  );

  const dstHome = unique("dst-home");
  await seedRoutine({
    householdID: dstHome,
    uid: client.uid,
    localZone: "America/New_York",
    routineID: "dst-dose",
    weekdays: [1, 2, 3, 4, 5, 6, 7],
    frequency: "daily",
    hour: 2,
    minute: 30,
    startDate: new Date("2026-01-01T00:00:00Z"),
  });
  await rejectsCode(
    client.call({
      householdID: dstHome,
      routineID: "dst-dose",
      localDate: "2026-03-08",
      action: "claim",
    }),
    "functions/failed-precondition",
  );

  // LT7-AC08: routines only reject nonexistent wall time. Unlike medication's
  // dstPolicy=reject, an ambiguous fall-back hour is accepted and resolves to
  // its first occurrence. This locks that difference in place so it cannot
  // change silently; aligning the two policies is a product decision.
  const foldHome = unique("dst-fold-home");
  await seedRoutine({
    householdID: foldHome,
    uid: client.uid,
    localZone: "America/New_York",
    routineID: "fold-dose",
    weekdays: [1, 2, 3, 4, 5, 6, 7],
    frequency: "daily",
    hour: 1,
    minute: 30,
    startDate: new Date("2026-01-01T00:00:00Z"),
  });
  const fold = await client.call({
    householdID: foldHome,
    routineID: "fold-dose",
    localDate: "2026-11-01",
    action: "claim",
  });
  assert.equal(fold.data.taskID, "fold-dose_2026-11-01");
});

test("two authenticated clients cannot materialize the same occurrence twice", async () => {
  const first = await newClient();
  const second = await newClient();
  const householdID = unique("conflict-home");
  await seedRoutine({
    householdID,
    uid: first.uid,
    additionalUIDs: [second.uid],
    localZone: "UTC",
    routineID: "daily-care",
    weekdays: [1, 2, 3, 4, 5, 6, 7],
    frequency: "daily",
    hour: 9,
    minute: 0,
    startDate: new Date("2026-01-01T00:00:00Z"),
  });
  const payload = {
    householdID,
    routineID: "daily-care",
    localDate: "2026-08-14",
    action: "claim",
  };

  const results = await Promise.allSettled([first.call(payload), second.call(payload)]);
  assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
  const rejected = results.find((result) => result.status === "rejected");
  assert.equal(rejected.reason.code, "functions/already-exists");
  const task = await adminFirestore
    .collection("households")
    .doc(householdID)
    .collection("tasks")
    .doc("daily-care_2026-08-14")
    .get();
  assert.equal(task.data().revision, 1);
  assert.ok([first.uid, second.uid].includes(task.data().assigneeID));
});

test("server binds the current active pet snapshot and rejects archived pets", async () => {
  const client = await newClient();
  const activeHome = unique("active-pet-home");
  await seedRoutine({
    householdID: activeHome,
    uid: client.uid,
    localZone: "UTC",
    routineID: "mugi-care",
    weekdays: [1, 2, 3, 4, 5, 6, 7],
    frequency: "daily",
    hour: 9,
    minute: 0,
    startDate: new Date("2026-01-01T00:00:00Z"),
    pet: { id: "mugi", name: "Mugi", isArchived: false },
  });
  const result = await client.call({
    householdID: activeHome,
    routineID: "mugi-care",
    localDate: "2026-08-14",
    action: "claim",
  });
  const activeTask = await adminFirestore
    .collection("households")
    .doc(activeHome)
    .collection("tasks")
    .doc(result.data.taskID)
    .get();
  assert.equal(activeTask.data().petID, "mugi");
  assert.equal(activeTask.data().petName, "Mugi");

  const renamedHome = unique("renamed-pet-home");
  await seedRoutine({
    householdID: renamedHome,
    uid: client.uid,
    localZone: "UTC",
    routineID: "renamed-pet-care",
    weekdays: [1, 2, 3, 4, 5, 6, 7],
    frequency: "daily",
    hour: 9,
    minute: 0,
    startDate: new Date("2026-01-01T00:00:00Z"),
    pet: {
      id: "renamed-pet",
      name: "Current name",
      isArchived: false,
      routineName: "Old name",
    },
  });
  const renamedResult = await client.call({
    householdID: renamedHome,
    routineID: "renamed-pet-care",
    localDate: "2026-08-14",
    action: "claim",
  });
  const renamedTask = await adminFirestore
    .collection("households")
    .doc(renamedHome)
    .collection("tasks")
    .doc(renamedResult.data.taskID)
    .get();
  assert.equal(renamedTask.data().petName, "Current name");

  const archivedHome = unique("archived-pet-home");
  await seedRoutine({
    householdID: archivedHome,
    uid: client.uid,
    localZone: "UTC",
    routineID: "archived-pet-care",
    weekdays: [1, 2, 3, 4, 5, 6, 7],
    frequency: "daily",
    hour: 9,
    minute: 0,
    startDate: new Date("2026-01-01T00:00:00Z"),
    pet: { id: "old-pet", name: "Old pet", isArchived: true },
  });
  await rejectsCode(
    client.call({
      householdID: archivedHome,
      routineID: "archived-pet-care",
      localDate: "2026-08-14",
      action: "claim",
    }),
    "functions/failed-precondition",
  );

  const legacyArchivedHome = unique("legacy-archived-pet-home");
  await seedRoutine({
    householdID: legacyArchivedHome,
    uid: client.uid,
    localZone: "UTC",
    routineID: "legacy-archived-care",
    weekdays: [1, 2, 3, 4, 5, 6, 7],
    frequency: "daily",
    hour: 9,
    minute: 0,
    startDate: new Date("2026-01-01T00:00:00Z"),
    pet: { id: "legacy-primary", name: "Old pet", isArchived: true },
    includePetOnRoutine: false,
  });
  await rejectsCode(
    client.call({
      householdID: legacyArchivedHome,
      routineID: "legacy-archived-care",
      localDate: "2026-08-14",
      action: "claim",
    }),
    "functions/failed-precondition",
  );
});

async function newClient() {
  const app = initializeClientApp(
    {
      apiKey: "demo-api-key",
      appId: `1:1234567890:web:${sequence}`,
      projectId,
    },
    `routine-client-${sequence++}`,
  );
  clientApps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, `http://127.0.0.1:${authPort}`, { disableWarnings: true });
  const credential = await signInAnonymously(auth);
  const functions = getFunctions(app, "asia-northeast1");
  connectFunctionsEmulator(functions, "127.0.0.1", functionsPort);
  return {
    uid: credential.user.uid,
    call: httpsCallable(functions, "mutateRoutineOccurrence"),
  };
}

async function seedRoutine({
  householdID,
  uid,
  additionalUIDs = [],
  localZone,
  routineID,
  weekdays,
  frequency = "selectedDays",
  hour,
  minute,
  startDate,
  pet,
  includePetOnRoutine = true,
}) {
  const household = adminFirestore.collection("households").doc(householdID);
  await household.set({
    id: householdID,
    name: "Function test home",
    petName: "Mochi",
    inviteCode: "ABC234",
    timeZoneIdentifier: localZone,
    ownerID: uid,
    createdAt: Timestamp.now(),
  });
  for (const memberID of [uid, ...additionalUIDs]) {
    await household.collection("members").doc(memberID).set({
      id: memberID,
      displayName: memberID === uid ? "Owner" : "Caregiver",
      inviteCode: "ABC234",
      joinedAt: Timestamp.now(),
    });
  }
  if (pet != null) {
    await household.collection("pets").doc(pet.id).set({
      id: pet.id,
      name: pet.name,
      species: null,
      isArchived: pet.isArchived,
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    });
  }
  await household.collection("routines").doc(routineID).set({
    id: routineID,
    title: "Scheduled care",
    category: "feeding",
    priority: "normal",
    frequency,
    weekdays,
    hour,
    minute,
    startDate: Timestamp.fromDate(startDate),
    timeZoneIdentifier: localZone,
    createdByID: uid,
    createdByName: "Owner",
    ...(pet == null || !includePetOnRoutine
      ? {}
      : { petID: pet.id, petName: pet.routineName ?? pet.name }),
    isActive: true,
    createdAt: Timestamp.now(),
  });
}

async function rejectsCode(promise, code) {
  await assert.rejects(promise, (error) => error?.code === code);
}

function unique(prefix) {
  return `${prefix}-${Date.now()}-${sequence++}`;
}
