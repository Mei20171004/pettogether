#!/usr/bin/env node

import { createHmac } from "node:crypto";
import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

import {
  loadFixtureFromEmulator,
  validateDryRunRequest,
} from "./firestore_migration_dry_run.mjs";
import { createPreservationManifest } from "./lt7_preservation_manifest.mjs";

export async function createSnapshotReceipt({
  seed,
  firestoreHost,
  authHost,
  key,
  fetchImpl = fetch,
}) {
  validateDryRunRequest({
    mode: "dry-run",
    environment: seed?.environment,
    projectID: seed?.projectID,
    firestoreHost,
  });
  assertLoopbackEndpoint(authHost, "FIREBASE_AUTH_EMULATOR_HOST");
  if (typeof key !== "string" || key.length < 16) {
    throw new Error("COPAW_SNAPSHOT_RECEIPT_KEY must contain at least 16 characters.");
  }
  const loaded = await loadFixtureFromEmulator({
    environment: seed.environment,
    projectID: seed.projectID,
    documents: seed.sentinels.map(({ path, data }) => ({ path, data })),
    excludedByScopeDocuments: [],
  }, firestoreHost, fetchImpl);
  const actualSeed = {
    ...seed,
    sentinels: seed.sentinels.map((sentinel, index) => ({
      ...sentinel,
      data: loaded.documents[index].data,
    })),
  };
  const firestore = createPreservationManifest(actualSeed, key);
  const accountsResponse = await fetchImpl(
    `http://${authHost}/identitytoolkit.googleapis.com/v1/projects/` +
      `demo-copaw/accounts:batchGet?maxResults=1000&key=local`,
    {
      headers: { authorization: "Bearer owner" },
      signal: AbortSignal.timeout(5000),
    },
  );
  if (!accountsResponse.ok) {
    throw new Error("LT7 Auth inventory is unavailable.");
  }
  const accountsBody = await accountsResponse.json();
  const users = Array.isArray(accountsBody.users) ? accountsBody.users : [];
  const uidPseudonyms = users.map((user) => {
    if (typeof user.localId !== "string" || user.localId.length === 0) {
      throw new Error("LT7 Auth inventory contains a malformed UID.");
    }
    return hmac(key, user.localId);
  }).sort();
  const auth = {
    accountCount: uidPseudonyms.length,
    uidPseudonyms,
  };
  return {
    schemaVersion: 1,
    environment: "emulator",
    projectID: "demo-copaw",
    auth,
    firestore,
    snapshotFingerprint: hmac(key, stableStringify({ auth, firestore })),
  };
}

async function main() {
  if (process.version !== "v22.23.2") {
    throw new Error("Repository Node 22.23.2 is required.");
  }
  const args = new Map();
  for (let index = 2; index < process.argv.length; index += 2) {
    args.set(process.argv[index], process.argv[index + 1]);
  }
  const input = args.get("--input");
  if (typeof input !== "string") {
    throw new Error("Usage: lt7_snapshot_receipt.mjs --input SENTINEL_FILE");
  }
  const seed = JSON.parse(await readFile(input, "utf8"));
  const receipt = await createSnapshotReceipt({
    seed,
    firestoreHost: process.env.FIRESTORE_EMULATOR_HOST,
    authHost: process.env.FIREBASE_AUTH_EMULATOR_HOST,
    key: process.env.COPAW_SNAPSHOT_RECEIPT_KEY,
  });
  process.stdout.write(`${JSON.stringify(receipt)}\n`);
}

function assertLoopbackEndpoint(value, name) {
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`${name} is required.`);
  }
  const match = value.match(/^([^:]+):(\d+)$/);
  if (match == null ||
      !(match[1] === "localhost" || /^127(?:\.\d{1,3}){3}$/.test(match[1]))) {
    throw new Error(`${name} must use a loopback host.`);
  }
  const port = Number(match[2]);
  if (!Number.isInteger(port) || port < 1024 || port > 65535) {
    throw new Error(`${name} has an invalid port.`);
  }
}

function hmac(key, value) {
  return createHmac("sha256", key).update(value).digest("hex");
}

function stableStringify(value) {
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(",")}]`;
  if (value != null && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) =>
      `${JSON.stringify(key)}:${stableStringify(value[key])}`
    ).join(",")}}`;
  }
  return JSON.stringify(value);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
