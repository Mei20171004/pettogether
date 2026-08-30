import { DateTime } from "luxon";

const levels = [
  { name: "due", startMinutes: 0, endMinutes: 15 },
  { name: "overdue15", startMinutes: 15, endMinutes: 30 },
  { name: "overdue30", startMinutes: 30, endMinutes: 45 },
];

// Retained only as a deterministic compatibility planner. It performs no reads,
// writes, scheduling, token access, or provider call.
export function plannedMedicationReminderWindows({
  medicationID,
  versionData,
  now,
}) {
  if (!(now instanceof Date) || Number.isNaN(now.getTime())) return [];
  const utcNow = DateTime.fromJSDate(now, { zone: "utc" });
  const zone = versionData?.timeZoneIdentifier;
  if (typeof zone !== "string") return [];
  const localNow = utcNow.setZone(zone);
  if (!localNow.isValid || typeof versionData?.effectiveFromLocalDate !== "string" ||
      !Array.isArray(versionData.weekdays) || !Array.isArray(versionData.slots)) {
    return [];
  }
  const result = [];
  for (const candidateDate of [localNow, localNow.minus({ days: 1 })]) {
    const localDate = candidateDate.toFormat("yyyy-MM-dd");
    if (localDate < versionData.effectiveFromLocalDate ||
        (typeof versionData.effectiveUntilLocalDate === "string" &&
          localDate >= versionData.effectiveUntilLocalDate) ||
        !versionData.weekdays.includes(candidateDate.weekday % 7 + 1)) continue;
    for (const slot of versionData.slots) {
      if (!validSlot(slot)) continue;
      const dueAt = DateTime.fromObject({
        year: candidateDate.year,
        month: candidateDate.month,
        day: candidateDate.day,
        hour: slot.hour,
        minute: slot.minute,
      }, { zone });
      if (!dueAt.isValid || dueAt.getPossibleOffsets().length !== 1) continue;
      const ageMinutes = utcNow.diff(dueAt.toUTC(), "minutes").minutes;
      const level = levels.find((candidate) =>
        ageMinutes >= candidate.startMinutes && ageMinutes < candidate.endMinutes);
      if (level == null) continue;
      result.push({
        occurrenceID:
          `${medicationID}_${versionData.id}_${localDate}_${slot.slotID}`,
        level: level.name,
        dueAtMilliseconds: dueAt.toUTC().toMillis(),
      });
    }
  }
  return result;
}

function validSlot(slot) {
  return slot != null && typeof slot === "object" &&
    typeof slot.slotID === "string" && slot.slotID.length > 0 &&
    Number.isInteger(slot.hour) && slot.hour >= 0 && slot.hour <= 23 &&
    Number.isInteger(slot.minute) && slot.minute >= 0 && slot.minute <= 59;
}
