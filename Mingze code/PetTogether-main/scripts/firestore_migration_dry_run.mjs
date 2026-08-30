#!/usr/bin/env node

import { createHmac } from "node:crypto";
import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

const classes = [
  "canonical/no-op",
  "safe-additive",
  "safe-patch",
  "manual/blocking",
  "malformed/quarantine",
];

const legacyHealthKeys = new Set([
  "schemaVersion", "petID", "petName", "type", "recordedAt", "detail",
  "weightKilograms", "waterMilliliters", "waterLevel", "appetiteLevel",
  "urinationLevel", "stoolStatus", "energyLevel", "moodStatus",
  "createdByID", "createdByName", "createdAt",
]);

const canonicalHealthKeys = new Set([
  "schemaVersion", "petID", "petName", "type", "recordedAt",
  "recordedLocalDate", "recordedTimeZoneIdentifier", "detail",
  "weightKilograms", "waterMilliliters", "waterMeasurementBasis",
  "waterLevel", "appetiteLevel", "urinationLevel", "stoolStatus",
  "energyLevel", "moodStatus", "createdByID", "createdByName", "createdAt",
]);

export function classifyFixture(fixture) {
  if (fixture == null || !Array.isArray(fixture.documents)) {
    throw new Error("Fixture must contain a documents array.");
  }
  if (fixture.documents.some((item) => !isMigrationScopePath(item?.path))) {
    throw new Error("Migration documents contain an out-of-scope path.");
  }
  const paths = new Set(fixture.documents.map((item) => item.path));
  return fixture.documents.map((document) => ({
    path: document.path,
    classification: classifyDocument(document, paths),
  }));
}

export function receiptFor(fixture, key, afterFixture = fixture) {
  const classified = classifyFixture(fixture);
  const excludedDocuments = Array.isArray(fixture.excludedByScopeDocuments)
    ? fixture.excludedByScopeDocuments
    : [];
  if (excludedDocuments.some((item) => isMigrationScopePath(item?.path))) {
    throw new Error("excludedByScope contains a migration-source path.");
  }
  const counts = Object.fromEntries(classes.map((name) => [name, 0]));
  for (const item of classified) counts[item.classification] += 1;
  const beforeFingerprint = inventoryFingerprint(fixture, key);
  const afterFingerprint = inventoryFingerprint(afterFixture, key);
  if (beforeFingerprint !== afterFingerprint) {
    throw new Error("Emulator inventory changed during the read-only dry-run.");
  }
  return {
    schemaVersion: 1,
    mode: "dry-run",
    environment: fixture.environment,
    projectID: fixture.projectID,
    sourceDocumentCount: classified.length,
    classifiedDocumentCount: Object.values(counts).reduce(
      (total, value) => total + value,
      0,
    ),
    excludedByScope: {
      documentCount: excludedDocuments.length,
      documents: [...excludedDocuments]
        .sort((left, right) => left.path.localeCompare(right.path))
        .map((item) => ({
          pathPseudonym: createHmac("sha256", key)
            .update(item.path)
            .digest("hex"),
        })),
    },
    plannedWrites: 0,
    appliedWrites: 0,
    beforeFingerprint,
    afterFingerprint,
    counts,
    documents: [...classified]
      .sort((left, right) => left.path.localeCompare(right.path))
      .map((item) => ({
      pathPseudonym: createHmac("sha256", key).update(item.path).digest("hex"),
      classification: item.classification,
      })),
  };
}

export function isMigrationScopePath(path) {
  if (typeof path !== "string" || path.length === 0) return false;
  const segments = path.split("/");
  if (segments.length === 2) {
    return segments[0] === "households" || segments[0] === "inviteCodes";
  }
  return segments.length === 4 && segments[0] === "households" &&
    ["members", "routines", "tasks", "healthRecords"].includes(segments[2]);
}

export async function loadFixtureFromEmulator(fixture, firestoreHost, fetchImpl = fetch) {
  validateDryRunRequest({
    mode: "dry-run",
    environment: fixture?.environment,
    projectID: fixture?.projectID,
    firestoreHost,
  });
  const source = Array.isArray(fixture.documents) ? fixture.documents : [];
  const excluded = Array.isArray(fixture.excludedByScopeDocuments)
    ? fixture.excludedByScopeDocuments
    : [];
  const loaded = await Promise.all([...source, ...excluded].map(
    async (document, index) => ({
      path: document.path,
      data: await readEmulatorDocument({
        path: document.path,
        firestoreHost,
        fetchImpl,
        index,
      }),
    }),
  ));
  return {
    environment: "emulator",
    projectID: "demo-copaw",
    documents: loaded.slice(0, source.length),
    excludedByScopeDocuments: loaded.slice(source.length),
  };
}

export function validateDryRunRequest({
  mode,
  environment,
  projectID,
  firestoreHost,
}) {
  if (mode !== "dry-run") {
    throw new Error("Only the read-only dry-run mode is available.");
  }
  if (environment !== "emulator") {
    throw new Error("Only the local emulator environment is available.");
  }
  if (projectID !== "demo-copaw") {
    throw new Error("Only the explicit demo-copaw project is available.");
  }
  if (typeof firestoreHost !== "string" || firestoreHost.length === 0) {
    throw new Error("FIRESTORE_EMULATOR_HOST is required.");
  }
  const host = emulatorHostName(firestoreHost);
  if (!isLoopbackHost(host)) {
    throw new Error("FIRESTORE_EMULATOR_HOST must use a loopback host.");
  }
}

function classifyDocument(document, paths) {
  if (document == null || typeof document.path !== "string" ||
      document.path.length === 0 || document.data == null ||
      typeof document.data !== "object" || Array.isArray(document.data)) {
    return "malformed/quarantine";
  }
  const segments = document.path.split("/");
  const data = document.data;
  if (segments.length === 2 && segments[0] === "households") {
    if (!validText(data.petName) || !validText(data.name)) {
      return "malformed/quarantine";
    }
    if (!validTimeZone(data.timeZoneIdentifier)) return "manual/blocking";
    if (!paths.has(`${document.path}/pets/legacy-primary`)) {
      return "safe-additive";
    }
    return "canonical/no-op";
  }
  if (segments.length === 4 && segments[0] === "households" &&
      segments[2] === "tasks") {
    if (!validText(data.title) ||
        !["pending", "unclaimed", "claimed", "completed"].includes(data.status)) {
      return "malformed/quarantine";
    }
    const requestFields = [
      "assignmentRequestID", "requestedByID", "requestedByName",
      "assignmentMode", "requestedToID", "requestedToName",
      "assignmentRequestedAt",
    ];
    const presentRequestFields = requestFields.filter((key) => key in data);
    if (presentRequestFields.length > 0 &&
        presentRequestFields.length !== requestFields.length) {
      return "manual/blocking";
    }
    const overlays = [
      ...requestFields,
      "assigneeID", "assigneeName", "claimedAt",
      "completedByID", "completedBy", "completedAt", "revision",
    ];
    return overlays.every((key) => key in data)
      ? "canonical/no-op"
      : "manual/blocking";
  }
  if (segments.length === 4 && segments[0] === "households" &&
      segments[2] === "routines") {
    if (!validText(data.title)) {
      return "malformed/quarantine";
    }
    if (!validTimeZone(data.timeZoneIdentifier)) return "manual/blocking";
    return validText(data.petID) && validText(data.petName)
      ? "canonical/no-op"
      : "manual/blocking";
  }
  if (segments.length === 2 && segments[0] === "inviteCodes") {
    if (!validText(data.householdID)) return "malformed/quarantine";
    return !("active" in data) || typeof data.active === "boolean"
      ? "canonical/no-op"
      : "malformed/quarantine";
  }
  if (segments.length === 4 && segments[0] === "households" &&
      segments[2] === "healthRecords") {
    return classifyHealthRecord(data);
  }
  if (segments.length === 4 && segments[0] === "households" &&
      ["members", "pets"].includes(segments[2])) {
    return "canonical/no-op";
  }
  return "malformed/quarantine";
}

function validText(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function validTimeZone(value) {
  if (!validText(value)) return false;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: value }).format(0);
    return true;
  } catch {
    return false;
  }
}

function classifyHealthRecord(data) {
  const types = new Set([
    "dailyCheckIn", "weight", "waterIntake", "appetite", "energy",
    "mood", "stoolObservation", "symptom", "visit", "vaccine", "note",
  ]);
  const validBase = validHealthID(data.petID) &&
    validText(data.petName) && data.petName.length <= 60 &&
    types.has(data.type) && validInstant(data.recordedAt) &&
    validHealthID(data.createdByID) &&
    validText(data.createdByName) && data.createdByName.length <= 50 &&
    validInstant(data.createdAt) &&
    Date.parse(data.recordedAt) <= Date.parse(data.createdAt) + 5000;
  if (!validBase) return "malformed/quarantine";

  if (data.schemaVersion === 1) {
    if (!hasOnlyKeys(data, legacyHealthKeys)) return "malformed/quarantine";
    return classifyLegacyHealthShape(data);
  }
  if (data.schemaVersion !== 2 ||
      !hasExactKeys(data, canonicalHealthKeys) ||
      !validTimeZone(data.recordedTimeZoneIdentifier) ||
      localDateFor(data.recordedAt, data.recordedTimeZoneIdentifier) !==
        data.recordedLocalDate) {
    return "malformed/quarantine";
  }
  return classifyCanonicalHealthShape(data);
}

function classifyLegacyHealthShape(data) {
  if (data.type === "dailyCheckIn") {
    return validDailyFields(data) &&
        validOptionalLegacyWater(data.waterMilliliters) &&
        data.weightKilograms == null
      ? "manual/blocking"
      : "malformed/quarantine";
  }
  if (data.type === "weight") {
    return validWeight(data.weightKilograms) && data.waterMilliliters == null &&
        validOptionalDetail(data.detail) && noDailyFields(data)
      ? "canonical/no-op"
      : "malformed/quarantine";
  }
  if (data.type === "waterIntake") {
    return validLegacyWater(data.waterMilliliters) &&
        data.weightKilograms == null && validOptionalDetail(data.detail) &&
        noDailyFields(data)
      ? "manual/blocking"
      : "malformed/quarantine";
  }
  return validText(data.detail) && data.detail.length <= 500 &&
      data.weightKilograms == null && data.waterMilliliters == null &&
      noDailyFields(data)
    ? "canonical/no-op"
    : "malformed/quarantine";
}

function classifyCanonicalHealthShape(data) {
  if (data.type === "dailyCheckIn") {
    if (!validDailyFields(data) || data.weightKilograms != null ||
        !validOptionalCanonicalWater(data.waterMilliliters)) {
      return "malformed/quarantine";
    }
    return data.waterMilliliters == null
      ? data.waterMeasurementBasis == null
        ? "canonical/no-op"
        : "malformed/quarantine"
      : data.waterMeasurementBasis === "localDayToDate"
        ? "canonical/no-op"
        : "malformed/quarantine";
  }
  if (data.type === "weight") {
    return validWeight(data.weightKilograms) &&
        data.waterMilliliters == null && data.waterMeasurementBasis == null &&
        validOptionalDetail(data.detail) && noDailyFields(data)
      ? "canonical/no-op"
      : "malformed/quarantine";
  }
  if (data.type === "waterIntake") {
    if (!validCanonicalWater(data.waterMilliliters) ||
        data.weightKilograms != null || !validOptionalDetail(data.detail) ||
        !noDailyFields(data)) {
      return "malformed/quarantine";
    }
    if (data.waterMeasurementBasis === "fullLocalDay") {
      return "manual/blocking";
    }
    return data.waterMeasurementBasis === "singleIntake"
      ? "canonical/no-op"
      : "malformed/quarantine";
  }
  return validText(data.detail) && data.detail.length <= 500 &&
      data.weightKilograms == null && data.waterMilliliters == null &&
      data.waterMeasurementBasis == null && noDailyFields(data)
    ? "canonical/no-op"
    : "malformed/quarantine";
}

function validDailyFields(data) {
  const levels = new Set([
    "lessThanUsual", "usual", "moreThanUsual", "notObserved",
  ]);
  const statuses = new Set(["usual", "changed", "notObserved"]);
  return levels.has(data.waterLevel) && levels.has(data.appetiteLevel) &&
    levels.has(data.urinationLevel) && statuses.has(data.stoolStatus) &&
    levels.has(data.energyLevel) && statuses.has(data.moodStatus) &&
    (data.detail == null ||
      (typeof data.detail === "string" && data.detail.length <= 500));
}

function validWeight(value) {
  return typeof value === "number" && Number.isFinite(value) &&
    value > 0 && value <= 500;
}

function validLegacyWater(value) {
  return typeof value === "number" && Number.isFinite(value) &&
    value > 0 && value <= 10000;
}

function validCanonicalWater(value) {
  return Number.isInteger(value) && value >= 1 && value <= 10000;
}

function validOptionalLegacyWater(value) {
  return value == null || validLegacyWater(value);
}

function validOptionalCanonicalWater(value) {
  return value == null || validCanonicalWater(value);
}

function validOptionalDetail(value) {
  return value == null ||
    (typeof value === "string" && value.length <= 500);
}

function noDailyFields(data) {
  return data.waterLevel == null && data.appetiteLevel == null &&
    data.urinationLevel == null && data.stoolStatus == null &&
    data.energyLevel == null && data.moodStatus == null;
}

function hasOnlyKeys(data, allowed) {
  return Object.keys(data).every((key) => allowed.has(key));
}

function hasExactKeys(data, expected) {
  const keys = Object.keys(data);
  return keys.length === expected.size && keys.every((key) => expected.has(key));
}

function localDateFor(value, timeZone) {
  if (!validInstant(value) || !validTimeZone(timeZone)) return null;
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date(value));
  const byType = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${byType.year}-${byType.month}-${byType.day}`;
}

function validInstant(value) {
  return typeof value === "string" && Number.isFinite(Date.parse(value));
}

function validHealthID(value) {
  return validText(value) && value.length <= 128 && !value.includes("/");
}

function stableStringify(value) {
  if (Array.isArray(value)) {
    return `[${value.map(stableStringify).join(",")}]`;
  }
  if (value != null && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) =>
      `${JSON.stringify(key)}:${stableStringify(value[key])}`
    ).join(",")}}`;
  }
  return JSON.stringify(value);
}

function inventoryFingerprint(fixture, key) {
  const excluded = Array.isArray(fixture.excludedByScopeDocuments)
    ? fixture.excludedByScopeDocuments
    : [];
  const inventory = [
    ...fixture.documents.map((item) => ({ scope: "migration", ...item })),
    ...excluded.map((item) => ({ scope: "excluded", ...item })),
  ].sort((left, right) => left.path.localeCompare(right.path));
  return createHmac("sha256", key)
    .update(stableStringify(inventory))
    .digest("hex");
}

async function readEmulatorDocument({ path, firestoreHost, fetchImpl, index }) {
  if (typeof path !== "string" || path.length === 0) {
    throw new Error(`Migration inventory path ${index} is malformed.`);
  }
  const encodedPath = path.split("/").map(encodeURIComponent).join("/");
  const response = await fetchImpl(
    `http://${firestoreHost}/v1/projects/demo-copaw/databases/(default)/documents/` +
      encodedPath,
    {
      headers: { authorization: "Bearer owner" },
      signal: AbortSignal.timeout(5000),
    },
  );
  if (!response.ok) {
    throw new Error(`Migration inventory document ${index} is unavailable.`);
  }
  const wire = await response.json();
  return decodeFirestoreMap(wire.fields ?? {});
}

function decodeFirestoreMap(fields) {
  return Object.fromEntries(Object.entries(fields).map(([key, value]) => [
    key,
    decodeFirestoreValue(value),
  ]));
}

function decodeFirestoreValue(value) {
  if (value == null || typeof value !== "object") {
    throw new Error("Firestore Emulator returned a malformed value.");
  }
  if ("nullValue" in value) return null;
  if ("booleanValue" in value) return value.booleanValue;
  if ("integerValue" in value) return Number(value.integerValue);
  if ("doubleValue" in value) return Number(value.doubleValue);
  if ("timestampValue" in value) return new Date(value.timestampValue).toISOString();
  if ("stringValue" in value) return value.stringValue;
  if ("bytesValue" in value) return { bytesValue: value.bytesValue };
  if ("referenceValue" in value) return { referenceValue: value.referenceValue };
  if ("geoPointValue" in value) return { geoPointValue: value.geoPointValue };
  if ("arrayValue" in value) {
    return (value.arrayValue.values ?? []).map(decodeFirestoreValue);
  }
  if ("mapValue" in value) return decodeFirestoreMap(value.mapValue.fields ?? {});
  throw new Error("Firestore Emulator returned an unsupported value.");
}

function emulatorHostName(value) {
  if (value.startsWith("[")) {
    const closing = value.indexOf("]");
    return closing < 0 ? "" : value.slice(1, closing);
  }
  const separator = value.lastIndexOf(":");
  return separator < 0 ? "" : value.slice(0, separator);
}

function isLoopbackHost(value) {
  if (value === "localhost" || value === "::1") return true;
  const octets = value.split(".");
  return octets.length === 4 && octets[0] === "127" &&
    octets.every((item) => /^\d{1,3}$/.test(item) && Number(item) <= 255);
}

async function main() {
  const args = new Map();
  for (let index = 2; index < process.argv.length; index += 2) {
    args.set(process.argv[index], process.argv[index + 1]);
  }
  const input = args.get("--input");
  if (input == null) {
    throw new Error(
      "Usage: firestore_migration_dry_run.mjs --input FILE --mode dry-run " +
      "--environment emulator",
    );
  }
  if (process.version !== "v22.23.2") {
    throw new Error("Repository Node 22.23.2 is required.");
  }
  const environment = args.get("--environment");
  const fixture = JSON.parse(await readFile(input, "utf8"));
  validateDryRunRequest({
    mode: args.get("--mode"),
    environment,
    projectID: fixture.projectID,
    firestoreHost: process.env.FIRESTORE_EMULATOR_HOST,
  });
  if (fixture.environment !== "emulator") {
    throw new Error("The fixture must declare the emulator environment.");
  }
  const key = process.env.COPAW_MIGRATION_RECEIPT_KEY;
  if (typeof key !== "string" || key.length < 16) {
    throw new Error("Set COPAW_MIGRATION_RECEIPT_KEY to a local test-only value.");
  }
  const beforeFixture = await loadFixtureFromEmulator(
    fixture,
    process.env.FIRESTORE_EMULATOR_HOST,
  );
  const afterFixture = await loadFixtureFromEmulator(
    fixture,
    process.env.FIRESTORE_EMULATOR_HOST,
  );
  process.stdout.write(`${JSON.stringify(
    receiptFor(beforeFixture, key, afterFixture),
    null,
    2,
  )}\n`);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
