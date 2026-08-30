import assert from "node:assert/strict";
import { after, test } from "node:test";

import { deleteApp, initializeApp as initializeClientApp } from "firebase/app";
import { connectAuthEmulator, getAuth, signInAnonymously } from "firebase/auth";
import { connectFunctionsEmulator, getFunctions, httpsCallable } from "firebase/functions";
import { deleteApp as deleteAdminApp, initializeApp as initializeAdminApp } from "firebase-admin/app";
import { Timestamp, getFirestore } from "firebase-admin/firestore";
import { DateTime } from "luxon";

const projectId = process.env.COPAW_TEST_PROJECT_ID ?? "demo-copaw";
const authPort = Number(process.env.COPAW_AUTH_TEST_PORT ?? "9099");
const functionsPort = Number(process.env.COPAW_FUNCTIONS_TEST_PORT ?? "5001");
const adminApp = initializeAdminApp({ projectId }, "medication-tests-admin");
const adminFirestore = getFirestore(adminApp);
const clientApps = [];
let sequence = 0;

after(async () => {
  await Promise.all(clientApps.map((app) => deleteApp(app)));
  await deleteAdminApp(adminApp);
});

test("versioned multi-slot plan preserves old outcome snapshots", async () => {
  const client = await newClient();
  const householdID = unique("versioned-medication");
  const today = DateTime.now().setZone("Asia/Tokyo").startOf("day");
  const tomorrow = today.plus({ days: 1 });
  await seedHousehold({ householdID, uids: [client.uid], zone: "Asia/Tokyo" });
  const created = await client.create(planInput({
    householdID,
    day: today,
    slots: [slot(0, 0, "1 tablet"), slot(12, 0, "2 tablets")],
    mutation: unique("create"),
  }));
  assert.equal(created.data.scheduleVersionID, "v000001");

  const terminal = await client.mutate(mutationInput({
    householdID,
    medicationID: created.data.medicationID,
    localDate: today.toFormat("yyyy-MM-dd"),
    slotID: "0000",
    action: "administer",
    mutation: unique("terminal"),
  }));
  assert.equal(terminal.data.confirmed, true);

  const replaced = await client.replace({
    ...planInput({
      householdID,
      day: tomorrow,
      slots: [slot(9, 30, "3 tablets")],
      mutation: unique("replace"),
    }),
    medicationID: created.data.medicationID,
    expectedMedicationRevision: 0,
    expectedScheduleVersionID: "v000001",
  });
  assert.equal(replaced.data.scheduleVersionID, "v000002");

  const medication = adminFirestore.collection("households").doc(householdID)
    .collection("medications").doc(created.data.medicationID);
  const first = await medication.collection("scheduleVersions").doc("v000001").get();
  const second = await medication.collection("scheduleVersions").doc("v000002").get();
  const outcome = await adminFirestore.collection("households").doc(householdID)
    .collection("medicationOccurrences").doc(terminal.data.occurrenceID).get();
  const medicationSnapshot = await medication.get();
  assert.equal(first.data().effectiveUntilLocalDate, tomorrow.toFormat("yyyy-MM-dd"));
  assert.equal(first.data().revision, 1);
  assert.equal(second.data().effectiveUntilLocalDate, null);
  assert.equal(outcome.data().doseText, "1 tablet");
  assert.equal(outcome.data().outcomeStatus, "administered");
  assert.equal(outcome.data().outcomeByID, client.uid);
  assert.equal(medicationSnapshot.data().purpose, "Prescription record");
  assert.equal(medicationSnapshot.data().possibleSideEffects, "Watch appetite");
  assert.ok(outcome.data().outcomeAt instanceof Timestamp);
});

test("concurrent administer and skip have one authoritative winner", async () => {
  const first = await newClient();
  const second = await newClient();
  const householdID = unique("medication-conflict");
  const today = DateTime.now().setZone("UTC").startOf("day");
  await seedHousehold({ householdID, uids: [first.uid, second.uid], zone: "UTC" });
  const created = await first.create(planInput({
    householdID,
    day: today,
    slots: [slot(0, 0, "2 drops")],
    mutation: unique("create"),
  }));
  const base = {
    householdID,
    medicationID: created.data.medicationID,
    localDate: today.toFormat("yyyy-MM-dd"),
    slotID: "0000",
  };
  const results = await Promise.allSettled([
    first.mutate(mutationInput({ ...base, action: "administer", mutation: unique("admin") })),
    second.mutate(mutationInput({
      ...base,
      action: "skip",
      mutation: unique("skip"),
      skippedReasonCode: "petRefused",
    })),
  ]);
  assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
  const rejected = results.find((result) => result.status === "rejected");
  assert.equal(rejected.reason.code, "functions/already-exists");
  assert.ok(["administered", "skipped"].includes(rejected.reason.details.outcomeStatus));
  assert.ok(["Owner", "Caregiver"].includes(rejected.reason.details.outcomeByName));
  const outcomes = await adminFirestore.collection("households").doc(householdID)
    .collection("medicationOccurrences").get();
  assert.equal(outcomes.size, 1);
});

test("ambiguous retry is idempotent and reused mutation IDs cannot change payload", async () => {
  const client = await newClient();
  const householdID = unique("medication-retry");
  const today = DateTime.now().setZone("UTC").startOf("day");
  await seedHousehold({ householdID, uids: [client.uid], zone: "UTC" });
  const createPayload = planInput({
    householdID,
    day: today,
    slots: [slot(0, 0, "5 mg")],
    mutation: unique("same-create"),
  });
  const first = await client.create(createPayload);
  const retried = await client.create(createPayload);
  assert.deepEqual(retried.data, first.data);
  await rejectsCode(client.create({ ...createPayload, medicationName: "Changed" }),
    "functions/invalid-argument");

  const mutation = mutationInput({
    householdID,
    medicationID: first.data.medicationID,
    localDate: today.toFormat("yyyy-MM-dd"),
    slotID: "0000",
    action: "administer",
    mutation: unique("same-outcome"),
  });
  const outcome = await client.mutate(mutation);
  const outcomeRetry = await client.mutate(mutation);
  assert.deepEqual(outcomeRetry.data, outcome.data);
});

test("responsibility stays independent when another caregiver skips with a reason", async () => {
  const responsible = await newClient();
  const recorder = await newClient();
  const householdID = unique("medication-responsibility");
  const today = DateTime.now().setZone("UTC").startOf("day");
  await seedHousehold({ householdID, uids: [responsible.uid, recorder.uid], zone: "UTC" });
  const created = await responsible.create(planInput({
    householdID,
    day: today,
    slots: [slot(0, 0, "1 capsule")],
    mutation: unique("create"),
  }));
  const base = {
    householdID,
    medicationID: created.data.medicationID,
    localDate: today.toFormat("yyyy-MM-dd"),
    slotID: "0000",
  };
  await responsible.mutate(mutationInput({
    ...base,
    action: "claim",
    mutation: unique("claim"),
  }));
  await recorder.mutate(mutationInput({
    ...base,
    action: "skip",
    skippedReasonCode: "vetInstruction",
    skippedReasonNote: "Called the clinic",
    mutation: unique("skip"),
  }));

  const snapshot = await adminFirestore.collection("households").doc(householdID)
    .collection("medicationOccurrences")
    .doc(`${created.data.medicationID}_v000001_${today.toFormat("yyyy-MM-dd")}_0000`)
    .get();
  assert.equal(snapshot.data().responsibilityStatus, "claimed");
  assert.equal(snapshot.data().responsibleByID, responsible.uid);
  assert.equal(snapshot.data().outcomeStatus, "skipped");
  assert.equal(snapshot.data().outcomeByID, recorder.uid);
  assert.equal(snapshot.data().skippedReasonCode, "vetInstruction");
  assert.equal(snapshot.data().skippedReasonNote, "Called the clinic");
});

test("legacy household materializes its synthetic primary pet when medication starts", async () => {
  const client = await newClient();
  const householdID = unique("legacy-medication");
  const today = DateTime.now().setZone("Asia/Tokyo").startOf("day");
  await seedHousehold({
    householdID,
    uids: [client.uid],
    zone: "Asia/Tokyo",
    seedPet: false,
  });

  const created = await client.create({
    ...planInput({
      householdID,
      day: today,
      slots: [slot(0, 0, "1 tablet")],
      mutation: unique("legacy-create"),
    }),
    petID: "legacy-primary",
  });

  const pet = await adminFirestore.collection("households").doc(householdID)
    .collection("pets").doc("legacy-primary").get();
  const version = await adminFirestore.collection("households").doc(householdID)
    .collection("medications").doc(created.data.medicationID)
    .collection("scheduleVersions").doc("v000001").get();
  assert.equal(pet.data().name, "Mugi");
  assert.equal(pet.data().isArchived, false);
  assert.equal(version.data().petID, "legacy-primary");
  assert.equal(version.data().petName, "Mugi");
});

test("validation rejects future outcomes, stale edits, archive, injection, and DST", async () => {
  const client = await newClient();
  const other = await newClient();
  const householdID = unique("medication-validation");
  const today = DateTime.now().setZone("UTC").startOf("day");
  const tomorrow = today.plus({ days: 1 });
  await seedHousehold({ householdID, uids: [client.uid], zone: "UTC" });
  const created = await client.create(planInput({
    householdID,
    day: today,
    slots: [slot(0, 0, "5 mg")],
    mutation: unique("create"),
  }));
  await rejectsCode(client.mutate(mutationInput({
    householdID,
    medicationID: created.data.medicationID,
    localDate: tomorrow.toFormat("yyyy-MM-dd"),
    slotID: "0000",
    action: "administer",
    mutation: unique("future"),
  })), "functions/failed-precondition");
  await rejectsCode(client.replace({
    ...planInput({ householdID, day: tomorrow, slots: [slot(8, 0, "10 mg")], mutation: unique("edit") }),
    medicationID: created.data.medicationID,
    expectedMedicationRevision: 99,
    expectedScheduleVersionID: "v000001",
  }), "functions/aborted");
  await rejectsCode(client.create({
    ...planInput({ householdID, day: today, slots: [slot(8, 0, "1 ml")], mutation: unique("inject") }),
    outcomeByID: client.uid,
  }), "functions/invalid-argument");

  await adminFirestore.collection("households").doc(householdID)
    .collection("pets").doc("mugi").update({ isArchived: true });
  await rejectsCode(client.create(planInput({
    householdID,
    day: tomorrow,
    slots: [slot(8, 0, "1 ml")],
    mutation: unique("archive"),
  })), "functions/failed-precondition");

  const dstHousehold = unique("dst-home");
  await seedHousehold({ householdID: dstHousehold, uids: [other.uid], zone: "America/New_York" });
  await rejectsCode(other.create(planInput({
    householdID: dstHousehold,
    day: DateTime.fromISO("2027-03-14", { zone: "America/New_York" }),
    slots: [slot(2, 30, "1 dose")],
    mutation: unique("dst"),
  })), "functions/failed-precondition");
  // LT7-AC08: dstPolicy rejects ambiguous fall-back wall time as well, so the
  // repeated local hour can never silently choose one of its two instants.
  await rejectsCode(other.create(planInput({
    householdID: dstHousehold,
    day: DateTime.fromISO("2027-11-07", { zone: "America/New_York" }),
    slots: [slot(1, 30, "1 dose")],
    mutation: unique("dst-fold"),
  })), "functions/failed-precondition");
});

test("pet archive is callable-only and blocks active medication plans", async () => {
  const client = await newClient();
  const clearHousehold = unique("archive-clear");
  await seedHousehold({ householdID: clearHousehold, uids: [client.uid], zone: "UTC" });
  const mutation = unique("archive-pet");
  const archived = await client.archive({
    householdID: clearHousehold,
    petID: "mugi",
    clientMutationID: mutation,
  });
  assert.equal(archived.data.archived, true);
  const retried = await client.archive({
    householdID: clearHousehold,
    petID: "mugi",
    clientMutationID: mutation,
  });
  assert.deepEqual(retried.data, archived.data);

  const activeHousehold = unique("archive-active");
  const today = DateTime.now().setZone("UTC").startOf("day");
  await seedHousehold({ householdID: activeHousehold, uids: [client.uid], zone: "UTC" });
  const activePlan = await client.create(planInput({
    householdID: activeHousehold,
    day: today,
    slots: [slot(0, 0, "1 tablet")],
    mutation: unique("active-plan"),
  }));
  await rejectsCode(client.archive({
    householdID: activeHousehold,
    petID: "mugi",
    clientMutationID: unique("blocked-archive"),
  }), "functions/failed-precondition");
  const stopped = await client.stop({
    householdID: activeHousehold,
    medicationID: activePlan.data.medicationID,
    expectedMedicationRevision: 0,
    effectiveUntilLocalDate: today.plus({ days: 1 }).toFormat("yyyy-MM-dd"),
    clientMutationID: unique("stop-plan"),
  });
  assert.equal(stopped.data.stopped, true);
  await client.archive({
    householdID: activeHousehold,
    petID: "mugi",
    clientMutationID: unique("archive-after-stop"),
  });
});

async function newClient() {
  const app = initializeClientApp({
    apiKey: "AIzaSyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    appId: `1:1234567890:web:medication-${sequence}`,
    projectId,
  }, `medication-client-${sequence++}`);
  clientApps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, `http://127.0.0.1:${authPort}`, { disableWarnings: true });
  const credential = await signInAnonymously(auth);
  const functions = getFunctions(app, "asia-northeast1");
  connectFunctionsEmulator(functions, "127.0.0.1", functionsPort);
  return {
    uid: credential.user.uid,
    create: httpsCallable(functions, "createMedicationPlan"),
    replace: httpsCallable(functions, "replaceMedicationPlan"),
    stop: httpsCallable(functions, "stopMedicationPlan"),
    mutate: httpsCallable(functions, "mutateMedicationOccurrence"),
    archive: httpsCallable(functions, "archivePet"),
  };
}

async function seedHousehold({ householdID, uids, zone, seedPet = true }) {
  const household = adminFirestore.collection("households").doc(householdID);
  await household.set({
    id: householdID,
    name: "Medication test home",
    petName: "Mugi",
    inviteCode: "ABC234",
    timeZoneIdentifier: zone,
    ownerID: uids[0],
    createdAt: Timestamp.now(),
  });
  for (const [index, uid] of uids.entries()) {
    await household.collection("members").doc(uid).set({
      id: uid,
      displayName: index === 0 ? "Owner" : "Caregiver",
      inviteCode: "ABC234",
      joinedAt: Timestamp.now(),
    });
  }
  if (seedPet) {
    await household.collection("pets").doc("mugi").set({
      id: "mugi",
      name: "Mugi",
      species: "cat",
      isArchived: false,
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    });
  }
}

function planInput({ householdID, day, slots, mutation }) {
  return {
    householdID,
    petID: "mugi",
    medicationName: "Tablet A",
    purpose: "Prescription record",
    possibleSideEffects: "Watch appetite",
    effectiveFromLocalDate: day.toFormat("yyyy-MM-dd"),
    weekdays: [appleWeekday(day)],
    slots,
    clientMutationID: mutation,
  };
}

function mutationInput({ householdID, medicationID, localDate, slotID, action, mutation,
  skippedReasonCode, skippedReasonNote }) {
  return {
    householdID,
    medicationID,
    scheduleVersionID: "v000001",
    localDate,
    slotID,
    action,
    skippedReasonCode: skippedReasonCode ?? null,
    skippedReasonNote: skippedReasonNote ?? null,
    clientMutationID: mutation,
  };
}

function slot(hour, minute, doseText) {
  return {
    slotID: `${String(hour).padStart(2, "0")}${String(minute).padStart(2, "0")}`,
    hour,
    minute,
    doseText,
    instructions: null,
  };
}

function appleWeekday(day) {
  return day.weekday % 7 + 1;
}

async function rejectsCode(promise, code) {
  await assert.rejects(promise, (error) => error?.code === code);
}

function unique(prefix) {
  return `${prefix}-${Date.now()}-${sequence++}`;
}
