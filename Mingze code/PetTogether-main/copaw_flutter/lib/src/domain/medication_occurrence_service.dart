import 'package:timezone/data/latest.dart' as time_zone_data;
import 'package:timezone/timezone.dart' as tz;

import 'medication_models.dart';

final class MedicationOccurrenceService {
  MedicationOccurrenceService() {
    if (!_initialized) {
      time_zone_data.initializeTimeZones();
      _initialized = true;
    }
  }

  static bool _initialized = false;

  List<PlannedMedicationOccurrence> forDay({
    required DateTime selectedInstant,
    required Iterable<MedicationScheduleVersion> schedules,
    required Iterable<MedicationOccurrence> persisted,
  }) {
    final persistedById = {for (final item in persisted) item.id: item};
    final result = <PlannedMedicationOccurrence>[];
    for (final schedule in schedules) {
      final location = tz.getLocation(schedule.timeZoneIdentifier);
      final selected = tz.TZDateTime.from(selectedInstant, location);
      final localDate = _date(selected);
      final start = DateTime.parse(schedule.effectiveFromLocalDate);
      final end = schedule.effectiveUntilLocalDate == null
          ? null
          : DateTime.parse(schedule.effectiveUntilLocalDate!);
      final selectedDate = DateTime(
        selected.year,
        selected.month,
        selected.day,
      );
      final weekday = selected.weekday % 7 + 1;
      if (selectedDate.isBefore(start) ||
          (end != null && !selectedDate.isBefore(end)) ||
          !schedule.weekdays.contains(weekday)) {
        continue;
      }
      for (final slot in schedule.slots) {
        final due = tz.TZDateTime(
          location,
          selected.year,
          selected.month,
          selected.day,
          slot.hour,
          slot.minute,
        );
        if (due.hour != slot.hour || due.minute != slot.minute) continue;
        final id =
            '${schedule.medicationId}_${schedule.id}_${localDate}_${slot.slotId}';
        result.add(
          PlannedMedicationOccurrence(
            id: id,
            medicationId: schedule.medicationId,
            scheduleVersionId: schedule.id,
            scheduleVersion: schedule.version,
            slotId: slot.slotId,
            localDate: localDate,
            dueAt: due.toUtc(),
            petId: schedule.petId,
            petNameSnapshot: schedule.petNameSnapshot,
            medicationNameSnapshot: schedule.medicationNameSnapshot,
            doseText: slot.doseText,
            instructions: slot.instructions,
            persisted: persistedById[id],
          ),
        );
      }
    }
    result.sort((left, right) => left.dueAt.compareTo(right.dueAt));
    return List.unmodifiable(result);
  }

  static String _date(tz.TZDateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
