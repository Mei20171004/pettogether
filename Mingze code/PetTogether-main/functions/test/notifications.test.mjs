import assert from "node:assert/strict";
import { test } from "node:test";

import { plannedMedicationReminderWindows } from "../notifications.js";

test("legacy notification module retains only pure medication planning", () => {
  const due = new Date("2026-08-16T23:00:00.000Z");
  const planned = plannedMedicationReminderWindows({
    medicationID: "medication-1",
    versionData: {
      id: "v000001",
      timeZoneIdentifier: "Asia/Tokyo",
      effectiveFromLocalDate: "2026-08-01",
      effectiveUntilLocalDate: null,
      weekdays: [2],
      slots: [{ slotID: "morning", hour: 8, minute: 0 }],
    },
    now: due,
  });
  assert.deepEqual(planned, [{
    occurrenceID: "medication-1_v000001_2026-08-17_morning",
    level: "due",
    dueAtMilliseconds: due.getTime(),
  }]);
});

test("legacy pure planner rejects malformed schedules and ambiguous DST slots", () => {
  assert.deepEqual(plannedMedicationReminderWindows({
    medicationID: "medication-1", versionData: {}, now: new Date(),
  }), []);
  assert.deepEqual(plannedMedicationReminderWindows({
    medicationID: "medication-1",
    versionData: {
      id: "v000001", timeZoneIdentifier: "America/New_York",
      effectiveFromLocalDate: "2026-01-01", effectiveUntilLocalDate: null,
      weekdays: [1], slots: [{ slotID: "fold", hour: 1, minute: 30 }],
    },
    now: new Date("2026-11-01T05:30:00.000Z"),
  }), []);
});
