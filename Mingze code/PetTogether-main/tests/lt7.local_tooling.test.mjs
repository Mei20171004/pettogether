import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { test } from "node:test";

import {
  LT7_NODE_VERSION,
  assertLt7Environment,
  buildFirebaseArguments,
  assertIsolatedHubInventory,
  assertSignedExportManifest,
  createSignedExportManifest,
  exportFromIsolatedHub,
  isolatedHubOrigin,
  lt7FirebaseEnvironment,
  parseJavaMajor,
} from "../scripts/lt7_local_environment.mjs";
import {
  EXPECTED_FUNCTION_EXPORTS,
  verifyFunctionExports,
} from "../scripts/verify_functions_exports.mjs";
import {
  REQUIRED_PRESERVATION_SENTINELS,
  createPreservationManifest,
  reconcilePreservationManifests,
  validatePreservationSeed,
} from "../scripts/lt7_preservation_manifest.mjs";
import { createSnapshotReceipt } from "../scripts/lt7_snapshot_receipt.mjs";

const repositoryRoot = new URL("../", import.meta.url);

test("LT7-AC01 pins every local entry point to repository Node 22.23.2", async () => {
  assert.equal(LT7_NODE_VERSION, "22.23.2");
  assert.equal(
    (await readFile(new URL("../.node-version", import.meta.url), "utf8")).trim(),
    LT7_NODE_VERSION,
  );
  const packageJSON = JSON.parse(await readFile(
    new URL("../package.json", import.meta.url),
    "utf8",
  ));
  assert.equal(packageJSON.engines.node, LT7_NODE_VERSION);
  assert.equal(packageJSON.devDependencies.node, LT7_NODE_VERSION);
  for (const name of [
    "lt7:emulators", "lt7:rules", "lt7:functions", "lt7:migration",
    "lt7:snapshot", "lt7:export", "lt7:restore", "lt7:verify-exports",
  ]) {
    assert.match(packageJSON.scripts[name], /^\.\/scripts\/node22_exec\.sh /);
  }
});

test("LT7-AC01 rejects runtime, Java, project, and non-loopback hosts before ports", () => {
  assert.equal(parseJavaMajor('openjdk version "21.0.8"'), 21);
  assert.equal(parseJavaMajor('java version "1.8.0_402"'), 8);
  const valid = {
    nodeVersion: "v22.23.2",
    javaVersionOutput: 'openjdk version "21.0.8"',
    projectID: "demo-copaw",
    hosts: {
      auth: "127.0.0.1",
      firestore: "localhost",
      functions: "::1",
      hub: "127.0.0.1",
      logging: "127.0.0.1",
    },
  };
  assert.doesNotThrow(() => assertLt7Environment(valid));
  assert.throws(
    () => assertLt7Environment({ ...valid, nodeVersion: "v24.2.0" }),
    /Node 22\.23\.2/,
  );
  assert.throws(
    () => assertLt7Environment({ ...valid, javaVersionOutput: "" }),
    /Java 21/,
  );
  assert.throws(
    () => assertLt7Environment({
      ...valid,
      javaVersionOutput: 'openjdk version "17.0.12"',
    }),
    /Java 21/,
  );
  assert.throws(
    () => assertLt7Environment({ ...valid, projectID: "copaw-prod" }),
    /demo-copaw/,
  );
  assert.throws(
    () => assertLt7Environment({
      ...valid,
      hosts: { ...valid.hosts, firestore: "0.0.0.0" },
    }),
    /loopback/,
  );
  assert.throws(
    () => assertLt7Environment({
      ...valid,
      hosts: { ...valid.hosts, auth: "" },
    }),
    /loopback/,
  );
});

test("LT7-AC01 export and restore are isolated and cannot target main ports", () => {
  const config = {
    auth: { host: "127.0.0.1", port: 9399 },
    firestore: { host: "127.0.0.1", port: 8280 },
    functions: { host: "127.0.0.1", port: 5201 },
    hub: { host: "127.0.0.1", port: 4700 },
    logging: { host: "127.0.0.1", port: 4701 },
  };
  assert.equal(isolatedHubOrigin(config), "http://127.0.0.1:4700");
  assert.doesNotThrow(() => assertIsolatedHubInventory(
    config,
    {
      host: "127.0.0.1",
      port: 4700,
      origins: ["http://127.0.0.1:4700"],
    },
    {
      auth: { host: "127.0.0.1", port: 9399 },
      firestore: { host: "127.0.0.1", port: 8280 },
    },
  ));
  assert.throws(() => assertIsolatedHubInventory(
    config,
    {
      host: "127.0.0.1",
      port: 4400,
      origins: ["http://127.0.0.1:4400"],
    },
    {
      auth: { host: "127.0.0.1", port: 9299 },
      firestore: { host: "127.0.0.1", port: 8080 },
    },
  ), /unexpected Emulator hub/);
  const environment = lt7FirebaseEnvironment(config, {});
  assert.equal(environment.FIREBASE_EMULATOR_HUB, "127.0.0.1:4700");
  assert.equal(environment.FIRESTORE_EMULATOR_HOST, "127.0.0.1:8280");
  assert.equal(environment.FIREBASE_AUTH_EMULATOR_HOST, "127.0.0.1:9399");
  assert.notEqual(environment.FIREBASE_EMULATOR_HUB, "127.0.0.1:4400");
  assert.deepEqual(
    buildFirebaseArguments("snapshot", undefined, config),
    [
      "emulators:start", "--only", "auth,firestore",
      "--config", "firebase.lt7.json", "--project", "demo-copaw",
    ],
  );
  assert.deepEqual(
    buildFirebaseArguments("restore", "/tmp/copaw-lt7-export", config),
    [
      "emulators:start", "--only", "auth,firestore",
      "--import", "/tmp/copaw-lt7-export", "--config", "firebase.lt7.json",
      "--project", "demo-copaw",
    ],
  );
  const signed = createSignedExportManifest(config, {
    version: "15.26.0",
  }, "local-snapshot-key-1234");
  assert.doesNotThrow(() => assertSignedExportManifest(
    signed,
    config,
    "local-snapshot-key-1234",
  ));
  assert.throws(() => assertSignedExportManifest(
    { ...signed, projectID: "copaw-prod" },
    config,
    "local-snapshot-key-1234",
  ), /untrusted export manifest/);
  assert.throws(
    () => buildFirebaseArguments("restore", "/tmp/copaw-lt7-export", {
      ...config,
      firestore: { host: "127.0.0.1", port: 8080 },
    }),
    /reserved main Emulator port/,
  );
  assert.throws(
    () => buildFirebaseArguments("restore", "/tmp/copaw-lt7-export", {
      ...config,
      auth: { host: "127.0.0.1", port: 9299 },
    }),
    /reserved main Emulator port/,
  );
  assert.throws(
    () => buildFirebaseArguments("apply", "/tmp/unused", config),
    /Unsupported LT7 operation/,
  );
});

test("LT7-AC02 freezes exactly 24 discoverable Functions exports", async () => {
  assert.equal(EXPECTED_FUNCTION_EXPORTS.length, 24);
  assert.equal(new Set(EXPECTED_FUNCTION_EXPORTS).size, 24);
  const fake = Object.fromEntries(EXPECTED_FUNCTION_EXPORTS.map((name) => [
    name,
    () => name,
  ]));
  assert.deepEqual(verifyFunctionExports(fake), EXPECTED_FUNCTION_EXPORTS);
  assert.throws(
    () => verifyFunctionExports({ ...fake, unexpected: () => {} }),
    /unexpected/,
  );
  assert.throws(
    () => verifyFunctionExports(Object.fromEntries(
      EXPECTED_FUNCTION_EXPORTS.slice(1).map((name) => [name, () => name]),
    )),
    /missing/,
  );
  const frozen = JSON.parse(await readFile(
    new URL("./fixtures/lt7-functions-exports.json", import.meta.url),
    "utf8",
  ));
  assert.deepEqual(frozen.exports, EXPECTED_FUNCTION_EXPORTS);
});

test("LT7-AC04 preservation manifest covers LT4-LT6 without raw paths or content", async () => {
  const seed = JSON.parse(await readFile(
    new URL("./fixtures/lt7-preservation-sentinels.json", import.meta.url),
    "utf8",
  ));
  assert.deepEqual(
    seed.sentinels.map((item) => item.type).sort(),
    [...REQUIRED_PRESERVATION_SENTINELS].sort(),
  );
  assert.doesNotThrow(() => validatePreservationSeed(seed));
  const manifest = createPreservationManifest(seed, "local-receipt-key-1234");
  assert.equal(manifest.sentinelCount, REQUIRED_PRESERVATION_SENTINELS.length);
  assert.equal(manifest.pathCount, REQUIRED_PRESERVATION_SENTINELS.length);
  assert.equal(
    manifest.semanticFingerprintCount,
    REQUIRED_PRESERVATION_SENTINELS.length,
  );
  assert.equal(manifest.semanticProjection.health.recordCount, 2);
  assert.equal(manifest.semanticProjection.health.legacyRecordCount, 1);
  assert.equal(manifest.semanticProjection.health.dailyIdentityCount, 1);
  // Buckets stay neutral so the receipt never reproduces a stored enum label.
  assert.deepEqual(manifest.semanticProjection.health.waterBasisCounts, {
    unspecifiedBasis: 1,
    singleDoseBasis: 0,
    dayToDateBasis: 1,
    fullDayBasis: 0,
  });
  assert.equal(manifest.semanticProjection.report.taskCount, 2);
  assert.equal(manifest.semanticProjection.report.taskCompletedCount, 1);
  assert.equal(manifest.semanticProjection.report.medicationAdministeredCount, 1);
  assert.equal(manifest.semanticProjection.report.ledgerExcludedCount, 1);
  assert.equal(manifest.semanticProjection.report.notificationExcludedCount, 3);
  assert.match(manifest.semanticProjectionFingerprint, /^[0-9a-f]{64}$/);
  assert.doesNotThrow(() => reconcilePreservationManifests(manifest, manifest));
  const serialized = JSON.stringify(manifest);
  for (const sentinel of seed.sentinels) {
    assert.equal(serialized.includes(sentinel.path), false);
    for (const value of Object.values(sentinel.data)) {
      if (typeof value === "string" && value.length > 3) {
        assert.equal(serialized.includes(value), false);
      }
    }
  }
  const changed = structuredClone(manifest);
  changed.sentinels[0].contentFingerprint = "0".repeat(64);
  assert.throws(
    () => reconcilePreservationManifests(manifest, changed),
    /preservation manifest changed/,
  );
});

test("LT7-AC04 rejects malformed semantic sentinel shapes and references", async () => {
  const seed = JSON.parse(await readFile(
    new URL("./fixtures/lt7-preservation-sentinels.json", import.meta.url),
    "utf8",
  ));
  for (const [type, mutate] of [
    ["task", (data) => { data.completedAt = "not-a-timestamp"; }],
    ["healthV2", (data) => { data.waterMeasurementBasis = "singleIntake"; }],
    ["responsibilityPointer", (data) => { data.transferID = "other-transfer"; }],
    ["collaborationReadCursor", (data) => { data.eventID = "other-event"; }],
    ["notificationInbox", (data) => { data.sourceRevision += 1; }],
    ["notificationDelivery", (data) => { data.attemptCount = 4; }],
    ["taskCompleted", (data) => { data.completedAt = null; }],
    ["healthV2", (data) => { data.recordedLocalDate = "2026-08-16"; }],
    ["handoffVersion", (data) => { data.careInstructions = "Edited later"; }],
    ["handoffSession", (data) => { data.versionID = "v000001"; }],
    ["responsibilityTransfer", (data) => { data.kind = "takeover"; }],
    ["medicationOccurrence", (data) => { data.outcomeStatus = "skipped"; }],
    ["collaborationLedger", (data) => { data.sourceRevision = 2; }],
    ["notificationReadCursor", (data) => { data.intentID = "a".repeat(64); }],
    ["notificationPreference", (data) => { data.revision = 2; }],
  ]) {
    const changed = structuredClone(seed);
    mutate(changed.sentinels.find((item) => item.type === type).data);
    assert.throws(
      () => validatePreservationSeed(changed),
      new RegExp(type),
      `${type} corruption must fail closed`,
    );
  }
});

test("LT7 tooling never embeds this repository absolute path", async () => {
  const packageJSON = await readFile(new URL("../package.json", import.meta.url), "utf8");
  assert.equal(packageJSON.includes(repositoryRoot.pathname), false);
});

test("LT7-AC04 snapshot receipt rejects missing hosts and non-demo projects", async () => {
  const seed = JSON.parse(await readFile(
    new URL("./fixtures/lt7-preservation-sentinels.json", import.meta.url),
    "utf8",
  ));
  await assert.rejects(
    createSnapshotReceipt({
      seed,
      firestoreHost: "127.0.0.1:8280",
      authHost: "",
      key: "local-receipt-key-1234",
    }),
    /FIREBASE_AUTH_EMULATOR_HOST is required/,
  );
  await assert.rejects(
    createSnapshotReceipt({
      seed: { ...seed, projectID: "copaw-prod" },
      firestoreHost: "127.0.0.1:8280",
      authHost: "127.0.0.1:9399",
      key: "local-receipt-key-1234",
    }),
    /demo-copaw/,
  );
});

test("LT7-AC04 guarded export fails closed when the isolated hub is unavailable", async () => {
  const config = {
    auth: { host: "127.0.0.1", port: 9399 },
    firestore: { host: "127.0.0.1", port: 8280 },
    functions: { host: "127.0.0.1", port: 5201 },
    hub: { host: "127.0.0.1", port: 4700 },
    logging: { host: "127.0.0.1", port: 4701 },
  };
  let calls = 0;
  await assert.rejects(
    exportFromIsolatedHub(
      config,
      "/tmp/copaw-lt7-unavailable-export",
      async () => {
        calls += 1;
        return { ok: false };
      },
      "local-snapshot-key-1234",
    ),
    /isolated Emulator hub is unavailable/,
  );
  assert.equal(calls, 2);
});
