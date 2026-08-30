import 'package:timezone/data/latest.dart' as time_zone_data;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';

final class RoutineOccurrenceService {
  RoutineOccurrenceService() {
    _ensureTimeZones();
  }

  static bool _initialized = false;

  static void _ensureTimeZones() {
    if (_initialized) return;
    time_zone_data.initializeTimeZones();
    _initialized = true;
  }

  List<CareTask> tasksForDay({
    required DateTime selectedInstant,
    required String householdTimeZoneIdentifier,
    required Iterable<CareRoutine> routines,
    required Iterable<CareTask> persistedTasks,
  }) {
    final location = tz.getLocation(householdTimeZoneIdentifier);
    final selectedLocal = tz.TZDateTime.from(selectedInstant, location);
    final dayStart = tz.TZDateTime(
      location,
      selectedLocal.year,
      selectedLocal.month,
      selectedLocal.day,
    );
    final nextDay = tz.TZDateTime(
      location,
      selectedLocal.year,
      selectedLocal.month,
      selectedLocal.day + 1,
    );
    final persistedForDay = persistedTasks.where((task) {
      final due = tz.TZDateTime.from(task.dueTime, location);
      return !due.isBefore(dayStart) && due.isBefore(nextDay);
    }).toList();
    final persistedById = <String, CareTask>{
      for (final task in persistedForDay) task.id: task,
    };
    final result = <CareTask>[];
    final includedIds = <String>{};

    for (final routine in routines.where((item) => item.isActive)) {
      final startLocal = tz.TZDateTime.from(routine.startDate, location);
      final routineStartDay = tz.TZDateTime(
        location,
        startLocal.year,
        startLocal.month,
        startLocal.day,
      );
      final appleWeekday = dayStart.weekday % 7 + 1;
      final occursToday =
          routine.frequency == CareRoutineFrequency.daily ||
          routine.weekdays.contains(appleWeekday);
      if (dayStart.isBefore(routineStartDay) || !occursToday) continue;

      final due = tz.TZDateTime(
        location,
        dayStart.year,
        dayStart.month,
        dayStart.day,
        routine.hour,
        routine.minute,
      );
      if (!due.isBefore(nextDay)) continue;
      final occurrenceId = _occurrenceId(routine.id, dayStart);
      final occurrence =
          persistedById[occurrenceId] ??
          CareTask(
            id: occurrenceId,
            title: routine.title,
            category: routine.category,
            dueTime: due.toUtc(),
            kind: CareTaskKind.routine,
            priority: routine.priority,
            routineId: routine.id,
            status: CareTaskStatus.unclaimed,
            assignmentRequest: null,
            assigneeId: null,
            assigneeNameSnapshot: null,
            claimedAt: null,
            createdById: routine.createdById,
            createdBy: routine.createdByNameSnapshot,
            createdAt: routine.startDate,
            completedById: null,
            completedBy: null,
            completedAt: null,
            revision: 0,
            petId: routine.petId,
            petNameSnapshot: routine.petNameSnapshot,
          );
      result.add(occurrence);
      includedIds.add(occurrenceId);
    }

    for (final task in persistedForDay) {
      if (includedIds.add(task.id)) result.add(task);
    }
    result.sort((left, right) {
      final time = left.dueTime.compareTo(right.dueTime);
      return time != 0
          ? time
          : left.title.toLowerCase().compareTo(right.title.toLowerCase());
    });
    return List.unmodifiable(result);
  }

  List<CareTask>? tryTasksForDay({
    required DateTime selectedInstant,
    required String householdTimeZoneIdentifier,
    required Iterable<CareRoutine> routines,
    required Iterable<CareTask> persistedTasks,
  }) {
    try {
      return tasksForDay(
        selectedInstant: selectedInstant,
        householdTimeZoneIdentifier: householdTimeZoneIdentifier,
        routines: routines,
        persistedTasks: persistedTasks,
      );
    } on tz.LocationNotFoundException {
      return null;
    }
  }

  Duration? durationUntilNextDay({
    required DateTime instant,
    required String householdTimeZoneIdentifier,
  }) {
    try {
      final location = tz.getLocation(householdTimeZoneIdentifier);
      final local = tz.TZDateTime.from(instant, location);
      final nextDay = tz.TZDateTime(
        location,
        local.year,
        local.month,
        local.day + 1,
      );
      return nextDay.difference(instant) + const Duration(seconds: 1);
    } on tz.LocationNotFoundException {
      return null;
    }
  }

  static String _occurrenceId(String routineId, tz.TZDateTime day) =>
      '${routineId}_${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}
