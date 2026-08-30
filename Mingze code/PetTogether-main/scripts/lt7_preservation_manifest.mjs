import { createHash, createHmac, timingSafeEqual } from "node:crypto";

export const REQUIRED_PRESERVATION_SENTINELS = Object.freeze([
  "household", "member", "invite", "pet", "task", "taskCompleted", "routine",
  "medicationPlan", "medicationVersion", "medicationOccurrence",
  "healthV1", "healthV2", "handoffTemplate", "handoffVersion",
  "handoffSession", "responsibilityTransfer", "responsibilityPointer",
  "collaborationLedger", "collaborationReadCursor",
  "notificationPreference", "notificationInbox", "notificationReadCursor",
  "notificationDelivery",
]);

// Neutral projection buckets. They deliberately avoid reproducing the stored
// enum labels so the manifest stays free of source content.
const WATER_BASIS_BUCKETS = Object.freeze({
  legacyUnspecified: "unspecifiedBasis",
  singleIntake: "singleDoseBasis",
  localDayToDate: "dayToDateBasis",
  fullLocalDay: "fullDayBasis",
});

const TASK_FIELDS = Object.freeze({
  id: "id",
  title: "text120",
  category: "enum:feeding|walking|medication|grooming|other",
  dueTime: "ts",
  kind: "enum:oneOff|routine",
  priority: "enum:normal|urgent",
  routineID: "id?",
  petID: "id?",
  petName: "text60?",
  status: "enum:unclaimed|claimed|completed",
  assignmentRequestID: "id?",
  assignmentMode: "enum?:direct|open",
  requestedByID: "id?",
  requestedByName: "text60?",
  requestedToID: "id?",
  requestedToName: "text60?",
  assignmentRequestedAt: "ts?",
  assigneeID: "id?",
  assigneeName: "text60?",
  claimedAt: "ts?",
  createdByID: "id",
  createdBy: "text60",
  createdAt: "ts",
  completedByID: "id?",
  completedBy: "text60?",
  completedAt: "ts?",
  revision: "count",
});

const HEALTH_TYPES = "dailyCheckIn|weight|waterIntake|appetite|energy|mood|" +
  "stoolObservation|symptom|visit|vaccine|note";
const HEALTH_LEVEL = "enum?:lessThanUsual|usual|moreThanUsual|notObserved";
const HEALTH_STATUS = "enum?:usual|changed|notObserved";

const SENTINEL_SPECS = Object.freeze({
  household: {
    path: /^households\/[^/]+$/,
    fields: {
      id: "id", name: "text60", petName: "text60", inviteCode: "code",
      timeZoneIdentifier: "zone", ownerID: "id", createdAt: "ts",
      updatedAt: "ts",
    },
  },
  member: {
    path: /^households\/[^/]+\/members\/[^/]+$/,
    fields: {
      id: "id", displayName: "text60", inviteCode: "code", joinedAt: "ts",
      updatedAt: "ts",
    },
  },
  invite: {
    path: /^inviteCodes\/[^/]+$/,
    fields: {
      householdID: "id", createdBy: "id", createdAt: "ts", active: "bool",
    },
  },
  pet: {
    path: /^households\/[^/]+\/pets\/[^/]+$/,
    fields: {
      id: "id", name: "text60", species: "text60?", isArchived: "bool",
      createdAt: "ts", updatedAt: "ts",
    },
  },
  task: { path: /^households\/[^/]+\/tasks\/[^/]+$/, fields: TASK_FIELDS },
  taskCompleted: {
    path: /^households\/[^/]+\/tasks\/[^/]+$/, fields: TASK_FIELDS,
  },
  routine: {
    path: /^households\/[^/]+\/routines\/[^/]+$/,
    fields: {
      id: "id", title: "text120",
      category: "enum:feeding|walking|medication|grooming|other",
      priority: "enum:normal|urgent", hour: "hour", minute: "minute",
      frequency: "enum:daily|selectedDays", weekdays: "weekdays",
      startDate: "ts", timeZoneIdentifier: "zone", createdByID: "id",
      createdByName: "text60", petID: "id", petName: "text60",
      isActive: "bool", createdAt: "ts",
    },
  },
  medicationPlan: {
    path: /^households\/[^/]+\/medications\/[^/]+$/,
    fields: {
      schemaVersion: "version1", id: "id", petID: "id",
      displayName: "text120", purpose: "text200?",
      possibleSideEffects: "text200?", isActive: "bool",
      currentScheduleVersion: "positive", currentScheduleVersionID: "id",
      revision: "count", createdAt: "ts", createdByID: "id",
      createdByName: "text60", updatedAt: "ts", updatedByID: "id",
    },
  },
  medicationVersion: {
    path: /^households\/[^/]+\/medications\/[^/]+\/scheduleVersions\/[^/]+$/,
    fields: {
      schemaVersion: "version1", id: "id", medicationID: "id",
      version: "positive", petID: "id", petName: "text60",
      medicationName: "text120", weekdays: "weekdays", slots: "slots",
      timeZoneIdentifier: "zone", dstPolicy: "enum:reject",
      effectiveFromLocalDate: "date", effectiveUntilLocalDate: "date?",
      createdAt: "ts", createdByID: "id", createdByName: "text60",
      closedAt: "ts?", closedByID: "id?", replacedByVersionID: "id?",
      revision: "count",
    },
  },
  medicationOccurrence: {
    path: /^households\/[^/]+\/medicationOccurrences\/[^/]+$/,
    fields: {
      schemaVersion: "version1", id: "id", medicationID: "id",
      scheduleVersionID: "id", scheduleVersion: "positive", slotID: "slot",
      localDate: "date", dueAt: "ts", timeZoneIdentifier: "zone",
      petID: "id", petName: "text60", medicationName: "text120",
      doseText: "text120", instructions: "text200?",
      responsibilityStatus: "enum:unclaimed|claimed",
      responsibleByID: "id?", responsibleByName: "text60?", claimedAt: "ts?",
      outcomeStatus: "enum:unresolved|administered|skipped",
      outcomeByID: "id?", outcomeByName: "text60?", outcomeAt: "ts?",
      skippedReasonCode: "text60?", skippedReasonNote: "text200?",
      materializedAt: "ts", revision: "count",
    },
  },
  healthV1: {
    path: /^households\/[^/]+\/healthRecords\/[^/]+$/,
    fields: {
      schemaVersion: "version1", petID: "id", petName: "text60",
      type: `enum:${HEALTH_TYPES}`, recordedAt: "ts", detail: "text200?",
      weightKilograms: "measure?", waterMilliliters: "measure?",
      waterLevel: HEALTH_LEVEL, appetiteLevel: HEALTH_LEVEL,
      urinationLevel: HEALTH_LEVEL, stoolStatus: HEALTH_STATUS,
      energyLevel: HEALTH_LEVEL, moodStatus: HEALTH_STATUS,
      createdByID: "id", createdByName: "text60", createdAt: "ts",
    },
  },
  healthV2: {
    path: /^households\/[^/]+\/healthRecords\/[^/]+$/,
    fields: {
      schemaVersion: "version2", petID: "id", petName: "text60",
      type: `enum:${HEALTH_TYPES}`, recordedAt: "ts",
      recordedLocalDate: "date", recordedTimeZoneIdentifier: "zone",
      detail: "text200?", weightKilograms: "measure?",
      waterMilliliters: "measure?",
      waterMeasurementBasis: "enum?:singleIntake|localDayToDate|fullLocalDay",
      waterLevel: HEALTH_LEVEL, appetiteLevel: HEALTH_LEVEL,
      urinationLevel: HEALTH_LEVEL, stoolStatus: HEALTH_STATUS,
      energyLevel: HEALTH_LEVEL, moodStatus: HEALTH_STATUS,
      createdByID: "id", createdByName: "text60", createdAt: "ts",
    },
  },
  handoffTemplate: {
    path: /^households\/[^/]+\/handoff\/current$/,
    fields: {
      schemaVersion: "version1", careInstructions: "text200?",
      emergencyContactName: "text60?", emergencyContactPhone: "text60?",
      veterinaryHospitalName: "text60?", veterinaryHospitalPhone: "text60?",
      revision: "count", updatedByID: "id", updatedByName: "text60",
      updatedAt: "ts",
    },
  },
  handoffVersion: {
    path: /^households\/[^/]+\/handoffVersions\/[^/]+$/,
    fields: {
      schemaVersion: "version1", id: "id", sourceHandoffRevision: "count",
      careInstructions: "text200?", emergencyContactName: "text60?",
      emergencyContactPhone: "text60?", veterinaryHospitalName: "text60?",
      veterinaryHospitalPhone: "text60?", updatedByID: "id",
      updatedByName: "text60", updatedAt: "ts", materializedAt: "ts",
    },
  },
  handoffSession: {
    path: /^households\/[^/]+\/handoffSessions\/[^/]+$/,
    fields: {
      schemaVersion: "version1", id: "id", versionID: "id",
      handoffRevisionSnapshot: "count", creatorID: "id",
      creatorName: "text60", recipientID: "id", recipientName: "text60",
      timeZoneIdentifierSnapshot: "zone", plannedStartAt: "ts",
      plannedEndAt: "ts",
      status: "enum:offered|accepted|declined|cancelled|closed",
      offeredAt: "ts", acceptedByID: "id?", acceptedByName: "text60?",
      acceptedAt: "ts?", declinedByID: "id?", declinedByName: "text60?",
      declinedAt: "ts?", cancelledByID: "id?", cancelledByName: "text60?",
      cancelledAt: "ts?", closedByID: "id?", closedByName: "text60?",
      closedAt: "ts?", resolutionReason: "enum?:ownerRecovery|windowElapsed",
      revision: "count",
    },
  },
  responsibilityTransfer: {
    path: /^households\/[^/]+\/taskResponsibilityTransfers\/[^/]+$/,
    fields: {
      schemaVersion: "version1", id: "id", taskID: "id",
      kind: "enum:reassign|takeover",
      status: "enum:pending|accepted|declined|cancelled|superseded",
      requestedByID: "id", requestedByName: "text60", consentByID: "id",
      consentByName: "text60", responsibilityFromID: "id?",
      responsibilityFromName: "text60?", responsibilityToID: "id",
      responsibilityToName: "text60", taskRevisionAtProposal: "count",
      createdAt: "ts", resolvedByID: "id?", resolvedByName: "text60?",
      resolvedAt: "ts?", resultingTaskRevision: "count?", revision: "count",
    },
  },
  responsibilityPointer: {
    path: /^households\/[^/]+\/taskResponsibilityState\/[^/]+$/,
    fields: {
      schemaVersion: "version1", taskID: "id", transferID: "id",
      taskRevisionAtProposal: "count", createdAt: "ts",
    },
  },
  collaborationLedger: {
    path: /^households\/[^/]+\/collaborationEvents\/[0-9a-f]{64}$/,
    fields: {
      schemaVersion: "version2",
      sourceType: "enum:task|taskResponsibilityTransfer|handoffSession",
      sourceID: "id", sourceRevision: "count", action: "action",
      actorID: "id", actorName: "text50", responsibilityFromID: "id?",
      responsibilityFromName: "text50?", responsibilityToID: "id?",
      responsibilityToName: "text50?", handoffCreatorID: "id?",
      handoffCreatorName: "text50?", handoffRecipientID: "id?",
      handoffRecipientName: "text50?", requestID: "id?", petID: "id?",
      petName: "text60?", taskTitle: "text120?",
      taskCategory: "enum?:feeding|walking|medication|grooming|other",
      taskPriority: "enum?:normal|urgent", taskDueTime: "ts?",
      stateAfter: "enum?:unclaimed|claimed|completed",
      handoffStatus: "enum?:offered|accepted|declined|cancelled|closed",
      occurredAt: "ts", recordedAt: "ts",
    },
  },
  collaborationReadCursor: {
    path: /^households\/[^/]+\/members\/[^/]+\/updateState\/collaboration$/,
    fields: {
      schemaVersion: "version1", occurredAt: "ts", eventID: "hex64",
      updatedAt: "ts",
    },
  },
  notificationPreference: {
    path: /^users\/[^/]+\/householdNotificationPreferences\/[^/]+$/,
    fields: {
      schemaVersion: "version1", uid: "id", householdID: "id",
      memberJoinedAtSnapshot: "ts", medicationRemindersEnabled: "bool",
      assignmentAlertsEnabled: "bool", urgentAlertsEnabled: "bool",
      pushEnabled: "bool", backupForMemberIDs: "ids",
      quietHoursEnabled: "bool", quietStartMinute: "dayMinute",
      quietEndMinute: "dayMinute", summaryEnabled: "bool",
      summaryMinute: "dayMinute", timeZoneIdentifierSnapshot: "zone",
      revision: "count", createdAt: "ts", updatedAt: "ts",
    },
  },
  notificationInbox: {
    path: /^users\/[^/]+\/notificationInbox\/[0-9a-f]{64}$/,
    fields: {
      schemaVersion: "version1", id: "hex64", householdID: "id",
      recipientID: "id", recipientJoinedAtSnapshot: "ts",
      category: "enum:medication|assignment|urgent|summary",
      level: "enum:due|overdue15|overdue30|directAssignment|" +
        "responsibilityProposal|handoffOffer|urgentUnclaimed|burstSummary|" +
        "dailySummary",
      routeReason: "enum:responsible|backup|medicationOptIn|directTarget|" +
        "handoffRecipient|urgentOptIn|summary",
      sourceType: "enum:medicationOccurrence|task|taskResponsibilityTransfer|" +
        "handoffSession|notificationDigest",
      sourceID: "id", sourcePath: "sourcePath", sourceRevision: "count",
      preferenceRevision: "count", status: "enum:active|cancelled",
      availableAt: "ts", expiresAt: "ts", nextDispatchAt: "ts?",
      coalescingKey: "text60?",
      cancelReason: "enum?:sourceChanged|membershipEnded|policyChanged|" +
        "expired|superseded",
      cancelledAt: "ts?", createdAt: "ts", updatedAt: "ts",
    },
  },
  notificationReadCursor: {
    path: /^users\/[^/]+\/notificationInboxState\/[^/]+$/,
    fields: {
      schemaVersion: "version1", householdID: "id",
      recipientJoinedAtSnapshot: "ts", createdAt: "ts", intentID: "hex64",
      updatedAt: "ts",
    },
  },
  notificationDelivery: {
    path: /^users\/[^/]+\/notificationDeliveries\/[0-9a-f]{64}$/,
    fields: {
      schemaVersion: "version2", id: "hex64", intentID: "hex64",
      householdID: "id", recipientID: "id", recipientJoinedAtSnapshot: "ts",
      installationHash: "hex64",
      status: "enum:queued|attempting|providerAccepted|providerUnknown|" +
        "retryableFailure|permanentFailure|cancelled|expired",
      attemptCount: "attempts", nextAttemptAt: "ts?", leaseID: "id?",
      leaseExpiresAt: "ts?", providerRequestStartedAt: "ts?",
      providerAcceptedAt: "ts?", providerUnknownAt: "ts?", terminalAt: "ts?",
      safeErrorCode: "enum?:providerRejected|leaseExpired|providerAmbiguous|" +
        "providerPermanent|installationRemoved",
      createdAt: "ts", updatedAt: "ts",
    },
  },
});

const SKIP_REASON_CODES = new Set([
  "petRefused", "vomited", "unavailable", "vetInstruction", "other",
]);

const LEDGER_ACTIONS = new Set([
  "taskCreated", "taskRequested", "taskClaimed", "taskAccepted",
  "taskDeclined", "taskCancelled", "taskCompleted", "taskReleased",
  "taskReassignRequested", "taskTakeoverRequested", "taskTransferAccepted",
  "taskTransferDeclined", "taskTransferCancelled", "taskTransferSuperseded",
  "handoffSessionOffered", "handoffSessionAccepted", "handoffSessionDeclined",
  "handoffSessionCancelled", "handoffSessionClosed",
]);

export function validatePreservationSeed(seed) {
  assertEnvelope(seed);
  const byType = new Map();
  for (const sentinel of seed.sentinels) {
    assertSentinelShape(sentinel);
    byType.set(sentinel.type, sentinel);
  }
  assertReferences(byType);
  return true;
}

export function createPreservationManifest(seed, key) {
  validatePreservationSeed(seed);
  assertKey(key);
  const sentinels = [...seed.sentinels]
    .sort((left, right) => left.type.localeCompare(right.type))
    .map((sentinel) => ({
      type: sentinel.type,
      pathPseudonym: hmac(key, sentinel.path),
      contentFingerprint: hmac(key, stableStringify(sentinel.data)),
    }));
  const schemaVersionCounts = {};
  for (const sentinel of seed.sentinels) {
    const version = sentinel.data.schemaVersion;
    const keyName = Number.isInteger(version) ? String(version) : "missing";
    schemaVersionCounts[keyName] = (schemaVersionCounts[keyName] ?? 0) + 1;
  }
  const semanticProjection = projectSemantics(seed.sentinels);
  return {
    schemaVersion: 1,
    environment: "emulator",
    projectID: "demo-copaw",
    sentinelCount: sentinels.length,
    pathCount: sentinels.length,
    semanticFingerprintCount: sentinels.length,
    schemaVersionCounts: Object.fromEntries(
      Object.entries(schemaVersionCounts).sort(([left], [right]) =>
        left.localeCompare(right)
      ),
    ),
    sentinels,
    semanticProjection,
    semanticProjectionFingerprint: hmac(key, stableStringify(semanticProjection)),
    manifestFingerprint: hmac(key, stableStringify(sentinels)),
  };
}

export function reconcilePreservationManifests(before, after) {
  const beforeValue = Buffer.from(stableStringify(before));
  const afterValue = Buffer.from(stableStringify(after));
  if (beforeValue.length !== afterValue.length ||
      !timingSafeEqual(beforeValue, afterValue)) {
    throw new Error("LT7 preservation manifest changed after reconciliation.");
  }
  return true;
}

// The projection carries only counts. Report denominators stay separate from
// the collaboration ledger and the notification inbox on purpose: neither is a
// report source, and the manifest must be able to prove they were not merged.
function projectSemantics(sentinels) {
  const byType = new Map(sentinels.map((item) => [item.type, item.data]));
  const healthRecords = ["healthV1", "healthV2"]
    .map((type) => byType.get(type))
    .filter((data) => data != null);
  const waterBasisCounts = Object.fromEntries(
    Object.values(WATER_BASIS_BUCKETS).map((bucket) => [bucket, 0]),
  );
  for (const record of healthRecords) {
    const bucket = record.schemaVersion === 1
      ? WATER_BASIS_BUCKETS.legacyUnspecified
      : WATER_BASIS_BUCKETS[record.waterMeasurementBasis] ??
        WATER_BASIS_BUCKETS.legacyUnspecified;
    waterBasisCounts[bucket] += 1;
  }
  const tasks = ["task", "taskCompleted"]
    .map((type) => byType.get(type))
    .filter((data) => data != null);
  const occurrence = byType.get("medicationOccurrence");
  const outcome = occurrence?.outcomeStatus ?? null;
  return {
    health: {
      recordCount: healthRecords.length,
      legacyRecordCount: healthRecords
        .filter((record) => record.schemaVersion === 1).length,
      dailyIdentityCount: healthRecords
        .filter((record) => typeof record.recordedLocalDate === "string").length,
      waterBasisCounts,
    },
    report: {
      taskCount: tasks.length,
      taskCompletedCount: tasks.filter((task) =>
        task.status === "completed" && task.completedAt != null).length,
      medicationOccurrenceCount: occurrence == null ? 0 : 1,
      medicationAdministeredCount: outcome === "administered" ? 1 : 0,
      medicationSkippedCount: outcome === "skipped" ? 1 : 0,
      medicationUnresolvedCount: outcome === "unresolved" ? 1 : 0,
      ledgerExcludedCount: byType.has("collaborationLedger") ? 1 : 0,
      collaborationCursorCount: byType.has("collaborationReadCursor") ? 1 : 0,
      notificationExcludedCount: [
        "notificationInbox", "notificationReadCursor", "notificationDelivery",
      ].filter((type) => byType.has(type)).length,
      notificationPolicyCount: byType.has("notificationPreference") ? 1 : 0,
    },
  };
}

function assertEnvelope(seed) {
  if (seed?.schemaVersion !== 1 || seed.environment !== "emulator" ||
      seed.projectID !== "demo-copaw" || !Array.isArray(seed.sentinels)) {
    throw new Error("LT7 preservation seed is malformed.");
  }
  const types = seed.sentinels.map((item) => item?.type);
  if (new Set(types).size !== types.length ||
      types.length !== REQUIRED_PRESERVATION_SENTINELS.length ||
      REQUIRED_PRESERVATION_SENTINELS.some((type) => !types.includes(type))) {
    throw new Error("LT7 preservation seed does not match the required sentinels.");
  }
}

function assertSentinelShape(sentinel) {
  const type = sentinel?.type;
  const spec = SENTINEL_SPECS[type];
  if (spec == null) {
    throw new Error(`LT7 preservation sentinel ${type} has no frozen schema.`);
  }
  const { path, data } = sentinel;
  if (typeof path !== "string" || !spec.path.test(path)) {
    throw new Error(`LT7 preservation sentinel ${type} has a non-canonical path.`);
  }
  if (data == null || typeof data !== "object" || Array.isArray(data)) {
    throw new Error(`LT7 preservation sentinel ${type} is malformed.`);
  }
  const expected = Object.keys(spec.fields).sort();
  const actual = Object.keys(data).sort();
  if (expected.length !== actual.length ||
      expected.some((name, index) => name !== actual[index])) {
    throw new Error(
      `LT7 preservation sentinel ${type} does not use the exact field set.`,
    );
  }
  for (const [name, kind] of Object.entries(spec.fields)) {
    if (!matchesKind(data[name], kind)) {
      throw new Error(
        `LT7 preservation sentinel ${type} field ${name} is malformed.`,
      );
    }
  }
}

function matchesKind(value, kind) {
  if (kind.startsWith("enum?:")) {
    return value == null || kind.slice(6).split("|").includes(value);
  }
  if (kind.startsWith("enum:")) {
    return kind.slice(5).split("|").includes(value);
  }
  if (kind.endsWith("?")) {
    return value == null || matchesKind(value, kind.slice(0, -1));
  }
  if (kind.startsWith("text")) {
    const maximum = Number(kind.slice(4));
    return typeof value === "string" && value.trim().length > 0 &&
      value.length <= maximum;
  }
  switch (kind) {
    case "id":
      return typeof value === "string" && value.length > 0 &&
        value.length <= 128 && !value.includes("/");
    case "ids":
      return Array.isArray(value) && value.every((item) => matchesKind(item, "id"));
    case "code":
      return typeof value === "string" && /^[A-Z0-9]{6}$/.test(value);
    case "zone":
      return typeof value === "string" && /^[A-Za-z]+\/[A-Za-z_+-]+$/.test(value) &&
        supportsZone(value);
    case "ts":
      return timestampMillis(value) != null;
    case "date":
      return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value) &&
        !Number.isNaN(Date.parse(`${value}T00:00:00Z`));
    case "bool":
      return typeof value === "boolean";
    case "count":
      return Number.isInteger(value) && value >= 0;
    case "positive":
      return Number.isInteger(value) && value >= 1;
    case "attempts":
      return Number.isInteger(value) && value >= 0 && value <= 3;
    case "hour":
      return Number.isInteger(value) && value >= 0 && value <= 23;
    case "minute":
      return Number.isInteger(value) && value >= 0 && value <= 59;
    case "dayMinute":
      return Number.isInteger(value) && value >= 0 && value <= 1439;
    case "measure":
      return typeof value === "number" && Number.isFinite(value) && value >= 0;
    case "weekdays":
      return Array.isArray(value) && value.length > 0 && value.length <= 7 &&
        new Set(value).size === value.length &&
        value.every((item) => Number.isInteger(item) && item >= 1 && item <= 7);
    case "slots":
      return Array.isArray(value) && value.length > 0 && value.every(validSlot);
    case "slot":
      return typeof value === "string" && /^[a-zA-Z0-9]{1,32}$/.test(value);
    case "hex64":
      return typeof value === "string" && /^[0-9a-f]{64}$/.test(value);
    case "sourcePath":
      return typeof value === "string" && /^[A-Za-z]+\/[^/]+$/.test(value);
    case "action":
      return LEDGER_ACTIONS.has(value);
    case "version1":
      return value === 1;
    case "version2":
      return value === 2;
    default:
      return false;
  }
}

function validSlot(slot) {
  if (slot == null || typeof slot !== "object" || Array.isArray(slot)) {
    return false;
  }
  const keys = Object.keys(slot).sort().join(",");
  return keys === "doseText,hour,instructions,minute,slotID" &&
    matchesKind(slot.slotID, "slot") && matchesKind(slot.hour, "hour") &&
    matchesKind(slot.minute, "minute") && matchesKind(slot.doseText, "text120") &&
    matchesKind(slot.instructions, "text200?");
}

function assertReferences(byType) {
  const document = (type) => byType.get(type).data;
  const identifier = (type) => byType.get(type).path.split("/").at(-1);
  const household = document("household");
  const member = document("member");
  const pet = document("pet");
  const task = document("task");
  const completed = document("taskCompleted");
  const transfer = document("responsibilityTransfer");
  const pointer = document("responsibilityPointer");
  const ledger = document("collaborationLedger");
  const cursor = document("collaborationReadCursor");
  const preference = document("notificationPreference");
  const inbox = document("notificationInbox");
  const inboxCursor = document("notificationReadCursor");
  const delivery = document("notificationDelivery");
  const plan = document("medicationPlan");
  const version = document("medicationVersion");
  const occurrence = document("medicationOccurrence");
  const legacyHealth = document("healthV1");
  const health = document("healthV2");
  const template = document("handoffTemplate");
  const handoffVersion = document("handoffVersion");
  const session = document("handoffSession");
  const householdID = identifier("household");

  for (const type of REQUIRED_PRESERVATION_SENTINELS) {
    const path = byType.get(type).path;
    if (path.startsWith("households/") &&
        path.split("/")[1] !== householdID) {
      fail(type, "is stored under another household");
    }
  }
  check("household", household.id === householdID, "path and id disagree");
  check("member", member.id === identifier("member"), "path and id disagree");
  check("member", member.inviteCode === household.inviteCode,
    "does not carry the household invite code");
  check("invite", identifier("invite") === household.inviteCode &&
    document("invite").householdID === householdID,
    "does not resolve to this household");
  check("pet", pet.id === identifier("pet"), "path and id disagree");

  for (const [type, data] of [["task", task], ["taskCompleted", completed]]) {
    check(type, data.id === byType.get(type).path.split("/").at(-1),
      "path and id disagree");
    check(type, data.petID === pet.id && data.petName === pet.name,
      "does not match the pet snapshot");
    check(type, (data.kind === "routine") === (data.routineID != null),
      "routine identity and kind disagree");
    check(type, data.status !== "claimed" ||
      (data.assigneeID != null && data.assigneeName != null &&
        data.claimedAt != null), "claimed overlay is incomplete");
    check(type, (data.status === "completed") === (data.completedAt != null) &&
      (data.completedAt == null) === (data.completedByID == null) &&
      (data.completedByID == null) === (data.completedBy == null),
      "completion overlay is inconsistent");
    check(type, data.completedAt == null ||
      timestampMillis(data.completedAt) >= timestampMillis(data.createdAt),
      "completion precedes creation");
  }
  check("task", task.status === "claimed",
    "must stay the live source of the pending transfer");
  check("taskCompleted", completed.status === "completed" &&
    completed.assigneeID != null, "must be the completed report source");
  check("taskCompleted", completed.id !== task.id,
    "must not reuse the live task identity");

  check("routine", document("routine").petID === pet.id &&
    document("routine").timeZoneIdentifier === household.timeZoneIdentifier,
    "does not match the pet and household timezone");

  check("medicationPlan", plan.id === identifier("medicationPlan") &&
    plan.petID === pet.id, "does not match its path and pet");
  check("medicationPlan",
    plan.currentScheduleVersionID === version.id &&
    plan.currentScheduleVersion === version.version,
    "does not point at the frozen schedule version");
  check("medicationVersion", version.id === identifier("medicationVersion") &&
    version.medicationID === plan.id, "does not belong to the plan");
  check("medicationVersion",
    version.id === `v${String(version.version).padStart(6, "0")}`,
    "identity does not encode its version number");
  check("medicationVersion", version.effectiveUntilLocalDate == null ||
    version.effectiveUntilLocalDate > version.effectiveFromLocalDate,
    "effective interval is not a half-open forward range");
  check("medicationVersion", (version.closedAt == null) ===
    (version.closedByID == null), "closure overlay is inconsistent");
  check("medicationOccurrence",
    occurrence.id === identifier("medicationOccurrence") &&
    occurrence.id === [
      occurrence.medicationID, occurrence.scheduleVersionID,
      occurrence.localDate, occurrence.slotID,
    ].join("_"), "identity does not encode its schedule coordinates");
  check("medicationOccurrence", occurrence.medicationID === plan.id &&
    occurrence.scheduleVersionID === version.id &&
    occurrence.scheduleVersion === version.version &&
    occurrence.timeZoneIdentifier === version.timeZoneIdentifier,
    "does not match the frozen schedule version");
  check("medicationOccurrence",
    version.slots.some((slot) => slot.slotID === occurrence.slotID &&
      slot.doseText === occurrence.doseText &&
      slot.instructions === occurrence.instructions),
    "does not match a frozen schedule slot");
  check("medicationOccurrence",
    localDateInZone(occurrence.dueAt, occurrence.timeZoneIdentifier) ===
      occurrence.localDate,
    "due instant does not fall on its household-local date");
  check("medicationOccurrence", (occurrence.responsibilityStatus === "claimed") ===
    (occurrence.responsibleByID != null) &&
    (occurrence.responsibleByID == null) === (occurrence.claimedAt == null),
    "responsibility overlay is inconsistent");
  check("medicationOccurrence", (occurrence.outcomeStatus === "unresolved") ===
    (occurrence.outcomeAt == null) &&
    (occurrence.outcomeAt == null) === (occurrence.outcomeByID == null),
    "outcome overlay is inconsistent");
  check("medicationOccurrence", (occurrence.outcomeStatus === "skipped") ===
    (occurrence.skippedReasonCode != null),
    "skip reason and skipped outcome disagree");
  check("medicationOccurrence", occurrence.skippedReasonCode == null ||
    SKIP_REASON_CODES.has(occurrence.skippedReasonCode),
    "carries an unknown skip reason code");
  check("medicationOccurrence", occurrence.skippedReasonNote == null ||
    occurrence.skippedReasonCode === "other",
    "carries a skip note without the free-text reason code");

  check("healthV1", legacyHealth.petID === pet.id,
    "does not match the pet snapshot");
  check("healthV2", health.petID === pet.id, "does not match the pet snapshot");
  check("healthV2",
    localDateInZone(health.recordedAt, health.recordedTimeZoneIdentifier) ===
      health.recordedLocalDate,
    "local date is not derived from its trusted instant and zone");
  check("healthV2", health.waterMeasurementBasis === expectedWaterBasis(health),
    "water basis does not follow the frozen type rule");
  check("healthV2", health.type !== "dailyCheckIn" ||
    [health.waterLevel, health.appetiteLevel, health.urinationLevel,
      health.stoolStatus, health.energyLevel, health.moodStatus]
      .every((answer) => answer != null),
    "daily check-in is missing typed answers");

  check("handoffVersion", handoffVersion.id === identifier("handoffVersion") &&
    handoffVersion.id ===
      `v${String(handoffVersion.sourceHandoffRevision).padStart(6, "0")}`,
    "identity does not encode its source revision");
  check("handoffVersion",
    handoffVersion.sourceHandoffRevision === template.revision &&
    handoffVersion.careInstructions === template.careInstructions &&
    handoffVersion.emergencyContactName === template.emergencyContactName &&
    handoffVersion.emergencyContactPhone === template.emergencyContactPhone &&
    handoffVersion.veterinaryHospitalName === template.veterinaryHospitalName &&
    handoffVersion.veterinaryHospitalPhone === template.veterinaryHospitalPhone,
    "is not an exact snapshot of the current template revision");
  check("handoffSession", session.id === identifier("handoffSession") &&
    session.versionID === handoffVersion.id &&
    session.handoffRevisionSnapshot === handoffVersion.sourceHandoffRevision,
    "is not pinned to the immutable version it offered");
  check("handoffSession",
    session.timeZoneIdentifierSnapshot === household.timeZoneIdentifier,
    "does not carry the household timezone snapshot");
  check("handoffSession",
    timestampMillis(session.plannedEndAt) >
      timestampMillis(session.plannedStartAt),
    "planned window is not a forward half-open interval");
  check("handoffSession", session.creatorID !== session.recipientID,
    "creator and recipient are the same member");
  check("handoffSession", (session.acceptedAt != null) ===
    (session.acceptedByID != null) &&
    (session.declinedAt != null) === (session.declinedByID != null) &&
    (session.cancelledAt != null) === (session.cancelledByID != null) &&
    (session.closedAt != null) === (session.closedByID != null),
    "transition overlays are inconsistent");
  check("handoffSession", session.status !== "closed" ||
    (session.closedAt != null && session.acceptedAt != null),
    "closed session was never accepted");
  check("handoffSession", session.status !== "accepted" ||
    (session.acceptedAt != null && session.closedAt == null),
    "accepted session is already closed");

  check("responsibilityTransfer", transfer.id === identifier("responsibilityTransfer") &&
    transfer.taskID === task.id &&
    transfer.taskRevisionAtProposal === task.revision,
    "does not match the live task it proposes");
  check("responsibilityTransfer",
    transfer.responsibilityFromID === task.assigneeID &&
    transfer.responsibilityFromName === task.assigneeName,
    "does not snapshot the current responsible member");
  check("responsibilityTransfer", transfer.kind !== "reassign" ||
    (transfer.consentByID === transfer.responsibilityToID &&
      transfer.requestedByID === transfer.responsibilityFromID),
    "reassign consent is not owed by the receiving member");
  check("responsibilityTransfer", transfer.kind !== "takeover" ||
    (transfer.consentByID === transfer.responsibilityFromID &&
      transfer.requestedByID === transfer.responsibilityToID),
    "takeover consent is not owed by the current responsible member");
  check("responsibilityTransfer", (transfer.status === "pending") ===
    (transfer.resolvedAt == null) &&
    (transfer.resolvedAt == null) === (transfer.resolvedByID == null),
    "resolution overlay is inconsistent");
  check("responsibilityTransfer", transfer.status === "accepted" ||
    transfer.resultingTaskRevision == null,
    "records a resulting task revision without acceptance");
  check("responsibilityPointer",
    identifier("responsibilityPointer") === transfer.taskID &&
    pointer.taskID === transfer.taskID &&
    pointer.transferID === transfer.id &&
    pointer.taskRevisionAtProposal === transfer.taskRevisionAtProposal &&
    sameInstant(pointer.createdAt, transfer.createdAt),
    "does not bind one-to-one to the pending transfer");
  check("responsibilityPointer", transfer.status === "pending",
    "exists without a pending transfer");

  check("collaborationLedger", ledger.sourceType !== "taskResponsibilityTransfer" ||
    (ledger.sourceID === transfer.id &&
      ledger.sourceRevision === transfer.revision &&
      ledger.requestID === transfer.id),
    "does not match its authoritative transfer source");
  check("collaborationLedger",
    identifier("collaborationLedger") === digestHex(
      `taskResponsibilityTransfers/${ledger.sourceID}|${ledger.sourceRevision}|` +
        `${ledger.action}`,
    ), "identity is not the deterministic source revision digest");
  check("collaborationLedger", ledger.actorID === transfer.requestedByID &&
    ledger.responsibilityToID === transfer.responsibilityToID &&
    ledger.responsibilityFromID === transfer.responsibilityFromID,
    "does not match the transfer participants");
  check("collaborationLedger", ledger.taskCategory !== "medication" ||
    ledger.taskTitle === "Medication care",
    "copies a medication task title into the ledger");
  check("collaborationLedger",
    timestampMillis(ledger.recordedAt) >= timestampMillis(ledger.occurredAt),
    "was recorded before it occurred");
  check("collaborationReadCursor",
    byType.get("collaborationReadCursor").path.split("/")[3] === member.id,
    "belongs to another member");
  check("collaborationReadCursor",
    cursor.eventID === identifier("collaborationLedger") &&
    sameInstant(cursor.occurredAt, ledger.occurredAt),
    "does not point at an existing event with its trusted order");

  check("notificationPreference", preference.uid === member.id &&
    preference.householdID === householdID &&
    sameInstant(preference.memberJoinedAtSnapshot, member.joinedAt),
    "does not match the member membership epoch");
  check("notificationPreference",
    preference.timeZoneIdentifierSnapshot === household.timeZoneIdentifier,
    "does not carry the household timezone snapshot");
  check("notificationPreference",
    !preference.backupForMemberIDs.includes(preference.uid),
    "lists its own member as a backup target");
  check("notificationInbox", inbox.recipientID === member.id &&
    inbox.householdID === householdID &&
    sameInstant(inbox.recipientJoinedAtSnapshot, member.joinedAt),
    "does not match the recipient membership epoch");
  check("notificationInbox",
    inbox.sourcePath === `taskResponsibilityTransfers/${transfer.id}` &&
    inbox.sourceID === transfer.id &&
    inbox.sourceRevision === transfer.revision,
    "does not match its authoritative transfer source");
  // Either side of this pair can drift, so the failure names both documents.
  check("notificationPreference",
    inbox.preferenceRevision === preference.revision,
    "and notificationInbox disagree about the routed policy revision");
  check("notificationInbox", inbox.id === identifier("notificationInbox") &&
    inbox.id === digestHex(stableStringify([
      inbox.householdID, inbox.sourceType, inbox.sourcePath,
      inbox.sourceRevision, inbox.level, inbox.recipientID,
      Math.floor(timestampMillis(inbox.recipientJoinedAtSnapshot) / 1000),
      (timestampMillis(inbox.recipientJoinedAtSnapshot) % 1000) * 1e6,
    ])), "identity is not the deterministic routing digest");
  check("notificationInbox",
    timestampMillis(inbox.expiresAt) > timestampMillis(inbox.availableAt),
    "expiry does not follow availability");
  check("notificationInbox", (inbox.status === "cancelled") ===
    (inbox.cancelledAt != null) &&
    (inbox.cancelledAt == null) === (inbox.cancelReason == null),
    "cancellation overlay is inconsistent");
  check("notificationInbox", inbox.status !== "cancelled" ||
    inbox.nextDispatchAt == null,
    "still schedules dispatch after cancellation");
  check("notificationReadCursor", inboxCursor.householdID === householdID &&
    sameInstant(inboxCursor.recipientJoinedAtSnapshot,
      member.joinedAt), "does not match the recipient membership epoch");
  check("notificationReadCursor", inboxCursor.intentID === inbox.id &&
    sameInstant(inboxCursor.createdAt, inbox.createdAt),
    "does not point at an existing intent with its trusted order");
  check("notificationDelivery", delivery.intentID === inbox.id &&
    delivery.householdID === householdID &&
    delivery.recipientID === member.id &&
    sameInstant(delivery.recipientJoinedAtSnapshot, member.joinedAt),
    "does not belong to the recipient intent");
  check("notificationDelivery",
    delivery.id === identifier("notificationDelivery") &&
    delivery.id === digestHex(stableStringify([
      delivery.intentID, delivery.installationHash,
    ])), "identity is not the deterministic installation digest");
  check("notificationDelivery", validDeliveryState(delivery),
    "attempt, lease, and provider overlays are inconsistent");
  const userSegments = ["notificationPreference", "notificationInbox",
    "notificationReadCursor", "notificationDelivery"]
    .map((type) => byType.get(type).path.split("/")[1]);
  check("notificationDelivery",
    new Set(userSegments).size === 1 && userSegments[0] === member.id,
    "private notification documents are split across users");
}

function validDeliveryState(delivery) {
  const noResults = delivery.providerAcceptedAt == null &&
    delivery.providerUnknownAt == null && delivery.terminalAt == null;
  if (delivery.status === "queued") {
    return delivery.attemptCount <= 2 && delivery.nextAttemptAt != null &&
      delivery.leaseID == null && delivery.leaseExpiresAt == null &&
      delivery.providerRequestStartedAt == null && noResults &&
      delivery.safeErrorCode == null;
  }
  if (delivery.status === "attempting") {
    return delivery.attemptCount >= 1 && delivery.nextAttemptAt == null &&
      delivery.leaseID != null && delivery.leaseExpiresAt != null &&
      noResults && delivery.safeErrorCode == null;
  }
  if (delivery.status === "retryableFailure") {
    return delivery.attemptCount >= 1 && delivery.attemptCount <= 2 &&
      delivery.nextAttemptAt != null && delivery.leaseID == null &&
      noResults && delivery.safeErrorCode != null;
  }
  if (delivery.status === "providerAccepted") {
    return delivery.attemptCount >= 1 && delivery.providerAcceptedAt != null &&
      sameInstant(delivery.providerAcceptedAt, delivery.terminalAt) &&
      delivery.providerUnknownAt == null && delivery.safeErrorCode == null;
  }
  if (delivery.status === "providerUnknown") {
    return delivery.attemptCount >= 1 && delivery.providerUnknownAt != null &&
      sameInstant(delivery.providerUnknownAt, delivery.terminalAt) &&
      delivery.providerAcceptedAt == null &&
      delivery.safeErrorCode === "providerAmbiguous";
  }
  return delivery.terminalAt != null && delivery.nextAttemptAt == null &&
    delivery.leaseID == null;
}

function expectedWaterBasis(record) {
  if (record.type === "dailyCheckIn") {
    return record.waterMilliliters == null ? null : "localDayToDate";
  }
  return record.type === "waterIntake" ? "singleIntake" : null;
}

function check(type, condition, reason) {
  if (!condition) fail(type, reason);
}

function fail(type, reason) {
  throw new Error(`LT7 preservation sentinel ${type} ${reason}.`);
}

function assertKey(key) {
  if (typeof key !== "string" || key.length < 16) {
    throw new Error("LT7 receipt key must contain at least 16 characters.");
  }
}

// Sentinel timestamps survive the Emulator round trip either as the portable
// fixture marker or as the decoded ISO instant, so both forms are accepted.
export function timestampMillis(value) {
  const iso = typeof value === "string"
    ? value
    : (value != null && typeof value === "object" &&
        value.__type === "timestamp" ? value.value : null);
  if (typeof iso !== "string" ||
      !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?Z$/.test(iso)) {
    return null;
  }
  const millis = Date.parse(iso);
  return Number.isFinite(millis) ? millis : null;
}

function sameInstant(left, right) {
  const leftMillis = timestampMillis(left);
  return leftMillis != null && leftMillis === timestampMillis(right);
}

export function localDateInZone(value, zone) {
  const millis = timestampMillis(value);
  if (millis == null || !supportsZone(zone)) return null;
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: zone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date(millis));
}

function supportsZone(zone) {
  try {
    new Intl.DateTimeFormat("en-CA", { timeZone: zone });
    return true;
  } catch {
    return false;
  }
}

function digestHex(value) {
  return createHash("sha256").update(value).digest("hex");
}

function hmac(key, value) {
  return createHmac("sha256", key).update(value).digest("hex");
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
