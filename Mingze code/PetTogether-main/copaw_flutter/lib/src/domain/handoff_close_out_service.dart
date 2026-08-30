import 'medication_models.dart';
import 'medication_occurrence_service.dart';
import 'models.dart';
import 'routine_occurrence_service.dart';

final class HandoffSourceCounts {
  const HandoffSourceCounts({
    required this.planned,
    required this.completed,
    required this.unresolved,
  });

  final int planned;
  final int completed;
  final int unresolved;
}

final class HandoffMedicationCounts {
  const HandoffMedicationCounts({
    required this.planned,
    required this.administered,
    required this.skipped,
    required this.unresolved,
  });

  final int planned;
  final int administered;
  final int skipped;
  final int unresolved;
}

final class HandoffCloseOutCounts {
  const HandoffCloseOutCounts({required this.care, required this.medication});

  final HandoffSourceCounts care;
  final HandoffMedicationCounts medication;
}

final class HandoffCloseOutBuildException implements Exception {
  const HandoffCloseOutBuildException();
}

final class HandoffCloseOutService {
  const HandoffCloseOutService();

  HandoffCloseOutCounts build({
    required DateTime start,
    required DateTime end,
    required String householdTimeZoneIdentifier,
    required Iterable<CareRoutine> routines,
    required Iterable<CareTask> tasks,
    required Iterable<MedicationScheduleVersion> medicationSchedules,
    required Iterable<MedicationOccurrence> medicationOccurrences,
  }) {
    final startUtc = start.toUtc();
    final endUtc = end.toUtc();
    if (!startUtc.isBefore(endUtc) ||
        endUtc.difference(startUtc) > const Duration(days: 30)) {
      throw const HandoffCloseOutBuildException();
    }
    try {
      final careService = RoutineOccurrenceService();
      final medicationService = MedicationOccurrenceService();
      final plannedCare = <String, CareTask>{};
      final plannedMedication = <String, PlannedMedicationOccurrence>{};
      var cursor = startUtc.subtract(const Duration(days: 1));
      final finalProbe = endUtc.add(const Duration(days: 1));
      while (!cursor.isAfter(finalProbe)) {
        for (final task in careService.tasksForDay(
          selectedInstant: cursor,
          householdTimeZoneIdentifier: householdTimeZoneIdentifier,
          routines: routines,
          persistedTasks: tasks,
        )) {
          if (!task.dueTime.isBefore(startUtc) &&
              task.dueTime.isBefore(endUtc)) {
            plannedCare[task.id] = task;
          }
        }
        for (final occurrence in medicationService.forDay(
          selectedInstant: cursor,
          schedules: medicationSchedules,
          persisted: medicationOccurrences,
        )) {
          if (!occurrence.dueAt.isBefore(startUtc) &&
              occurrence.dueAt.isBefore(endUtc)) {
            plannedMedication[occurrence.id] = occurrence;
          }
        }
        cursor = cursor.add(const Duration(hours: 12));
      }
      final completedCare = plannedCare.values
          .where((task) => task.status == CareTaskStatus.completed)
          .length;
      final administered = plannedMedication.values
          .where(
            (occurrence) =>
                occurrence.outcomeStatus ==
                MedicationOutcomeStatus.administered,
          )
          .length;
      final skipped = plannedMedication.values
          .where(
            (occurrence) =>
                occurrence.outcomeStatus == MedicationOutcomeStatus.skipped,
          )
          .length;
      return HandoffCloseOutCounts(
        care: HandoffSourceCounts(
          planned: plannedCare.length,
          completed: completedCare,
          unresolved: plannedCare.length - completedCare,
        ),
        medication: HandoffMedicationCounts(
          planned: plannedMedication.length,
          administered: administered,
          skipped: skipped,
          unresolved: plannedMedication.length - administered - skipped,
        ),
      );
    } on Object catch (error) {
      if (error is HandoffCloseOutBuildException) rethrow;
      throw const HandoffCloseOutBuildException();
    }
  }
}
