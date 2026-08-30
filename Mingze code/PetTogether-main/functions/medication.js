import { createHash, randomUUID } from "node:crypto";

import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { DateTime } from "luxon";

const actions = new Set(["claim", "administer", "skip"]);
const skipReasonCodes = new Set([
  "petRefused",
  "vomited",
  "unavailable",
  "vetInstruction",
  "other",
]);
const medicationCallableOptions = {
  enforceAppCheck: process.env.FUNCTIONS_EMULATOR !== "true",
};

export function createMedicationCallables(db) {
  return {
    createMedicationPlan: onCall(
      medicationCallableOptions,
      (request) => createPlan(db, request),
    ),
    replaceMedicationPlan: onCall(
      medicationCallableOptions,
      (request) => replacePlan(db, request),
    ),
    stopMedicationPlan: onCall(
      medicationCallableOptions,
      (request) => stopPlan(db, request),
    ),
    mutateMedicationOccurrence: onCall(
      medicationCallableOptions,
      (request) => mutateOccurrence(db, request),
    ),
    archivePet: onCall(medicationCallableOptions, (request) => archivePet(db, request)),
  };
}

async function stopPlan(db, request) {
  const uid = requireUID(request);
  const input = parseStopInput(request.data);
  const household = db.collection("households").doc(input.householdID);
  const actor = household.collection("members").doc(uid);
  const medication = household.collection("medications").doc(input.medicationID);
  const receipt = mutationReceipt(household, uid, input.clientMutationID);
  const fingerprint = mutationFingerprint("stopMedicationPlan", input);

  return db.runTransaction(async (transaction) => {
    const [receiptSnapshot, householdSnapshot, actorSnapshot, medicationSnapshot] =
      await Promise.all([
        transaction.get(receipt),
        transaction.get(household),
        transaction.get(actor),
        transaction.get(medication),
      ]);
    const priorResult = readReceipt(receiptSnapshot, fingerprint);
    if (priorResult != null) return priorResult;
    requireMembership(householdSnapshot, actorSnapshot);
    if (!medicationSnapshot.exists || medicationSnapshot.data()?.isActive !== true) {
      throw new HttpsError("failed-precondition", "This medication plan is not active.");
    }
    const current = medicationSnapshot.data();
    if (current.revision !== input.expectedMedicationRevision) {
      throw new HttpsError("aborted", "The medication plan changed. Refresh and try again.");
    }
    const version = medication
      .collection("scheduleVersions")
      .doc(current.currentScheduleVersionID);
    const versionSnapshot = await transaction.get(version);
    if (!versionSnapshot.exists || versionSnapshot.data()?.effectiveUntilLocalDate != null) {
      throw new HttpsError("failed-precondition", "The current medication schedule needs repair.");
    }
    const zone = validZone(householdSnapshot.data()?.timeZoneIdentifier);
    const effectiveUntil = parseLocalDate(input.effectiveUntilLocalDate, zone);
    const tomorrow = DateTime.now().setZone(zone).startOf("day").plus({ days: 1 });
    const effectiveFrom = parseLocalDate(versionSnapshot.data()?.effectiveFromLocalDate, zone);
    if (effectiveUntil < tomorrow || effectiveUntil <= effectiveFrom) {
      throw new HttpsError("failed-precondition", "A medication plan can stop tomorrow or later.");
    }
    const serverTime = FieldValue.serverTimestamp();
    const result = {
      medicationID: input.medicationID,
      effectiveUntilLocalDate: input.effectiveUntilLocalDate,
      medicationRevision: current.revision + 1,
      stopped: true,
    };
    transaction.update(version, {
      effectiveUntilLocalDate: input.effectiveUntilLocalDate,
      closedAt: serverTime,
      closedByID: uid,
      replacedByVersionID: null,
      revision: 1,
    });
    transaction.update(medication, {
      isActive: false,
      revision: current.revision + 1,
      updatedAt: serverTime,
      updatedByID: uid,
    });
    transaction.create(receipt, receiptPayload({
      uid,
      fingerprint,
      action: "stopMedicationPlan",
      result,
      serverTime,
    }));
    return result;
  });
}

async function archivePet(db, request) {
  const uid = requireUID(request);
  const input = parseArchiveInput(request.data);
  const household = db.collection("households").doc(input.householdID);
  const actor = household.collection("members").doc(uid);
  const pet = household.collection("pets").doc(input.petID);
  const activeMedications = household
    .collection("medications")
    .where("petID", "==", input.petID)
    .where("isActive", "==", true);
  const receipt = mutationReceipt(household, uid, input.clientMutationID);
  const fingerprint = mutationFingerprint("archivePet", input);

  return db.runTransaction(async (transaction) => {
    const [receiptSnapshot, householdSnapshot, actorSnapshot, petSnapshot,
      activeMedicationSnapshots] = await Promise.all([
      transaction.get(receipt),
      transaction.get(household),
      transaction.get(actor),
      transaction.get(pet),
      transaction.get(activeMedications),
    ]);
    const priorResult = readReceipt(receiptSnapshot, fingerprint);
    if (priorResult != null) return priorResult;
    requireMembership(householdSnapshot, actorSnapshot);
    if (!activeMedicationSnapshots.empty) {
      throw new HttpsError(
        "failed-precondition",
        "Stop this pet's active medication plans before archiving.",
      );
    }
    if (petSnapshot.exists && petSnapshot.data()?.isArchived === true) {
      throw new HttpsError("already-exists", "This pet is already archived.");
    }
    if (!petSnapshot.exists && input.petID !== "legacy-primary") {
      throw new HttpsError("not-found", "This pet no longer exists.");
    }
    const serverTime = FieldValue.serverTimestamp();
    if (petSnapshot.exists) {
      transaction.update(pet, { isArchived: true, updatedAt: serverTime });
    } else {
      transaction.create(pet, {
        id: "legacy-primary",
        name: validText(householdSnapshot.data()?.petName, 60, "pet"),
        species: null,
        isArchived: true,
        createdAt: serverTime,
        updatedAt: serverTime,
      });
    }
    const result = { petID: input.petID, archived: true };
    transaction.create(receipt, receiptPayload({
      uid,
      fingerprint,
      action: "archivePet",
      result,
      serverTime,
    }));
    return result;
  });
}

async function createPlan(db, request) {
  const uid = requireUID(request);
  const input = parsePlanInput(request.data, false);
  const household = db.collection("households").doc(input.householdID);
  const actor = household.collection("members").doc(uid);
  const pet = household.collection("pets").doc(input.petID);
  const medicationID = randomUUID();
  const medication = household.collection("medications").doc(medicationID);
  const versionID = formatVersionID(1);
  const version = medication.collection("scheduleVersions").doc(versionID);
  const receipt = mutationReceipt(household, uid, input.clientMutationID);
  const fingerprint = mutationFingerprint("createMedicationPlan", input);

  return db.runTransaction(async (transaction) => {
    const [receiptSnapshot, householdSnapshot, actorSnapshot, petSnapshot] = await Promise.all([
      transaction.get(receipt),
      transaction.get(household),
      transaction.get(actor),
      transaction.get(pet),
    ]);
    const priorResult = readReceipt(receiptSnapshot, fingerprint);
    if (priorResult != null) return priorResult;
    requireMembership(householdSnapshot, actorSnapshot);
    const materializeLegacyPet = !petSnapshot.exists && input.petID === "legacy-primary";
    if ((!petSnapshot.exists && !materializeLegacyPet) ||
        petSnapshot.data()?.isArchived === true) {
      throw new HttpsError("failed-precondition", "This pet is archived or unavailable.");
    }

    const zone = validZone(householdSnapshot.data()?.timeZoneIdentifier);
    const effectiveFrom = parseLocalDate(input.effectiveFromLocalDate, zone);
    if (effectiveFrom < DateTime.now().setZone(zone).startOf("day")) {
      throw new HttpsError("failed-precondition", "A medication plan cannot start in the past.");
    }
    validateScheduleDates(input, zone, effectiveFrom);
    const actorName = validText(actorSnapshot.data()?.displayName, 50, "caregiver");
    const petName = validText(
      materializeLegacyPet
        ? householdSnapshot.data()?.petName
        : petSnapshot.data()?.name,
      60,
      "pet",
    );
    const serverTime = FieldValue.serverTimestamp();
    const result = { medicationID, scheduleVersionID: versionID, scheduleVersion: 1 };

    if (materializeLegacyPet) {
      transaction.create(pet, {
        id: "legacy-primary",
        name: petName,
        species: null,
        isArchived: false,
        createdAt: serverTime,
        updatedAt: serverTime,
      });
    }

    transaction.create(medication, {
      schemaVersion: 1,
      id: medicationID,
      petID: input.petID,
      displayName: input.medicationName,
      purpose: input.purpose,
      possibleSideEffects: input.possibleSideEffects,
      isActive: true,
      currentScheduleVersion: 1,
      currentScheduleVersionID: versionID,
      revision: 0,
      createdAt: serverTime,
      createdByID: uid,
      createdByName: actorName,
      updatedAt: serverTime,
      updatedByID: uid,
    });
    transaction.create(version, versionPayload({
      input,
      medicationID,
      version: 1,
      versionID,
      petName,
      zone,
      uid,
      actorName,
      serverTime,
    }));
    transaction.create(receipt, receiptPayload({
      uid,
      fingerprint,
      action: "createMedicationPlan",
      result,
      serverTime,
    }));
    return result;
  });
}

async function replacePlan(db, request) {
  const uid = requireUID(request);
  const input = parsePlanInput(request.data, true);
  const household = db.collection("households").doc(input.householdID);
  const actor = household.collection("members").doc(uid);
  const medication = household.collection("medications").doc(input.medicationID);
  const pet = household.collection("pets").doc(input.petID);
  const receipt = mutationReceipt(household, uid, input.clientMutationID);
  const fingerprint = mutationFingerprint("replaceMedicationPlan", input);

  return db.runTransaction(async (transaction) => {
    const [receiptSnapshot, householdSnapshot, actorSnapshot, medicationSnapshot, petSnapshot] =
      await Promise.all([
        transaction.get(receipt),
        transaction.get(household),
        transaction.get(actor),
        transaction.get(medication),
        transaction.get(pet),
      ]);
    const priorResult = readReceipt(receiptSnapshot, fingerprint);
    if (priorResult != null) return priorResult;
    requireMembership(householdSnapshot, actorSnapshot);
    if (!medicationSnapshot.exists) {
      throw new HttpsError("not-found", "This medication no longer exists.");
    }
    if (!petSnapshot.exists || petSnapshot.data()?.isArchived === true) {
      throw new HttpsError("failed-precondition", "This pet is archived or unavailable.");
    }
    const current = medicationSnapshot.data();
    if (current?.petID !== input.petID || current?.isActive !== true) {
      throw new HttpsError("failed-precondition", "This medication cannot be edited.");
    }
    if (current.revision !== input.expectedMedicationRevision ||
        current.currentScheduleVersionID !== input.expectedScheduleVersionID) {
      throw new HttpsError("aborted", "The medication plan changed. Refresh and try again.");
    }
    const priorVersion = medication
      .collection("scheduleVersions")
      .doc(current.currentScheduleVersionID);
    const priorVersionSnapshot = await transaction.get(priorVersion);
    if (!priorVersionSnapshot.exists || priorVersionSnapshot.data()?.effectiveUntilLocalDate != null) {
      throw new HttpsError("failed-precondition", "The current medication schedule needs repair.");
    }

    const zone = validZone(householdSnapshot.data()?.timeZoneIdentifier);
    const effectiveFrom = parseLocalDate(input.effectiveFromLocalDate, zone);
    const tomorrow = DateTime.now().setZone(zone).startOf("day").plus({ days: 1 });
    if (effectiveFrom < tomorrow) {
      throw new HttpsError("failed-precondition", "A replacement plan must start tomorrow or later.");
    }
    validateScheduleDates(input, zone, effectiveFrom);
    const newVersion = current.currentScheduleVersion + 1;
    const newVersionID = formatVersionID(newVersion);
    const nextVersion = medication.collection("scheduleVersions").doc(newVersionID);
    const actorName = validText(actorSnapshot.data()?.displayName, 50, "caregiver");
    const petName = validText(petSnapshot.data()?.name, 60, "pet");
    const serverTime = FieldValue.serverTimestamp();
    const result = {
      medicationID: input.medicationID,
      scheduleVersionID: newVersionID,
      scheduleVersion: newVersion,
      medicationRevision: current.revision + 1,
    };

    transaction.update(priorVersion, {
      effectiveUntilLocalDate: input.effectiveFromLocalDate,
      closedAt: serverTime,
      closedByID: uid,
      replacedByVersionID: newVersionID,
      revision: 1,
    });
    transaction.create(nextVersion, versionPayload({
      input,
      medicationID: input.medicationID,
      version: newVersion,
      versionID: newVersionID,
      petName,
      zone,
      uid,
      actorName,
      serverTime,
    }));
    transaction.update(medication, {
      displayName: input.medicationName,
      purpose: input.purpose,
      possibleSideEffects: input.possibleSideEffects,
      currentScheduleVersion: newVersion,
      currentScheduleVersionID: newVersionID,
      revision: current.revision + 1,
      updatedAt: serverTime,
      updatedByID: uid,
    });
    transaction.create(receipt, receiptPayload({
      uid,
      fingerprint,
      action: "replaceMedicationPlan",
      result,
      serverTime,
    }));
    return result;
  });
}

async function mutateOccurrence(db, request) {
  const uid = requireUID(request);
  const input = parseOccurrenceInput(request.data);
  const household = db.collection("households").doc(input.householdID);
  const actor = household.collection("members").doc(uid);
  const medication = household.collection("medications").doc(input.medicationID);
  const version = medication.collection("scheduleVersions").doc(input.scheduleVersionID);
  const canonicalID = occurrenceID(input);
  const occurrence = household.collection("medicationOccurrences").doc(canonicalID);
  const receipt = mutationReceipt(household, uid, input.clientMutationID);
  const fingerprint = mutationFingerprint("mutateMedicationOccurrence", input);

  return db.runTransaction(async (transaction) => {
    const [receiptSnapshot, householdSnapshot, actorSnapshot, medicationSnapshot,
      versionSnapshot, occurrenceSnapshot] = await Promise.all([
      transaction.get(receipt),
      transaction.get(household),
      transaction.get(actor),
      transaction.get(medication),
      transaction.get(version),
      transaction.get(occurrence),
    ]);
    const priorResult = readReceipt(receiptSnapshot, fingerprint);
    if (priorResult != null) return priorResult;
    requireMembership(householdSnapshot, actorSnapshot);
    if (!medicationSnapshot.exists || !versionSnapshot.exists) {
      throw new HttpsError("not-found", "This medication schedule no longer exists.");
    }
    const versionData = versionSnapshot.data();
    const slot = canonicalOccurrence({ input, versionData, canonicalID });
    const current = occurrenceSnapshot.exists ? occurrenceSnapshot.data() : null;
    if (current?.outcomeStatus === "administered" || current?.outcomeStatus === "skipped") {
      throw terminalConflict(canonicalID, current);
    }
    if (input.action !== "claim" && slot.dueAt > DateTime.now().toUTC()) {
      throw new HttpsError("failed-precondition", "This dose is not due yet.");
    }
    if (input.action === "claim" && current?.responsibilityStatus === "claimed") {
      throw new HttpsError("already-exists", "This dose already has a responsible caregiver.", {
        occurrenceID: canonicalID,
        responsibleByName: current.responsibleByName,
      });
    }

    const actorName = validText(actorSnapshot.data()?.displayName, 50, "caregiver");
    const serverTime = FieldValue.serverTimestamp();
    const base = current ?? occurrencePayload({
      canonicalID,
      input,
      versionData,
      slot,
      serverTime,
    });
    const next = input.action === "claim"
      ? {
          ...base,
          responsibilityStatus: "claimed",
          responsibleByID: uid,
          responsibleByName: actorName,
          claimedAt: serverTime,
          revision: base.revision + 1,
        }
      : {
          ...base,
          outcomeStatus: input.action === "administer" ? "administered" : "skipped",
          outcomeByID: uid,
          outcomeByName: actorName,
          outcomeAt: serverTime,
          skippedReasonCode: input.skippedReasonCode,
          skippedReasonNote: input.skippedReasonNote,
          revision: base.revision + 1,
        };
    const result = {
      occurrenceID: canonicalID,
      action: input.action,
      revision: next.revision,
      confirmed: true,
    };
    if (occurrenceSnapshot.exists) {
      transaction.set(occurrence, next);
    } else {
      transaction.create(occurrence, next);
    }
    transaction.create(receipt, receiptPayload({
      uid,
      fingerprint,
      action: input.action,
      result,
      serverTime,
    }));
    return result;
  });
}

function parsePlanInput(data, editing) {
  const allowed = new Set([
    "householdID", "petID", "medicationName", "purpose", "possibleSideEffects", "effectiveFromLocalDate",
    "weekdays", "slots", "clientMutationID",
    ...(editing ? ["medicationID", "expectedMedicationRevision", "expectedScheduleVersionID"] : []),
  ]);
  requireStructuredInput(data, allowed);
  const weekdays = data.weekdays;
  if (!Array.isArray(weekdays) || weekdays.length === 0 || weekdays.length > 7 ||
      new Set(weekdays).size !== weekdays.length ||
      weekdays.some((day) => !Number.isInteger(day) || day < 1 || day > 7) ||
      [...weekdays].sort((a, b) => a - b).some((day, index) => day !== weekdays[index])) {
    throw new HttpsError("invalid-argument", "weekdays must be unique sorted values from 1 through 7.");
  }
  const slots = data.slots;
  if (!Array.isArray(slots) || slots.length === 0 || slots.length > 8) {
    throw new HttpsError("invalid-argument", "A plan needs one through eight dose slots.");
  }
  const parsedSlots = slots.map(parseSlot);
  if (new Set(parsedSlots.map((slot) => slot.slotID)).size !== parsedSlots.length ||
      [...parsedSlots].sort((a, b) => a.slotID.localeCompare(b.slotID))
        .some((slot, index) => slot.slotID !== parsedSlots[index].slotID)) {
    throw new HttpsError("invalid-argument", "Dose slots must be unique and sorted.");
  }
  const result = {
    householdID: validID(data.householdID, "householdID"),
    petID: validID(data.petID, "petID"),
    medicationName: validText(data.medicationName, 120, "medication name"),
    purpose: optionalText(data.purpose, 500, "medication purpose"),
    possibleSideEffects: optionalText(
      data.possibleSideEffects,
      500,
      "possible side effects",
    ),
    effectiveFromLocalDate: validDateString(data.effectiveFromLocalDate),
    weekdays,
    slots: parsedSlots,
    clientMutationID: validMutationID(data.clientMutationID),
  };
  if (!editing) return result;
  if (!Number.isInteger(data.expectedMedicationRevision) || data.expectedMedicationRevision < 0) {
    throw new HttpsError("invalid-argument", "expectedMedicationRevision is invalid.");
  }
  return {
    ...result,
    medicationID: validID(data.medicationID, "medicationID"),
    expectedMedicationRevision: data.expectedMedicationRevision,
    expectedScheduleVersionID: validID(data.expectedScheduleVersionID, "expectedScheduleVersionID"),
  };
}

function parseSlot(value) {
  requireStructuredInput(value, new Set(["slotID", "hour", "minute", "doseText", "instructions"]));
  if (!Number.isInteger(value.hour) || value.hour < 0 || value.hour > 23 ||
      !Number.isInteger(value.minute) || value.minute < 0 || value.minute > 59) {
    throw new HttpsError("invalid-argument", "A dose slot has an invalid local time.");
  }
  const expectedSlotID = `${String(value.hour).padStart(2, "0")}${String(value.minute).padStart(2, "0")}`;
  if (value.slotID !== expectedSlotID) {
    throw new HttpsError("invalid-argument", "slotID must match the local time.");
  }
  return {
    slotID: expectedSlotID,
    hour: value.hour,
    minute: value.minute,
    doseText: validText(value.doseText, 80, "dose"),
    instructions: optionalText(value.instructions, 500, "instructions"),
  };
}

function parseOccurrenceInput(data) {
  requireStructuredInput(data, new Set([
    "householdID", "medicationID", "scheduleVersionID", "localDate", "slotID",
    "action", "skippedReasonCode", "skippedReasonNote", "clientMutationID",
  ]));
  if (!actions.has(data.action)) {
    throw new HttpsError("invalid-argument", "The medication action is invalid.");
  }
  const skippedReasonCode = data.action === "skip" ? data.skippedReasonCode : null;
  if (data.action === "skip" && !skipReasonCodes.has(skippedReasonCode)) {
    throw new HttpsError("invalid-argument", "Skipping requires a valid reason.");
  }
  if (data.action !== "skip" && (data.skippedReasonCode != null || data.skippedReasonNote != null)) {
    throw new HttpsError("invalid-argument", "Only skipped doses may include a reason.");
  }
  const skippedReasonNote = data.action === "skip"
    ? optionalText(data.skippedReasonNote, 200, "skip reason note")
    : null;
  if (skippedReasonCode === "other" && skippedReasonNote == null) {
    throw new HttpsError("invalid-argument", "The other skip reason requires a note.");
  }
  if (typeof data.slotID !== "string" || !/^([01]\d|2[0-3])[0-5]\d$/.test(data.slotID)) {
    throw new HttpsError("invalid-argument", "slotID is invalid.");
  }
  return {
    householdID: validID(data.householdID, "householdID"),
    medicationID: validID(data.medicationID, "medicationID"),
    scheduleVersionID: validID(data.scheduleVersionID, "scheduleVersionID"),
    localDate: validDateString(data.localDate),
    slotID: data.slotID,
    action: data.action,
    skippedReasonCode,
    skippedReasonNote,
    clientMutationID: validMutationID(data.clientMutationID),
  };
}

function parseArchiveInput(data) {
  requireStructuredInput(
    data,
    new Set(["householdID", "petID", "clientMutationID"]),
  );
  return {
    householdID: validID(data.householdID, "householdID"),
    petID: validID(data.petID, "petID"),
    clientMutationID: validMutationID(data.clientMutationID),
  };
}

function parseStopInput(data) {
  requireStructuredInput(data, new Set([
    "householdID", "medicationID", "expectedMedicationRevision",
    "effectiveUntilLocalDate", "clientMutationID",
  ]));
  if (!Number.isInteger(data.expectedMedicationRevision) || data.expectedMedicationRevision < 0) {
    throw new HttpsError("invalid-argument", "expectedMedicationRevision is invalid.");
  }
  return {
    householdID: validID(data.householdID, "householdID"),
    medicationID: validID(data.medicationID, "medicationID"),
    expectedMedicationRevision: data.expectedMedicationRevision,
    effectiveUntilLocalDate: validDateString(data.effectiveUntilLocalDate),
    clientMutationID: validMutationID(data.clientMutationID),
  };
}

function canonicalOccurrence({ input, versionData, canonicalID }) {
  if (versionData?.medicationID !== input.medicationID ||
      versionData?.id !== input.scheduleVersionID) {
    throw new HttpsError("failed-precondition", "This medication schedule needs repair.");
  }
  const zone = validZone(versionData.timeZoneIdentifier);
  const day = parseLocalDate(input.localDate, zone);
  const start = parseLocalDate(versionData.effectiveFromLocalDate, zone);
  const end = versionData.effectiveUntilLocalDate == null
    ? null
    : parseLocalDate(versionData.effectiveUntilLocalDate, zone);
  const slot = Array.isArray(versionData.slots)
    ? versionData.slots.find((candidate) => candidate?.slotID === input.slotID)
    : null;
  if (canonicalID !== occurrenceID(input) || slot == null ||
      !Array.isArray(versionData.weekdays) ||
      !versionData.weekdays.includes(day.weekday % 7 + 1) ||
      day < start || (end != null && day >= end)) {
    throw new HttpsError("failed-precondition", "This dose is not scheduled.");
  }
  const dueAt = localSlotDateTime(day, slot, zone);
  return {
    slot,
    dueAt: dueAt.toUTC(),
  };
}

function occurrencePayload({ canonicalID, input, versionData, slot, serverTime }) {
  return {
    schemaVersion: 1,
    id: canonicalID,
    medicationID: input.medicationID,
    scheduleVersionID: input.scheduleVersionID,
    scheduleVersion: versionData.version,
    slotID: input.slotID,
    localDate: input.localDate,
    dueAt: Timestamp.fromDate(slot.dueAt.toJSDate()),
    timeZoneIdentifier: versionData.timeZoneIdentifier,
    petID: validID(versionData.petID, "petID"),
    petName: validText(versionData.petName, 60, "pet"),
    medicationName: validText(versionData.medicationName, 120, "medication name"),
    doseText: validText(slot.slot.doseText, 80, "dose"),
    instructions: optionalText(slot.slot.instructions, 500, "instructions"),
    responsibilityStatus: "unclaimed",
    responsibleByID: null,
    responsibleByName: null,
    claimedAt: null,
    outcomeStatus: "unresolved",
    outcomeByID: null,
    outcomeByName: null,
    outcomeAt: null,
    skippedReasonCode: null,
    skippedReasonNote: null,
    materializedAt: serverTime,
    revision: 0,
  };
}

function versionPayload({ input, medicationID, version, versionID, petName, zone,
  uid, actorName, serverTime }) {
  return {
    schemaVersion: 1,
    id: versionID,
    medicationID,
    version,
    petID: input.petID,
    petName,
    medicationName: input.medicationName,
    weekdays: input.weekdays,
    slots: input.slots,
    timeZoneIdentifier: zone,
    dstPolicy: "reject",
    effectiveFromLocalDate: input.effectiveFromLocalDate,
    effectiveUntilLocalDate: null,
    createdAt: serverTime,
    createdByID: uid,
    createdByName: actorName,
    closedAt: null,
    closedByID: null,
    replacedByVersionID: null,
    revision: 0,
  };
}

function validateScheduleDates(input, zone, effectiveFrom) {
  for (let offset = 0; offset < 400; offset += 1) {
    const day = effectiveFrom.plus({ days: offset });
    if (!input.weekdays.includes(day.weekday % 7 + 1)) continue;
    for (const slot of input.slots) localSlotDateTime(day, slot, zone);
  }
}

function localSlotDateTime(day, slot, zone) {
  const local = DateTime.fromObject({
    year: day.year,
    month: day.month,
    day: day.day,
    hour: slot.hour,
    minute: slot.minute,
  }, { zone });
  if (!local.isValid || local.year !== day.year || local.month !== day.month ||
      local.day !== day.day || local.hour !== slot.hour || local.minute !== slot.minute ||
      local.getPossibleOffsets().length !== 1) {
    throw new HttpsError("failed-precondition", "A dose time crosses a daylight-saving boundary.");
  }
  return local;
}

function requireStructuredInput(data, allowed) {
  if (data == null || typeof data !== "object" || Array.isArray(data)) {
    throw new HttpsError("invalid-argument", "A structured request is required.");
  }
  if (Object.keys(data).some((key) => !allowed.has(key))) {
    throw new HttpsError("invalid-argument", "The request contains unsupported fields.");
  }
}

function requireUID(request) {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in before changing medication.");
  return uid;
}

function requireMembership(householdSnapshot, actorSnapshot) {
  if (!householdSnapshot.exists || !actorSnapshot.exists) {
    throw new HttpsError("permission-denied", "Household membership is required.");
  }
}

function mutationReceipt(household, uid, clientMutationID) {
  const id = createHash("sha256").update(`${uid}:${clientMutationID}`).digest("hex");
  return household.collection("medicationMutationReceipts").doc(id);
}

function mutationFingerprint(action, input) {
  return createHash("sha256").update(JSON.stringify({ action, input })).digest("hex");
}

function readReceipt(snapshot, fingerprint) {
  if (!snapshot.exists) return null;
  if (snapshot.data()?.fingerprint !== fingerprint) {
    throw new HttpsError("invalid-argument", "clientMutationID was already used for another action.");
  }
  return snapshot.data().result;
}

function receiptPayload({ uid, fingerprint, action, result, serverTime }) {
  return { uid, fingerprint, action, result, createdAt: serverTime };
}

function terminalConflict(occurrenceIDValue, current) {
  return new HttpsError("already-exists", "This dose was already recorded.", {
    occurrenceID: occurrenceIDValue,
    outcomeStatus: current.outcomeStatus,
    outcomeByName: current.outcomeByName,
    outcomeAt: current.outcomeAt instanceof Timestamp
      ? current.outcomeAt.toDate().toISOString()
      : null,
    revision: current.revision,
  });
}

function formatVersionID(version) {
  return `v${String(version).padStart(6, "0")}`;
}

function occurrenceID(input) {
  return `${input.medicationID}_${input.scheduleVersionID}_${input.localDate}_${input.slotID}`;
}

function validZone(value) {
  if (typeof value !== "string" || !DateTime.now().setZone(value).isValid) {
    throw new HttpsError("failed-precondition", "Repair the household timezone first.");
  }
  return value;
}

function validDateString(value) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new HttpsError("invalid-argument", "A local date must use YYYY-MM-DD.");
  }
  return value;
}

function parseLocalDate(value, zone) {
  validDateString(value);
  const day = DateTime.fromFormat(value, "yyyy-MM-dd", { zone, setZone: true });
  if (!day.isValid || day.toFormat("yyyy-MM-dd") !== value) {
    throw new HttpsError("invalid-argument", "The local date is invalid.");
  }
  return day.startOf("day");
}

function validID(value, field) {
  if (typeof value !== "string" || value.length === 0 || value.length > 200 || value.includes("/")) {
    throw new HttpsError("invalid-argument", `${field} is invalid.`);
  }
  return value;
}

function validMutationID(value) {
  if (typeof value !== "string" || value.length < 8 || value.length > 128 || value.includes("/")) {
    throw new HttpsError("invalid-argument", "clientMutationID is invalid.");
  }
  return value;
}

function validText(value, maximum, label) {
  if (typeof value !== "string" || value.trim().length === 0 || value.length > maximum) {
    throw new HttpsError("invalid-argument", `The ${label} is invalid.`);
  }
  return value.trim();
}

function optionalText(value, maximum, label) {
  if (value == null || value === "") return null;
  return validText(value, maximum, label);
}
