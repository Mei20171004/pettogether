import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { after, test } from "node:test";

import { deleteApp, initializeApp as initializeClientApp } from "firebase/app";
import { connectAuthEmulator, getAuth, signInAnonymously } from "firebase/auth";
import { connectFunctionsEmulator, getFunctions, httpsCallable } from "firebase/functions";
import { deleteApp as deleteAdminApp, initializeApp as initializeAdminApp } from "firebase-admin/app";
import { Timestamp, getFirestore } from "firebase-admin/firestore";

import {
  createDailyHealthCheckInAt,
  createHealthRecordAt,
} from "../health.js";

const projectId = process.env.COPAW_TEST_PROJECT_ID ?? "demo-copaw";
const authPort = Number(process.env.COPAW_AUTH_TEST_PORT ?? "9099");
const functionsPort = Number(process.env.COPAW_FUNCTIONS_TEST_PORT ?? "5001");
const adminApp = initializeAdminApp({ projectId }, "health-tests-admin");
const adminFirestore = getFirestore(adminApp);
const clientApps = [];
let sequence = 0;

after(async () => {
  await Promise.all(clientApps.map((app) => deleteApp(app)));
  await deleteAdminApp(adminApp);
});

test("server clock derives Tokyo local dates and preserves timezone snapshots", async () => {
  const uid = unique("clock-user");
  const householdID = unique("tokyo-boundary");
  await seedHousehold({ householdID, uids: [uid], zone: "Asia/Tokyo" });

  const before = await createDailyHealthCheckInAt(
    adminFirestore,
    { auth: { uid }, data: dailyInput({
      householdID,
      mutation: unique("before-midnight"),
    }) },
    new Date("2026-08-14T14:59:59.000Z"),
  );
  const afterMidnight = await createDailyHealthCheckInAt(
    adminFirestore,
    { auth: { uid }, data: dailyInput({
      householdID,
      mutation: unique("after-midnight"),
      moodStatus: "changed",
    }) },
    new Date("2026-08-14T15:00:00.000Z"),
  );

  assert.equal(before.recordedLocalDate, "2026-08-14");
  assert.equal(afterMidnight.recordedLocalDate, "2026-08-15");
  assert.equal(before.recordID, digest("mugi|2026-08-14"));
  assert.equal(afterMidnight.recordID, digest("mugi|2026-08-15"));
  const first = await healthRecord(householdID, before.recordID).get();
  assert.equal(first.data().schemaVersion, 2);
  assert.equal(first.data().recordedTimeZoneIdentifier, "Asia/Tokyo");
  assert.equal(first.data().recordedLocalDate, "2026-08-14");
  assert.equal(first.data().waterMeasurementBasis, "localDayToDate");
  assert.equal(
    first.data().recordedAt.toMillis(),
    Date.parse("2026-08-14T14:59:59.000Z"),
  );
  assert.ok(first.data().createdAt instanceof Timestamp);

  await adminFirestore.collection("households").doc(householdID)
    .update({ timeZoneIdentifier: "UTC" });
  const unchanged = await healthRecord(householdID, before.recordID).get();
  assert.equal(unchanged.data().recordedTimeZoneIdentifier, "Asia/Tokyo");
  const authoritativeRetry = await createDailyHealthCheckInAt(
    adminFirestore,
    { auth: { uid }, data: dailyInput({
      householdID,
      mutation: unique("same-date-after-zone-change"),
    }) },
    new Date("2026-08-14T14:59:59.000Z"),
  );
  assert.equal(authoritativeRetry.existing, true);
  assert.equal(authoritativeRetry.recordedLocalDate, "2026-08-14");
  assert.equal(
    authoritativeRetry.recordedTimeZoneIdentifier,
    "Asia/Tokyo",
  );
});

test("legacy random-ID daily check-ins block a duplicate canonical day", async () => {
  const uid = unique("legacy-daily-user");
  const householdID = unique("legacy-daily-conflict");
  await seedHousehold({ householdID, uids: [uid], zone: "Asia/Tokyo" });
  await healthRecord(householdID, "legacy-random-daily").set({
    schemaVersion: 1,
    petID: "mugi",
    petName: "Mugi",
    type: "dailyCheckIn",
    recordedAt: Timestamp.fromDate(new Date("2026-08-14T14:00:00.000Z")),
    createdAt: Timestamp.fromDate(new Date("2026-08-14T14:00:01.000Z")),
  });

  await assert.rejects(
    createDailyHealthCheckInAt(
      adminFirestore,
      { auth: { uid }, data: dailyInput({
        householdID,
        mutation: unique("blocked-by-legacy"),
      }) },
      new Date("2026-08-14T14:30:00.000Z"),
    ),
    (error) => error.code === "already-exists",
  );
  assert.equal(
    (await adminFirestore.collection("households").doc(householdID)
      .collection("healthRecords").get()).size,
    1,
  );
});

test("two clients racing with different payloads create one immutable daily record", async () => {
  const first = await newClient();
  const second = await newClient();
  const householdID = unique("health-conflict");
  await seedHousehold({
    householdID,
    uids: [first.uid, second.uid],
    zone: "UTC",
  });
  const results = await Promise.allSettled([
    first.call(dailyInput({
      householdID,
      mutation: unique("first-payload"),
      waterMilliliters: 400,
      moodStatus: "usual",
    })),
    second.call(dailyInput({
      householdID,
      mutation: unique("second-payload"),
      waterMilliliters: 650,
      moodStatus: "changed",
    })),
  ]);

  assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
  const rejected = results.find((result) => result.status === "rejected");
  assert.equal(rejected.reason.code, "functions/already-exists");
  const records = await adminFirestore.collection("households").doc(householdID)
    .collection("healthRecords").get();
  assert.equal(records.size, 1);
  assert.ok([400, 650].includes(records.docs[0].data().waterMilliliters));
  assert.ok([first.uid, second.uid].includes(records.docs[0].data().createdByID));
});

test("mutation retries return the existing record and reject mutation ID reuse", async () => {
  const client = await newClient();
  const householdID = unique("health-retry");
  await seedHousehold({ householdID, uids: [client.uid], zone: "UTC" });
  const payload = dailyInput({
    householdID,
    mutation: unique("stable-mutation"),
    detail: "  Observed after breakfast  ",
  });

  const first = await client.call(payload);
  const retried = await client.call(payload);
  assert.equal(first.data.existing, false);
  assert.equal(retried.data.existing, true);
  assert.equal(retried.data.recordID, first.data.recordID);
  const sameFact = await client.call({
    ...payload,
    clientMutationID: unique("same-fact-new-mutation"),
  });
  assert.equal(sameFact.data.existing, true);
  await rejectsCode(
    client.call({ ...payload, moodStatus: "changed" }),
    "functions/invalid-argument",
  );
  const record = await healthRecord(householdID, first.data.recordID).get();
  assert.equal(record.data().detail, "Observed after breakfast");
});

test("different pets receive different deterministic records for the same date", async () => {
  const client = await newClient();
  const householdID = unique("health-multiple-pets");
  await seedHousehold({
    householdID,
    uids: [client.uid],
    zone: "UTC",
    pets: [
      { id: "mugi", name: "Mugi", isArchived: false },
      { id: "luna", name: "Luna", isArchived: false },
    ],
  });

  const [mugi, luna] = await Promise.all([
    client.call(dailyInput({
      householdID,
      petID: "mugi",
      mutation: unique("mugi-health"),
    })),
    client.call(dailyInput({
      householdID,
      petID: "luna",
      mutation: unique("luna-health"),
      appetiteLevel: "moreThanUsual",
      waterMilliliters: null,
    })),
  ]);
  assert.notEqual(mugi.data.recordID, luna.data.recordID);
  assert.equal(mugi.data.recordedLocalDate, luna.data.recordedLocalDate);
  const records = await adminFirestore.collection("households").doc(householdID)
    .collection("healthRecords").get();
  assert.equal(records.size, 2);
  const lunaRecord = records.docs.find((document) => document.data().petID === "luna");
  assert.equal(lunaRecord.data().waterMilliliters, null);
  assert.equal(lunaRecord.data().waterMeasurementBasis, null);
});

test("legacy primary pet uses the household snapshot without materializing a pet", async () => {
  const client = await newClient();
  const householdID = unique("legacy-health");
  await seedHousehold({
    householdID,
    uids: [client.uid],
    zone: "Asia/Tokyo",
    petName: "Legacy pet",
    pets: [],
  });

  const result = await client.call(dailyInput({
    householdID,
    petID: "legacy-primary",
    mutation: unique("legacy-check-in"),
  }));
  const record = await healthRecord(householdID, result.data.recordID).get();
  const pet = await adminFirestore.collection("households").doc(householdID)
    .collection("pets").doc("legacy-primary").get();
  assert.equal(record.data().petName, "Legacy pet");
  assert.equal(pet.exists, false);
});

test("authentication membership pet state timezone and payload validation are enforced", async () => {
  const unauthenticated = newUnauthenticatedClient();
  await rejectsCode(
    unauthenticated.call(dailyInput({
      householdID: unique("no-auth"),
      mutation: unique("no-auth-mutation"),
    })),
    "functions/unauthenticated",
  );

  const outsider = await newClient();
  const member = await newClient();
  const noMembershipHome = unique("no-membership");
  await seedHousehold({
    householdID: noMembershipHome,
    uids: [member.uid],
    zone: "UTC",
  });
  await rejectsCode(
    outsider.call(dailyInput({
      householdID: noMembershipHome,
      mutation: unique("outsider"),
    })),
    "functions/permission-denied",
  );

  const archivedHome = unique("archived-health");
  await seedHousehold({
    householdID: archivedHome,
    uids: [member.uid],
    zone: "UTC",
    pets: [{ id: "mugi", name: "Mugi", isArchived: true }],
  });
  await rejectsCode(
    member.call(dailyInput({
      householdID: archivedHome,
      mutation: unique("archived"),
    })),
    "functions/failed-precondition",
  );

  const invalidZoneHome = unique("invalid-zone-health");
  await seedHousehold({
    householdID: invalidZoneHome,
    uids: [member.uid],
    zone: "GMT+9",
  });
  await rejectsCode(
    member.call(dailyInput({
      householdID: invalidZoneHome,
      mutation: unique("invalid-zone"),
    })),
    "functions/failed-precondition",
  );

  const validHome = unique("invalid-payload-health");
  await seedHousehold({ householdID: validHome, uids: [member.uid], zone: "UTC" });
  for (const payload of [
    { waterMilliliters: 0 },
    { waterMilliliters: 1.5 },
    { waterMilliliters: 10001 },
    { detail: "x".repeat(501) },
    { moodStatus: "healthy" },
    { moodStatus: undefined },
    { localDate: "2026-08-14" },
  ]) {
    await rejectsCode(
      member.call({
        ...dailyInput({
          householdID: validHome,
          mutation: unique("invalid-payload"),
        }),
        ...payload,
      }),
      "functions/invalid-argument",
    );
  }
});

test("generic records derive the Tokyo date and measurement basis on the server", async () => {
  const uid = unique("generic-clock-user");
  const householdID = unique("generic-tokyo-boundary");
  await seedHousehold({ householdID, uids: [uid], zone: "Asia/Tokyo" });
  const recordedAtMilliseconds = Date.parse("2026-08-14T15:00:00.000Z");

  const result = await createHealthRecordAt(
    adminFirestore,
    { auth: { uid }, data: genericInput({
      householdID,
      mutation: unique("generic-water"),
      type: "waterIntake",
      recordedAtMilliseconds,
      detail: "  After the evening walk  ",
      waterMilliliters: 420,
    }) },
    new Date("2026-08-17T00:00:00.000Z"),
  );

  assert.match(result.recordID, /^event_[a-f0-9]{64}$/);
  assert.equal(result.recordedLocalDate, "2026-08-15");
  assert.equal(result.recordedTimeZoneIdentifier, "Asia/Tokyo");
  const record = await healthRecord(householdID, result.recordID).get();
  assert.equal(record.data().schemaVersion, 2);
  assert.equal(record.data().recordedAt.toMillis(), recordedAtMilliseconds);
  assert.equal(record.data().recordedLocalDate, "2026-08-15");
  assert.equal(record.data().recordedTimeZoneIdentifier, "Asia/Tokyo");
  assert.equal(record.data().detail, "After the evening walk");
  assert.equal(record.data().weightKilograms, null);
  assert.equal(record.data().waterMilliliters, 420);
  assert.equal(record.data().waterMeasurementBasis, "singleIntake");
  assert.equal(record.data().waterLevel, null);
  assert.equal(record.data().moodStatus, null);
  assert.equal(record.data().createdByID, uid);
  assert.ok(record.data().createdAt instanceof Timestamp);
});

test("generic mutation retries are idempotent and payload reuse is rejected", async () => {
  const client = await newClient();
  const householdID = unique("generic-retry");
  await seedHousehold({ householdID, uids: [client.uid], zone: "UTC" });
  const payload = genericInput({
    householdID,
    mutation: unique("generic-stable-mutation"),
    type: "weight",
    weightKilograms: 4.25,
    detail: "Morning weight",
  });

  const first = await client.generic(payload);
  const retried = await client.generic(payload);
  assert.equal(first.data.existing, false);
  assert.equal(retried.data.existing, true);
  assert.equal(retried.data.recordID, first.data.recordID);
  await rejectsCode(
    client.generic({ ...payload, weightKilograms: 4.5 }),
    "functions/invalid-argument",
  );
  const records = await adminFirestore.collection("households").doc(householdID)
    .collection("healthRecords").get();
  assert.equal(records.size, 1);
  assert.equal(records.docs[0].data().weightKilograms, 4.25);
});

test("generic records support the active legacy primary pet snapshot", async () => {
  const client = await newClient();
  const householdID = unique("generic-legacy-health");
  await seedHousehold({
    householdID,
    uids: [client.uid],
    zone: "Asia/Tokyo",
    petName: "Legacy pet",
    pets: [],
  });

  const result = await client.generic(genericInput({
    householdID,
    petID: "legacy-primary",
    mutation: unique("generic-legacy-note"),
    type: "note",
    detail: "Calm after dinner",
  }));
  const record = await healthRecord(householdID, result.data.recordID).get();
  const pet = await adminFirestore.collection("households").doc(householdID)
    .collection("pets").doc("legacy-primary").get();
  assert.equal(record.data().petName, "Legacy pet");
  assert.equal(record.data().type, "note");
  assert.equal(pet.exists, false);
});

test("generic records reject unsupported types shapes membership and archived pets", async () => {
  const member = await newClient();
  const outsider = await newClient();
  const householdID = unique("invalid-generic-health");
  await seedHousehold({ householdID, uids: [member.uid], zone: "UTC" });
  const base = genericInput({
    householdID,
    mutation: unique("generic-invalid-base"),
    type: "note",
    detail: "Observation",
  });
  const invalidPayloads = [
    { ...base, clientMutationID: unique("invalid-type"), type: "dailyCheckIn" },
    { ...base, clientMutationID: unique("missing-detail"), detail: null },
    { ...base, clientMutationID: unique("long-detail"), detail: "x".repeat(501) },
    { ...base, clientMutationID: unique("note-weight"), weightKilograms: 4.2 },
    genericInput({ householdID, mutation: unique("water-zero"), type: "waterIntake", waterMilliliters: 0 }),
    genericInput({ householdID, mutation: unique("water-fraction"), type: "waterIntake", waterMilliliters: 1.5 }),
    genericInput({ householdID, mutation: unique("water-high"), type: "waterIntake", waterMilliliters: 10001 }),
    genericInput({ householdID, mutation: unique("water-weight"), type: "waterIntake", waterMilliliters: 10, weightKilograms: 4.2 }),
    genericInput({ householdID, mutation: unique("weight-zero"), type: "weight", weightKilograms: 0 }),
    genericInput({ householdID, mutation: unique("weight-high"), type: "weight", weightKilograms: 501 }),
    { ...base, clientMutationID: unique("future-time"), recordedAtMilliseconds: Date.now() + 60000 },
    { ...base, clientMutationID: unique("client-date"), recordedLocalDate: "2026-08-17" },
  ];
  for (const payload of invalidPayloads) {
    await rejectsCode(member.generic(payload), "functions/invalid-argument");
  }

  await rejectsCode(
    outsider.generic({ ...base, clientMutationID: unique("generic-outsider") }),
    "functions/permission-denied",
  );
  const archivedHome = unique("generic-archived-health");
  await seedHousehold({
    householdID: archivedHome,
    uids: [member.uid],
    zone: "UTC",
    pets: [{ id: "mugi", name: "Mugi", isArchived: true }],
  });
  await rejectsCode(
    member.generic(genericInput({
      householdID: archivedHome,
      mutation: unique("generic-archived"),
      type: "note",
      detail: "Observation",
    })),
    "functions/failed-precondition",
  );
});

async function newClient() {
  const app = initializeClientApp({
    apiKey: "AIzaSyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    appId: `1:1234567890:web:health-${sequence}`,
    projectId,
  }, `health-client-${sequence++}`);
  clientApps.push(app);
  const auth = getAuth(app);
  connectAuthEmulator(auth, `http://127.0.0.1:${authPort}`, { disableWarnings: true });
  const credential = await signInAnonymously(auth);
  const functions = getFunctions(app, "asia-northeast1");
  connectFunctionsEmulator(functions, "127.0.0.1", functionsPort);
  return {
    uid: credential.user.uid,
    call: httpsCallable(functions, "createDailyHealthCheckIn"),
    generic: httpsCallable(functions, "createHealthRecord"),
  };
}

function newUnauthenticatedClient() {
  const app = initializeClientApp({
    apiKey: "AIzaSyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    appId: `1:1234567890:web:health-unauthenticated-${sequence}`,
    projectId,
  }, `health-unauthenticated-client-${sequence++}`);
  clientApps.push(app);
  const functions = getFunctions(app, "asia-northeast1");
  connectFunctionsEmulator(functions, "127.0.0.1", functionsPort);
  return { call: httpsCallable(functions, "createDailyHealthCheckIn") };
}

async function seedHousehold({
  householdID,
  uids,
  zone,
  petName = "Mugi",
  pets = [{ id: "mugi", name: "Mugi", isArchived: false }],
}) {
  const household = adminFirestore.collection("households").doc(householdID);
  await household.set({
    id: householdID,
    name: "Health test home",
    petName,
    inviteCode: "ABC234",
    timeZoneIdentifier: zone,
    ownerID: uids[0] ?? "seed-owner",
    createdAt: Timestamp.now(),
  });
  await Promise.all(uids.map((uid, index) => household.collection("members").doc(uid).set({
    id: uid,
    displayName: index === 0 ? "Owner" : "Caregiver",
    inviteCode: "ABC234",
    joinedAt: Timestamp.now(),
  })));
  await Promise.all(pets.map((pet) => household.collection("pets").doc(pet.id).set({
    id: pet.id,
    name: pet.name,
    species: "cat",
    isArchived: pet.isArchived,
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
  })));
}

function dailyInput({
  householdID,
  petID = "mugi",
  mutation,
  waterLevel = "usual",
  appetiteLevel = "usual",
  urinationLevel = "usual",
  stoolStatus = "usual",
  energyLevel = "usual",
  moodStatus = "usual",
  waterMilliliters = 500,
  detail = "Observed by caregiver",
}) {
  return {
    householdID,
    petID,
    waterLevel,
    appetiteLevel,
    urinationLevel,
    stoolStatus,
    energyLevel,
    moodStatus,
    waterMilliliters,
    detail,
    clientMutationID: mutation,
  };
}

function genericInput({
  householdID,
  petID = "mugi",
  mutation,
  type = "note",
  recordedAtMilliseconds = Date.now() - 1000,
  detail = null,
  weightKilograms = null,
  waterMilliliters = null,
}) {
  return {
    householdID,
    petID,
    type,
    recordedAtMilliseconds,
    detail,
    weightKilograms,
    waterMilliliters,
    clientMutationID: mutation,
  };
}

function healthRecord(householdID, recordID) {
  return adminFirestore.collection("households").doc(householdID)
    .collection("healthRecords").doc(recordID);
}

async function rejectsCode(promise, code) {
  await assert.rejects(promise, (error) => error?.code === code);
}

function digest(value) {
  return createHash("sha256").update(value).digest("hex");
}

function unique(prefix) {
  return `${prefix}-${Date.now()}-${sequence++}`;
}
