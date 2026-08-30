import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

const fixtureURL = new URL(
  "./fixtures/firestore-migration-synthetic.json",
  import.meta.url,
);
const scriptURL = new URL("../scripts/firestore_migration_dry_run.mjs", import.meta.url);
const fixture = JSON.parse(await readFile(fixtureURL, "utf8"));
const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;

test("LT7-AC05 real Emulator inventory produces identical zero-write receipts", async () => {
  assert.match(firestoreHost ?? "", /^127\.0\.0\.1:8280$/);
  for (const document of [
    ...fixture.documents,
    ...fixture.excludedByScopeDocuments,
  ]) {
    const response = await fetch(documentURL(document.path), {
      method: "PATCH",
      headers: {
        authorization: "Bearer owner",
        "content-type": "application/json",
      },
      body: JSON.stringify({ fields: encodeMap(document.data) }),
    });
    assert.equal(response.ok, true, `synthetic seed failed with ${response.status}`);
  }

  const first = runMigration("dry-run");
  const second = runMigration("dry-run");
  assert.equal(first.status, 0, first.stderr);
  assert.equal(second.status, 0, second.stderr);
  assert.equal(second.stdout, first.stdout);
  const receipt = JSON.parse(first.stdout);
  assert.equal(receipt.plannedWrites, 0);
  assert.equal(receipt.appliedWrites, 0);
  assert.equal(receipt.beforeFingerprint, receipt.afterFingerprint);
  assert.equal(receipt.excludedByScope.documentCount, 2);
  assert.equal(JSON.stringify(receipt).includes("households/home-a"), false);

  const apply = runMigration("apply");
  assert.notEqual(apply.status, 0);
  assert.match(apply.stderr, /read-only dry-run/);
  const afterRejectedApply = runMigration("dry-run");
  assert.equal(afterRejectedApply.status, 0, afterRejectedApply.stderr);
  assert.equal(afterRejectedApply.stdout, first.stdout);
});

function runMigration(mode) {
  return spawnSync(process.execPath, [
    fileURLToPath(scriptURL),
    "--input", fileURLToPath(fixtureURL),
    "--mode", mode,
    "--environment", "emulator",
  ], {
    encoding: "utf8",
    env: {
      ...process.env,
      FIRESTORE_EMULATOR_HOST: firestoreHost,
      COPAW_MIGRATION_RECEIPT_KEY: "local-emulator-receipt-key",
    },
    timeout: 10000,
  });
}

function documentURL(path) {
  const encodedPath = path.split("/").map(encodeURIComponent).join("/");
  return `http://${firestoreHost}/v1/projects/demo-copaw/` +
    `databases/(default)/documents/${encodedPath}`;
}

function encodeMap(data) {
  return Object.fromEntries(Object.entries(data).map(([key, value]) => [
    key,
    encodeValue(value),
  ]));
}

function encodeValue(value) {
  if (value == null) return { nullValue: null };
  if (typeof value === "boolean") return { booleanValue: value };
  if (Number.isInteger(value)) return { integerValue: String(value) };
  if (typeof value === "number") return { doubleValue: value };
  if (typeof value === "string") return { stringValue: value };
  if (Array.isArray(value)) {
    return { arrayValue: { values: value.map(encodeValue) } };
  }
  if (typeof value === "object") {
    return { mapValue: { fields: encodeMap(value) } };
  }
  throw new Error("Unsupported synthetic fixture value.");
}
