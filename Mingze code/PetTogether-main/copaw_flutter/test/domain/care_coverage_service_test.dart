import 'package:copaw_flutter/src/domain/care_coverage_service.dart';
import 'package:copaw_flutter/src/domain/health_models.dart';
import 'package:copaw_flutter/src/domain/medication_models.dart';
import 'package:copaw_flutter/src/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as time_zone_data;

void main() {
  setUpAll(time_zone_data.initializeTimeZones);

  const service = CareCoverageService();
  final endInstant = DateTime.utc(2026, 8, 12, 15); // 2026-08-13 00:00 in Tokyo

  test('a dose still ahead of now is not counted as a gap', () {
    final summary = service.build(
      endInstant: endInstant,
      rangeDays: 3,
      timeZoneIdentifier: 'Asia/Tokyo',
      medicationOccurrences: [
        _dose('future', '2026-08-13', DateTime.utc(2026, 8, 12, 23)),
      ],
    );

    expect(summary.medicationDue, 0);
    expect(summary.medicationWithoutOutcome, 0);
  });

  test('a claimed dose without an outcome is still an open gap', () {
    final summary = service.build(
      endInstant: endInstant,
      rangeDays: 3,
      timeZoneIdentifier: 'Asia/Tokyo',
      medicationOccurrences: [
        _dose(
          'claimed',
          '2026-08-12',
          DateTime.utc(2026, 8, 12, 1),
          responsibility: MedicationResponsibilityStatus.claimed,
        ),
      ],
    );

    expect(summary.medicationDue, 1);
    expect(summary.medicationWithoutOwner, 0);
    expect(summary.medicationWithoutOutcome, 1);
    expect(summary.hasGaps, isTrue);
  });

  test('a dose nobody took responsibility for is reported separately', () {
    final summary = service.build(
      endInstant: endInstant,
      rangeDays: 3,
      timeZoneIdentifier: 'Asia/Tokyo',
      medicationOccurrences: [
        _dose('orphan', '2026-08-12', DateTime.utc(2026, 8, 12, 1)),
      ],
    );

    expect(summary.medicationWithoutOwner, 1);
    expect(summary.medicationWithoutOutcome, 1);
  });

  test('days with no health record at all are listed', () {
    final summary = service.build(
      endInstant: endInstant,
      rangeDays: 3,
      timeZoneIdentifier: 'Asia/Tokyo',
      healthRecords: [
        _health('h-1', DateTime.utc(2026, 8, 12, 1), '2026-08-12'),
      ],
    );

    expect(summary.daysWithoutHealthRecord, ['2026-08-11', '2026-08-13']);
  });

  test('contributions count recorded work and never rank people by name', () {
    final summary = service.build(
      endInstant: endInstant,
      rangeDays: 3,
      timeZoneIdentifier: 'Asia/Tokyo',
      medicationOccurrences: [
        _dose(
          'given',
          '2026-08-12',
          DateTime.utc(2026, 8, 12, 1),
          responsibility: MedicationResponsibilityStatus.claimed,
          outcome: MedicationOutcomeStatus.administered,
          actorId: 'user-1',
          actorName: 'Alex',
        ),
      ],
      tasks: [
        _task('t-1', DateTime.utc(2026, 8, 12, 2), completedBy: 'user-2'),
        _task('t-2', DateTime.utc(2026, 8, 12, 3), completedBy: 'user-2'),
      ],
    );

    expect(summary.contributions.first.memberId, 'user-2');
    expect(summary.contributions.first.completedTasks, 2);
    expect(summary.contributions.last.medicationOutcomes, 1);
  });

  test('an unusable timezone reports no period instead of zero gaps', () {
    final summary = service.build(
      endInstant: endInstant,
      rangeDays: 3,
      timeZoneIdentifier: 'Not/AZone',
      medicationOccurrences: [
        _dose('orphan', '2026-08-12', DateTime.utc(2026, 8, 12, 1)),
      ],
    );

    expect(summary.isRangeUsable, isFalse);
    expect(summary.fromLocalDate, isNull);
    expect(summary.hasGaps, isFalse);
  });

  test('an unassigned task that has not come due yet is not a gap', () {
    final summary = service.build(
      endInstant: endInstant,
      rangeDays: 3,
      timeZoneIdentifier: 'Asia/Tokyo',
      tasks: [_task('later', DateTime.utc(2026, 8, 12, 23))],
    );

    expect(summary.tasksWithoutOwner, 0);
  });

  test('an overdue unassigned task is a gap', () {
    final summary = service.build(
      endInstant: endInstant,
      rangeDays: 3,
      timeZoneIdentifier: 'Asia/Tokyo',
      tasks: [_task('overdue', DateTime.utc(2026, 8, 12, 1))],
    );

    expect(summary.tasksWithoutOwner, 1);
    expect(summary.hasGaps, isTrue);
  });
}

MedicationOccurrence _dose(
  String id,
  String localDate,
  DateTime dueAt, {
  MedicationResponsibilityStatus responsibility =
      MedicationResponsibilityStatus.unclaimed,
  MedicationOutcomeStatus outcome = MedicationOutcomeStatus.unresolved,
  String? actorId,
  String? actorName,
}) => MedicationOccurrence(
  id: id,
  medicationId: 'med-1',
  scheduleVersionId: 'v000001',
  scheduleVersion: 1,
  slotId: 'morning',
  localDate: localDate,
  dueAt: dueAt,
  petId: 'pet-1',
  petNameSnapshot: 'Mochi',
  medicationNameSnapshot: 'Medicine',
  doseText: '1 tablet',
  instructions: null,
  responsibilityStatus: responsibility,
  responsibleById: responsibility == MedicationResponsibilityStatus.claimed
      ? (actorId ?? 'user-1')
      : null,
  responsibleByNameSnapshot:
      responsibility == MedicationResponsibilityStatus.claimed
      ? (actorName ?? 'Alex')
      : null,
  claimedAt: responsibility == MedicationResponsibilityStatus.claimed
      ? dueAt.subtract(const Duration(minutes: 5))
      : null,
  outcomeStatus: outcome,
  outcomeById: outcome == MedicationOutcomeStatus.unresolved ? null : actorId,
  outcomeByNameSnapshot:
      outcome == MedicationOutcomeStatus.unresolved ? null : actorName,
  outcomeAt: outcome == MedicationOutcomeStatus.unresolved ? null : dueAt,
  skippedReasonCode: null,
  skippedReasonNote: null,
  revision: 1,
  isServerConfirmed: true,
);

CareTask _task(String id, DateTime dueTime, {String? completedBy}) => CareTask(
  id: id,
  title: 'Morning meal',
  category: CareCategory.feeding,
  dueTime: dueTime,
  kind: CareTaskKind.oneOff,
  priority: CarePriority.normal,
  routineId: null,
  status: completedBy == null
      ? CareTaskStatus.unclaimed
      : CareTaskStatus.completed,
  assignmentRequest: null,
  assigneeId: completedBy,
  assigneeNameSnapshot: completedBy == null ? null : 'Sam',
  claimedAt: completedBy == null ? null : dueTime,
  createdById: 'user-1',
  createdBy: 'Alex',
  createdAt: DateTime.utc(2026, 8, 10),
  completedById: completedBy,
  completedBy: completedBy == null ? null : 'Sam',
  completedAt: completedBy == null ? null : dueTime,
  revision: 1,
  petId: 'pet-1',
  petNameSnapshot: 'Mochi',
);

HealthRecord _health(String id, DateTime recordedAt, String localDate) =>
    HealthRecord(
      id: id,
      petId: 'pet-1',
      petNameSnapshot: 'Mochi',
      type: HealthRecordType.note,
      recordedAt: recordedAt,
      recordedLocalDate: localDate,
      recordedTimeZoneIdentifier: 'Asia/Tokyo',
      detail: 'Observation',
      weightKilograms: null,
      createdById: 'user-1',
      createdByNameSnapshot: 'Alex',
      createdAt: recordedAt,
    );
