import 'package:timezone/timezone.dart' as tz;

import 'health_models.dart';
import 'medication_models.dart';
import 'models.dart';
import 'plus_features.dart';

/// What one member recorded during the period.
///
/// These are counts of recorded work, not a ranking or an evaluation. A member
/// with a low count may simply not have been on duty, and the summary never
/// says otherwise.
final class CareContribution {
  const CareContribution({
    required this.memberId,
    required this.memberName,
    required this.completedTasks,
    required this.medicationOutcomes,
  });

  final String memberId;
  final String memberName;
  final int completedTasks;
  final int medicationOutcomes;

  int get total => completedTasks + medicationOutcomes;
}

/// Where care coverage has gaps over a period.
///
/// Part of [PlusFeature.careCoverageSummary]. Every number counts records that
/// exist; the summary never infers that something did not happen, only that
/// nothing was recorded.
final class CareCoverageSummary {
  const CareCoverageSummary({
    required this.fromLocalDate,
    required this.toLocalDate,
    required this.medicationDue,
    required this.medicationWithoutOwner,
    required this.medicationWithoutOutcome,
    required this.tasksWithoutOwner,
    required this.daysWithoutHealthRecord,
    required this.contributions,
    required this.isRangeUsable,
  });

  const CareCoverageSummary.unusableRange()
    : fromLocalDate = null,
      toLocalDate = null,
      medicationDue = 0,
      medicationWithoutOwner = 0,
      medicationWithoutOutcome = 0,
      tasksWithoutOwner = 0,
      daysWithoutHealthRecord = const [],
      contributions = const [],
      isRangeUsable = false;

  final String? fromLocalDate;
  final String? toLocalDate;

  /// Doses whose scheduled time has passed within the period.
  final int medicationDue;

  /// Passed doses nobody took responsibility for.
  final int medicationWithoutOwner;

  /// Passed doses with no recorded outcome. Responsibility alone is not an
  /// outcome, so a claimed dose still counts here until it is resolved.
  final int medicationWithoutOutcome;

  /// Tasks whose due time has passed with no assignee.
  final int tasksWithoutOwner;

  /// Household-local days in the period with no health record at all.
  final List<String> daysWithoutHealthRecord;

  final List<CareContribution> contributions;

  /// False when the household timezone could not be used, in which case no
  /// period was determined and every count is zero rather than guessed.
  final bool isRangeUsable;

  bool get hasGaps =>
      medicationWithoutOwner > 0 ||
      medicationWithoutOutcome > 0 ||
      tasksWithoutOwner > 0 ||
      daysWithoutHealthRecord.isNotEmpty;
}

final class CareCoverageService {
  const CareCoverageService();

  CareCoverageSummary build({
    required DateTime endInstant,
    required int rangeDays,
    required String timeZoneIdentifier,
    List<CareTask> tasks = const [],
    List<MedicationOccurrence> medicationOccurrences = const [],
    List<HealthRecord> healthRecords = const [],
  }) {
    final location = _location(timeZoneIdentifier);
    if (location == null || rangeDays < 1) {
      return const CareCoverageSummary.unusableRange();
    }
    final localEnd = tz.TZDateTime.from(endInstant, location);
    final localStart = tz.TZDateTime(
      location,
      localEnd.year,
      localEnd.month,
      localEnd.day - (rangeDays - 1),
    );
    final fromLocalDate = _dateKey(localStart);
    final toLocalDate = _dateKey(localEnd);

    var due = 0;
    var withoutOwner = 0;
    var withoutOutcome = 0;
    final outcomesByMember = <String, (String, int)>{};

    for (final occurrence in medicationOccurrences) {
      if (!_inRange(occurrence.localDate, fromLocalDate, toLocalDate)) continue;
      if (occurrence.dueAt.isAfter(endInstant)) continue;
      due += 1;
      if (occurrence.responsibilityStatus ==
          MedicationResponsibilityStatus.unclaimed) {
        withoutOwner += 1;
      }
      if (occurrence.outcomeStatus == MedicationOutcomeStatus.unresolved) {
        withoutOutcome += 1;
        continue;
      }
      final actorId = occurrence.outcomeById;
      final actorName = occurrence.outcomeByNameSnapshot;
      if (actorId != null && actorName != null) {
        final current = outcomesByMember[actorId];
        outcomesByMember[actorId] = (actorName, (current?.$2 ?? 0) + 1);
      }
    }

    var tasksWithoutOwner = 0;
    final tasksByMember = <String, (String, int)>{};
    for (final task in tasks) {
      final localDate = _dateKey(tz.TZDateTime.from(task.dueTime, location));
      if (!_inRange(localDate, fromLocalDate, toLocalDate)) continue;
      if (task.dueTime.isAfter(endInstant)) continue;
      if (task.status != CareTaskStatus.completed && task.assigneeId == null) {
        tasksWithoutOwner += 1;
      }
      final actorId = task.completedById;
      final actorName = task.completedBy;
      if (task.status == CareTaskStatus.completed &&
          actorId != null &&
          actorName != null) {
        final current = tasksByMember[actorId];
        tasksByMember[actorId] = (actorName, (current?.$2 ?? 0) + 1);
      }
    }

    final recordedDays = <String>{};
    for (final record in healthRecords) {
      final localDate = record.recordedLocalDate ??
          _dateKey(tz.TZDateTime.from(record.recordedAt, location));
      if (_inRange(localDate, fromLocalDate, toLocalDate)) {
        recordedDays.add(localDate);
      }
    }
    final missingDays = <String>[];
    for (var offset = 0; offset < rangeDays; offset += 1) {
      final day = _dateKey(
        tz.TZDateTime(
          location,
          localStart.year,
          localStart.month,
          localStart.day + offset,
          12,
        ),
      );
      if (!recordedDays.contains(day)) missingDays.add(day);
    }

    final memberIds = {...outcomesByMember.keys, ...tasksByMember.keys};
    final contributions = [
      for (final memberId in memberIds)
        CareContribution(
          memberId: memberId,
          memberName:
              tasksByMember[memberId]?.$1 ?? outcomesByMember[memberId]!.$1,
          completedTasks: tasksByMember[memberId]?.$2 ?? 0,
          medicationOutcomes: outcomesByMember[memberId]?.$2 ?? 0,
        ),
    ]..sort((left, right) {
      final byTotal = right.total.compareTo(left.total);
      return byTotal != 0 ? byTotal : left.memberName.compareTo(right.memberName);
    });

    return CareCoverageSummary(
      fromLocalDate: fromLocalDate,
      toLocalDate: toLocalDate,
      medicationDue: due,
      medicationWithoutOwner: withoutOwner,
      medicationWithoutOutcome: withoutOutcome,
      tasksWithoutOwner: tasksWithoutOwner,
      daysWithoutHealthRecord: List.unmodifiable(missingDays),
      contributions: List.unmodifiable(contributions),
      isRangeUsable: true,
    );
  }

  bool _inRange(String localDate, String from, String to) =>
      localDate.compareTo(from) >= 0 && localDate.compareTo(to) <= 0;

  tz.Location? _location(String identifier) {
    try {
      return tz.getLocation(identifier);
    } on Object {
      return null;
    }
  }

  String _dateKey(tz.TZDateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}
