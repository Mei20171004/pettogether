import '../models/models.dart';

/// Date/calendar helpers shared by the store and the mock service.
///
/// Day boundaries use the device-local calendar (see README for the note on
/// cross-timezone households), while `timeZoneIdentifier` is still stored for
/// Firestore compatibility.

/// Converts Dart's weekday (1=Mon..7=Sun) to the Calendar/Firestore convention
/// used throughout the app (1=Sun..7=Sat).
int swiftWeekday(DateTime date) => (date.weekday % 7) + 1;

/// Local midnight for [date].
DateTime startOfDay(DateTime date) => DateTime(date.year, date.month, date.day);

/// The stable occurrence id for a routine expanded onto [date]:
/// `<routineID>_yyyy-MM-dd`.
String occurrenceID(CareRoutine routine, DateTime date) {
  final d = startOfDay(date);
  final month = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${routine.id}_${d.year.toString().padLeft(4, '0')}-$month-$day';
}

/// The due time for [routine] on [day], or null when the routine does not run
/// on that day.
DateTime? dueTimeForRoutine(CareRoutine routine, DateTime day) {
  if (!routineRunsOn(routine, day)) return null;
  return DateTime(day.year, day.month, day.day, routine.hour, routine.minute);
}

/// Whether [routine] has an occurrence on [day], for every recurrence type.
bool routineRunsOn(CareRoutine routine, DateTime day) {
  final dayStart = startOfDay(day);
  final start = startOfDay(routine.startDate);
  final interval = routine.interval < 1 ? 1 : routine.interval;

  switch (routine.frequency) {
    case CareRoutineFrequency.daily:
      return !dayStart.isBefore(start);

    case CareRoutineFrequency.selectedDays:
      return !dayStart.isBefore(start) &&
          routine.weekdays.contains(swiftWeekday(day));

    case CareRoutineFrequency.intervalDays:
      // Every N days, anchored on startDate.
      return !dayStart.isBefore(start) &&
          dayStart.difference(start).inDays % interval == 0;

    case CareRoutineFrequency.intervalWeeks:
      // Every N weeks, on startDate's weekday.
      return !dayStart.isBefore(start) &&
          dayStart.difference(start).inDays % (interval * 7) == 0;

    case CareRoutineFrequency.intervalMonths:
      // Every N months, anchored on startDate's day-of-month.
      return runsOnMonth(dayStart, start, interval);

    case CareRoutineFrequency.nthWeekday:
      // Monthly on the Nth weekday (interval = 1..4 for 1st..4th, 5 = last).
      final weekday =
          routine.weekdays.isEmpty ? swiftWeekday(day) : routine.weekdays.first;
      return !dayStart.isBefore(start) &&
          isNthWeekdayOfMonth(day, interval, weekday);

    case CareRoutineFrequency.intervalYears:
      // Every N years, anchored on startDate's month + day.
      return !dayStart.isBefore(start) &&
          day.month == start.month &&
          day.day == start.day &&
          (day.year - start.year) % interval == 0;
  }
}

/// True when [day] is the anchor day-of-month in a "every N months" schedule,
/// clamping to the last day of shorter months.
bool runsOnMonth(DateTime day, DateTime start, int interval) {
  if (day.isBefore(start)) return false;
  final months = (day.year - start.year) * 12 + (day.month - start.month);
  if (months % interval != 0) return false;
  if (day.day == start.day) return true;
  return start.day > day.day && day.day == lastDayOfMonth(day);
}

int lastDayOfMonth(DateTime d) => DateTime(d.year, d.month + 1, 0).day;

/// True when [day] is the [nth] occurrence of [weekday] in its month.
/// [nth] is 1..4 for the 1st..4th occurrence, or 5 for the last occurrence.
bool isNthWeekdayOfMonth(DateTime day, int nth, int weekday) {
  if (swiftWeekday(day) != weekday) return false;
  if (nth >= 5) {
    return day.add(const Duration(days: 7)).month != day.month;
  }
  final occurrence = ((day.day - 1) ~/ 7) + 1;
  return occurrence == nth;
}
