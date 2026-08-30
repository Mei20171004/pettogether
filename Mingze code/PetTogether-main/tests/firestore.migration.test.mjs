import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";

import {
  classifyFixture,
  loadFixtureFromEmulator,
  isMigrationScopePath,
  receiptFor,
  validateDryRunRequest,
} from "../scripts/firestore_migration_dry_run.mjs";

const fixture = JSON.parse(await readFile(
  new URL("./fixtures/firestore-migration-synthetic.json", import.meta.url),
  "utf8",
));

test("synthetic migration fixture closes every document into one class", () => {
  const classified = classifyFixture(fixture);
  assert.equal(classified.length, fixture.documents.length);
  assert.deepEqual(
    Object.fromEntries(classified.map((item) => [item.path, item.classification])),
    {
      "households/home-a": "safe-additive",
      "households/home-b": "manual/blocking",
      "households/home-a/tasks/canonical-task": "canonical/no-op",
      "households/home-a/tasks/legacy-task": "manual/blocking",
      "households/home-a/tasks/partial-request": "manual/blocking",
      "households/home-a/tasks/malformed-task": "malformed/quarantine",
      "inviteCodes/ABC234": "canonical/no-op",
      "households/home-a/healthRecords/legacy-health": "canonical/no-op",
      "households/home-a/healthRecords/legacy-daily": "manual/blocking",
      "households/home-a/healthRecords/legacy-fractional-water":
        "manual/blocking",
      "households/home-a/healthRecords/malformed-v1": "malformed/quarantine",
      "households/home-a/healthRecords/malformed-v2-weight":
        "malformed/quarantine",
      "households/home-a/healthRecords/mismatched-v2-date":
        "malformed/quarantine",
      "households/home-a/healthRecords/canonical-v2-note": "canonical/no-op",
      "households/home-a/healthRecords/missing-v2-null-keys":
        "malformed/quarantine",
      "households/home-a/healthRecords/unexpected-v2-key":
        "malformed/quarantine",
    },
  );
});

test("receipt is deterministic and contains no raw source path or content", () => {
  const receipt = receiptFor(fixture, "local-synthetic-key");
  assert.equal(receipt.sourceDocumentCount, receipt.classifiedDocumentCount);
  const serialized = JSON.stringify(receipt);
  assert.equal(serialized.includes("Synthetic pet"), false);
  assert.equal(serialized.includes("households/home-a"), false);
  assert.deepEqual(
    receiptFor(fixture, "local-synthetic-key"),
    receipt,
  );
});

test("LT7-AC05 two dry-runs reconcile to identical zero-write receipts", () => {
  const first = receiptFor(fixture, "local-synthetic-key");
  const second = receiptFor(fixture, "local-synthetic-key");
  assert.deepEqual(second, first);
  assert.equal(first.plannedWrites, 0);
  assert.equal(first.appliedWrites, 0);
  assert.equal(first.beforeFingerprint, first.afterFingerprint);
  assert.equal(first.excludedByScope.documentCount, fixture.excludedByScopeDocuments.length);
  assert.equal(first.sourceDocumentCount, fixture.documents.length);
  assert.equal(first.classifiedDocumentCount, fixture.documents.length);
  const serialized = JSON.stringify(first);
  assert.equal(serialized.includes("collaborationEvents"), false);
  assert.equal(serialized.includes("notificationInbox"), false);
});

test("LT7-AC05 rejects apply, remote, non-demo, missing-host, and non-loopback", () => {
  const valid = {
    mode: "dry-run",
    environment: "emulator",
    projectID: "demo-copaw",
    firestoreHost: "127.0.0.1:8280",
  };
  assert.doesNotThrow(() => validateDryRunRequest(valid));
  assert.throws(() => validateDryRunRequest({ ...valid, mode: "apply" }), /dry-run/);
  assert.throws(
    () => validateDryRunRequest({ ...valid, environment: "staging" }),
    /emulator/,
  );
  assert.throws(
    () => validateDryRunRequest({ ...valid, projectID: "copaw-prod" }),
    /demo-copaw/,
  );
  assert.throws(
    () => validateDryRunRequest({ ...valid, firestoreHost: "" }),
    /FIRESTORE_EMULATOR_HOST/,
  );
  assert.throws(
    () => validateDryRunRequest({ ...valid, firestoreHost: "firebase.example:8080" }),
    /loopback/,
  );
});

test("LT7-AC05 inventory reads are emulator-only and content changes fail reconciliation", async () => {
  const requested = [];
  const emulatorFixture = await loadFixtureFromEmulator({
    environment: "emulator",
    projectID: "demo-copaw",
    documents: [{ path: "households/home-a", data: {} }],
    excludedByScopeDocuments: [{
      path: "users/member-a/notificationInbox/intent-a",
      data: {},
    }],
  }, "127.0.0.1:8280", async (url) => {
    requested.push(url);
    return {
      ok: true,
      async json() {
        return {
          fields: {
            name: { stringValue: "Synthetic home" },
            revision: { integerValue: "2" },
            active: { booleanValue: true },
            updatedAt: { timestampValue: "2026-08-17T00:00:00.000Z" },
          },
        };
      },
    };
  });
  assert.equal(requested.length, 2);
  assert.equal(requested.every((url) => url.startsWith(
    "http://127.0.0.1:8280/v1/projects/demo-copaw/",
  )), true);
  assert.deepEqual(emulatorFixture.documents[0].data, {
    name: "Synthetic home",
    revision: 2,
    active: true,
    updatedAt: "2026-08-17T00:00:00.000Z",
  });

  const after = structuredClone(fixture);
  after.documents[0].data.name = "Changed synthetic home";
  assert.throws(
    () => receiptFor(fixture, "local-synthetic-key", after),
    /changed during the read-only dry-run/,
  );
});

test("LT7-AC05 denominator cannot mix migration and excluded canonical paths", () => {
  assert.equal(isMigrationScopePath("households/home-a/tasks/task-a"), true);
  assert.equal(
    isMigrationScopePath("households/home-a/collaborationEvents/event-a"),
    false,
  );
  assert.throws(() => classifyFixture({
    documents: [{
      path: "users/member-a/notificationInbox/intent-a",
      data: {},
    }],
  }), /out-of-scope path/);
  assert.throws(() => receiptFor({
    environment: "emulator",
    projectID: "demo-copaw",
    documents: [],
    excludedByScopeDocuments: [{
      path: "households/home-a/tasks/task-a",
      data: {},
    }],
  }, "local-synthetic-key"), /migration-source path/);
});

test("health inventory rejects IDs and timestamp relations the reader drops", () => {
  const canonical = {
    schemaVersion: 2,
    petID: "legacy-primary",
    petName: "Synthetic pet",
    type: "note",
    recordedAt: "2026-08-15T15:00:00.000Z",
    recordedLocalDate: "2026-08-16",
    recordedTimeZoneIdentifier: "Asia/Tokyo",
    detail: "Synthetic observation",
    weightKilograms: null,
    waterMilliliters: null,
    waterMeasurementBasis: null,
    waterLevel: null,
    appetiteLevel: null,
    urinationLevel: null,
    stoolStatus: null,
    energyLevel: null,
    moodStatus: null,
    createdByID: "synthetic-member",
    createdByName: "Synthetic caregiver",
    createdAt: "2026-08-15T15:00:01.000Z",
  };
  const cases = [
    { ...canonical, petID: "p".repeat(129) },
    { ...canonical, petID: "pet/other" },
    { ...canonical, createdByID: "m".repeat(129) },
    {
      ...canonical,
      recordedAt: "2026-08-16T15:00:00.000Z",
      recordedLocalDate: "2026-08-17",
    },
  ];
  const classified = classifyFixture({
    documents: cases.map((data, index) => ({
      path: `households/home-a/healthRecords/invalid-${index}`,
      data,
    })),
  });
  assert.deepEqual(
    classified.map((item) => item.classification),
    Array(cases.length).fill("malformed/quarantine"),
  );
});
