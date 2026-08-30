import { createHash } from "node:crypto";

import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { DateTime, IANAZone } from "luxon";

const dailyLevels = new Set([
  "lessThanUsual",
  "usual",
  "moreThanUsual",
  "notObserved",
]);
const dailyStatuses = new Set(["usual", "changed", "notObserved"]);
const genericHealthTypes = new Set([
  "weight",
  "waterIntake",
  "appetite",
  "energy",
  "mood",
  "stoolObservation",
  "symptom",
  "visit",
  "vaccine",
  "note",
]);
const healthCallableOptions = {
  enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
};

export function createHealthCallables(db, { now = () => new Date() } = {}) {
  return {
    createDailyHealthCheckIn: onCall(
      healthCallableOptions,
      (request) => createDailyHealthCheckInAt(db, request, now()),
    ),
    createHealthRecord: onCall(
      healthCallableOptions,
      (request) => createHealthRecordAt(db, request, now()),
    ),
  };
}

export async function createDailyHealthCheckInAt(db, request, receivedAt) {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in before recording health.");
  }
  const input = parseDailyInput(request.data);
  if (!(receivedAt instanceof Date) || Number.isNaN(receivedAt.getTime())) {
    throw new HttpsError("internal", "The server clock is unavailable.");
  }

  const household = db.collection("households").doc(input.householdID);
  const member = household.collection("members").doc(uid);
  const pet = household.collection("pets").doc(input.petID);
  const receipt = mutationReceipt(household, uid, input.clientMutationID);
  const fingerprint = requestFingerprint(input);

  return db.runTransaction(async (transaction) => {
    const [householdSnapshot, memberSnapshot, receiptSnapshot] = await Promise.all([
      transaction.get(household),
      transaction.get(member),
      transaction.get(receipt),
    ]);
    if (!householdSnapshot.exists || !memberSnapshot.exists) {
      throw new HttpsError("permission-denied", "Household membership is required.");
    }

    const priorResult = readReceipt(
      receiptSnapshot,
      fingerprint,
      "createDailyHealthCheckIn",
    );
    if (priorResult != null) return { ...priorResult, existing: true };

    const zone = canonicalZone(householdSnapshot.data()?.timeZoneIdentifier);
    const observedAt = Timestamp.fromDate(receivedAt);
    const localObservation = DateTime.fromJSDate(receivedAt, { zone });
    const localDate = localObservation.toFormat("yyyy-MM-dd");
    const recordID = digest(`${input.petID}|${localDate}`);
    const record = household.collection("healthRecords").doc(recordID);
    const startOfDay = localObservation.startOf("day").toUTC();
    const endOfDay = localObservation.startOf("day").plus({ days: 1 }).toUTC();
    const sameDayRecords = household.collection("healthRecords")
      .where("recordedAt", ">=", Timestamp.fromMillis(startOfDay.toMillis()))
      .where("recordedAt", "<", Timestamp.fromMillis(endOfDay.toMillis()));
    const [petSnapshot, recordSnapshot, sameDaySnapshot] = await Promise.all([
      transaction.get(pet),
      transaction.get(record),
      transaction.get(sameDayRecords),
    ]);
    const conflictingLegacyDaily = sameDaySnapshot.docs.find(
      (document) => document.id !== recordID &&
        document.data()?.schemaVersion !== 2 &&
        document.data()?.type === "dailyCheckIn" &&
        document.data()?.petID === input.petID,
    );
    if (conflictingLegacyDaily != null) {
      throw new HttpsError(
        "already-exists",
        "A legacy daily health check-in needs review for this pet and date.",
        { recordedLocalDate: localDate },
      );
    }
    const petName = currentPetName({
      householdData: householdSnapshot.data(),
      petID: input.petID,
      petSnapshot,
    });
    const actorName = validText(
      memberSnapshot.data()?.displayName,
      50,
      "caregiver",
    );
    const result = {
      recordID,
      recordedLocalDate: localDate,
      recordedTimeZoneIdentifier: zone,
      existing: recordSnapshot.exists,
    };

    if (recordSnapshot.exists) {
      const storedRecord = recordSnapshot.data();
      if (!sameHealthFact(storedRecord, input, localDate)) {
        throw new HttpsError(
          "already-exists",
          "A daily health check-in already exists for this pet and date.",
          { recordID, recordedLocalDate: localDate },
        );
      }
      const authoritativeResult = {
        recordID,
        recordedLocalDate: storedRecord.recordedLocalDate,
        recordedTimeZoneIdentifier: storedRecord.recordedTimeZoneIdentifier,
        existing: true,
      };
      transaction.create(receipt, receiptPayload({
        uid,
        fingerprint,
        result: authoritativeResult,
        action: "createDailyHealthCheckIn",
      }));
      return authoritativeResult;
    }

    const serverTime = FieldValue.serverTimestamp();
    transaction.create(record, {
      schemaVersion: 2,
      petID: input.petID,
      petName,
      type: "dailyCheckIn",
      recordedAt: observedAt,
      recordedLocalDate: localDate,
      recordedTimeZoneIdentifier: zone,
      detail: input.detail,
      weightKilograms: null,
      waterMilliliters: input.waterMilliliters,
      waterMeasurementBasis: input.waterMilliliters == null
        ? null
        : "localDayToDate",
      waterLevel: input.waterLevel,
      appetiteLevel: input.appetiteLevel,
      urinationLevel: input.urinationLevel,
      stoolStatus: input.stoolStatus,
      energyLevel: input.energyLevel,
      moodStatus: input.moodStatus,
      createdByID: uid,
      createdByName: actorName,
      createdAt: serverTime,
    });
    transaction.create(receipt, receiptPayload({
      uid,
      fingerprint,
      result,
      serverTime,
      action: "createDailyHealthCheckIn",
    }));
    return result;
  });
}

export async function createHealthRecordAt(db, request, receivedAt) {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in before recording health.");
  }
  if (!(receivedAt instanceof Date) || Number.isNaN(receivedAt.getTime())) {
    throw new HttpsError("internal", "The server clock is unavailable.");
  }
  const input = parseHealthRecordInput(request.data, receivedAt);
  const household = db.collection("households").doc(input.householdID);
  const member = household.collection("members").doc(uid);
  const pet = household.collection("pets").doc(input.petID);
  const receipt = mutationReceipt(household, uid, input.clientMutationID);
  const fingerprint = requestFingerprint(input);
  const recordID = `event_${digest(`${uid}:${input.clientMutationID}`)}`;
  const record = household.collection("healthRecords").doc(recordID);

  return db.runTransaction(async (transaction) => {
    const [householdSnapshot, memberSnapshot, receiptSnapshot] = await Promise.all([
      transaction.get(household),
      transaction.get(member),
      transaction.get(receipt),
    ]);
    if (!householdSnapshot.exists || !memberSnapshot.exists) {
      throw new HttpsError("permission-denied", "Household membership is required.");
    }

    const priorResult = readReceipt(
      receiptSnapshot,
      fingerprint,
      "createHealthRecord",
    );
    if (priorResult != null) return { ...priorResult, existing: true };

    const zone = canonicalZone(householdSnapshot.data()?.timeZoneIdentifier);
    const localDate = DateTime.fromMillis(input.recordedAtMilliseconds, { zone })
      .toFormat("yyyy-MM-dd");
    const [petSnapshot, recordSnapshot] = await Promise.all([
      transaction.get(pet),
      transaction.get(record),
    ]);
    const petName = currentPetName({
      householdData: householdSnapshot.data(),
      petID: input.petID,
      petSnapshot,
    });
    const actorName = validText(
      memberSnapshot.data()?.displayName,
      50,
      "caregiver",
    );
    const result = {
      recordID,
      recordedLocalDate: localDate,
      recordedTimeZoneIdentifier: zone,
      existing: recordSnapshot.exists,
    };

    if (recordSnapshot.exists) {
      if (!sameGenericHealthFact(recordSnapshot.data(), input, localDate, zone)) {
        throw new HttpsError(
          "already-exists",
          "This health mutation conflicts with an existing record.",
          { recordID },
        );
      }
      transaction.create(receipt, receiptPayload({
        uid,
        fingerprint,
        result,
        action: "createHealthRecord",
      }));
      return result;
    }

    const serverTime = FieldValue.serverTimestamp();
    transaction.create(record, {
      schemaVersion: 2,
      petID: input.petID,
      petName,
      type: input.type,
      recordedAt: Timestamp.fromMillis(input.recordedAtMilliseconds),
      recordedLocalDate: localDate,
      recordedTimeZoneIdentifier: zone,
      detail: input.detail,
      weightKilograms: input.weightKilograms,
      waterMilliliters: input.waterMilliliters,
      waterMeasurementBasis: input.type === "waterIntake"
        ? "singleIntake"
        : null,
      waterLevel: null,
      appetiteLevel: null,
      urinationLevel: null,
      stoolStatus: null,
      energyLevel: null,
      moodStatus: null,
      createdByID: uid,
      createdByName: actorName,
      createdAt: serverTime,
    });
    transaction.create(receipt, receiptPayload({
      uid,
      fingerprint,
      result,
      serverTime,
      action: "createHealthRecord",
    }));
    return result;
  });
}

function parseDailyInput(data) {
  requireStructuredInput(data, new Set([
    "householdID",
    "petID",
    "waterLevel",
    "appetiteLevel",
    "urinationLevel",
    "stoolStatus",
    "energyLevel",
    "moodStatus",
    "waterMilliliters",
    "detail",
    "clientMutationID",
  ]));
  const waterMilliliters = data.waterMilliliters == null
    ? null
    : data.waterMilliliters;
  if (waterMilliliters != null &&
      (!Number.isInteger(waterMilliliters) ||
       waterMilliliters < 1 || waterMilliliters > 10000)) {
    throw new HttpsError(
      "invalid-argument",
      "waterMilliliters must be an integer from 1 through 10000.",
    );
  }
  return {
    householdID: validID(data.householdID, "householdID"),
    petID: validID(data.petID, "petID"),
    waterLevel: validEnum(data.waterLevel, dailyLevels, "waterLevel"),
    appetiteLevel: validEnum(data.appetiteLevel, dailyLevels, "appetiteLevel"),
    urinationLevel: validEnum(data.urinationLevel, dailyLevels, "urinationLevel"),
    stoolStatus: validEnum(data.stoolStatus, dailyStatuses, "stoolStatus"),
    energyLevel: validEnum(data.energyLevel, dailyLevels, "energyLevel"),
    moodStatus: validEnum(data.moodStatus, dailyStatuses, "moodStatus"),
    waterMilliliters,
    detail: optionalText(data.detail, 500, "detail"),
    clientMutationID: validMutationID(data.clientMutationID),
  };
}

function parseHealthRecordInput(data, receivedAt) {
  requireStructuredInput(data, new Set([
    "householdID",
    "petID",
    "type",
    "recordedAtMilliseconds",
    "detail",
    "weightKilograms",
    "waterMilliliters",
    "clientMutationID",
  ]));
  const type = validEnum(data.type, genericHealthTypes, "type");
  const recordedAtMilliseconds = data.recordedAtMilliseconds;
  if (!Number.isSafeInteger(recordedAtMilliseconds)) {
    throw new HttpsError(
      "invalid-argument",
      "recordedAtMilliseconds must be a UTC epoch millisecond integer.",
    );
  }
  try {
    Timestamp.fromMillis(recordedAtMilliseconds);
  } catch {
    throw new HttpsError(
      "invalid-argument",
      "recordedAtMilliseconds is outside the supported range.",
    );
  }
  if (recordedAtMilliseconds > receivedAt.getTime() + 5000) {
    throw new HttpsError(
      "invalid-argument",
      "recordedAtMilliseconds cannot be in the future.",
    );
  }

  const detail = optionalText(data.detail, 500, "detail");
  const weightKilograms = data.weightKilograms == null
    ? null
    : data.weightKilograms;
  const waterMilliliters = data.waterMilliliters == null
    ? null
    : data.waterMilliliters;
  if (type === "weight") {
    if (typeof weightKilograms !== "number" ||
        !Number.isFinite(weightKilograms) ||
        weightKilograms <= 0 || weightKilograms > 500 ||
        waterMilliliters != null) {
      throw new HttpsError(
        "invalid-argument",
        "Weight records require kilograms greater than 0 and at most 500.",
      );
    }
  } else if (type === "waterIntake") {
    if (!Number.isInteger(waterMilliliters) ||
        waterMilliliters < 1 || waterMilliliters > 10000 ||
        weightKilograms != null) {
      throw new HttpsError(
        "invalid-argument",
        "Water records require an integer from 1 through 10000 milliliters.",
      );
    }
  } else if (detail == null || weightKilograms != null || waterMilliliters != null) {
    throw new HttpsError(
      "invalid-argument",
      "This health record requires detail and cannot include measurements.",
    );
  }

  return {
    householdID: validID(data.householdID, "householdID"),
    petID: validID(data.petID, "petID"),
    type,
    recordedAtMilliseconds,
    detail,
    weightKilograms: type === "weight" ? weightKilograms : null,
    waterMilliliters: type === "waterIntake" ? waterMilliliters : null,
    clientMutationID: validMutationID(data.clientMutationID),
  };
}

function currentPetName({ householdData, petID, petSnapshot }) {
  if (petSnapshot.exists) {
    if (petSnapshot.data()?.isArchived !== false) {
      throw new HttpsError("failed-precondition", "This pet is archived or unavailable.");
    }
    return validText(petSnapshot.data()?.name, 60, "pet");
  }
  if (petID === "legacy-primary") {
    return validText(householdData?.petName, 60, "pet");
  }
  throw new HttpsError("not-found", "This pet no longer exists.");
}

function canonicalZone(value) {
  if (typeof value !== "string" || !IANAZone.isValidZone(value)) {
    throw new HttpsError("failed-precondition", "Repair the household timezone first.");
  }
  return value;
}

function sameHealthFact(data, input, localDate) {
  return data?.schemaVersion === 2 &&
    data.petID === input.petID &&
    data.type === "dailyCheckIn" &&
    data.recordedAt instanceof Timestamp &&
    typeof data.recordedTimeZoneIdentifier === "string" &&
    IANAZone.isValidZone(data.recordedTimeZoneIdentifier) &&
    data.recordedLocalDate === localDate &&
    DateTime.fromMillis(data.recordedAt.toMillis(), {
      zone: data.recordedTimeZoneIdentifier,
    }).toFormat("yyyy-MM-dd") === data.recordedLocalDate &&
    data.detail === input.detail &&
    data.weightKilograms === null &&
    data.waterMilliliters === input.waterMilliliters &&
    data.waterMeasurementBasis === (input.waterMilliliters == null
      ? null
      : "localDayToDate") &&
    data.waterLevel === input.waterLevel &&
    data.appetiteLevel === input.appetiteLevel &&
    data.urinationLevel === input.urinationLevel &&
    data.stoolStatus === input.stoolStatus &&
    data.energyLevel === input.energyLevel &&
    data.moodStatus === input.moodStatus;
}

function sameGenericHealthFact(data, input, localDate, zone) {
  return data?.schemaVersion === 2 &&
    data.petID === input.petID &&
    data.type === input.type &&
    data.recordedAt instanceof Timestamp &&
    data.recordedAt.toMillis() === input.recordedAtMilliseconds &&
    data.recordedLocalDate === localDate &&
    data.recordedTimeZoneIdentifier === zone &&
    data.detail === input.detail &&
    data.weightKilograms === input.weightKilograms &&
    data.waterMilliliters === input.waterMilliliters &&
    data.waterMeasurementBasis === (input.type === "waterIntake"
      ? "singleIntake"
      : null) &&
    data.waterLevel === null &&
    data.appetiteLevel === null &&
    data.urinationLevel === null &&
    data.stoolStatus === null &&
    data.energyLevel === null &&
    data.moodStatus === null;
}

function mutationReceipt(household, uid, clientMutationID) {
  return household.collection("healthMutationReceipts")
    .doc(digest(`${uid}:${clientMutationID}`));
}

function requestFingerprint(input) {
  const { clientMutationID: _, ...payload } = input;
  return digest(JSON.stringify(payload));
}

function readReceipt(snapshot, fingerprint, action) {
  if (!snapshot.exists) return null;
  if (snapshot.data()?.fingerprint !== fingerprint ||
      snapshot.data()?.action !== action) {
    throw new HttpsError(
      "invalid-argument",
      "clientMutationID was already used for another health request.",
    );
  }
  return snapshot.data().result;
}

function receiptPayload({ uid, fingerprint, result, serverTime, action }) {
  return {
    schemaVersion: 1,
    uid,
    fingerprint,
    action,
    result,
    createdAt: serverTime ?? FieldValue.serverTimestamp(),
  };
}

function requireStructuredInput(data, allowed) {
  if (data == null || typeof data !== "object" || Array.isArray(data)) {
    throw new HttpsError("invalid-argument", "A structured request is required.");
  }
  if (Object.keys(data).some((key) => !allowed.has(key))) {
    throw new HttpsError("invalid-argument", "The request contains unsupported fields.");
  }
}

function validID(value, field) {
  if (typeof value !== "string" || value.length === 0 ||
      value.length > 200 || value.includes("/")) {
    throw new HttpsError("invalid-argument", `${field} is invalid.`);
  }
  return value;
}

function validMutationID(value) {
  if (typeof value !== "string" || value.length < 8 ||
      value.length > 128 || value.includes("/")) {
    throw new HttpsError("invalid-argument", "clientMutationID is invalid.");
  }
  return value;
}

function validEnum(value, allowed, field) {
  if (!allowed.has(value)) {
    throw new HttpsError("invalid-argument", `${field} is invalid.`);
  }
  return value;
}

function validText(value, maximum, label) {
  if (typeof value !== "string" || value.trim().length === 0 ||
      value.length > maximum) {
    throw new HttpsError("failed-precondition", `The ${label} is invalid.`);
  }
  return value.trim();
}

function optionalText(value, maximum, label) {
  if (value == null || value === "") return null;
  if (typeof value !== "string" || value.length > maximum) {
    throw new HttpsError("invalid-argument", `The ${label} is invalid.`);
  }
  const normalized = value.trim();
  return normalized.length === 0 ? null : normalized;
}

function digest(value) {
  return createHash("sha256").update(value).digest("hex");
}
