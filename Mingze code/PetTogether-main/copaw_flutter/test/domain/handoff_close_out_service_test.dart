import 'package:copaw_flutter/src/domain/handoff_close_out_service.dart';
import 'package:copaw_flutter/src/domain/medication_models.dart';
import 'package:copaw_flutter/src/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('[start,end) counts are rebuilt from current source state', () {
    final service = HandoffCloseOutService();
    final start = DateTime.utc(2026, 8, 20);
    final end = DateTime.utc(2026, 8, 21);
    final unresolved = [
      _task('at-start', start, CareTaskStatus.claimed),
      _task(
        'inside',
        start.add(const Duration(hours: 12)),
        CareTaskStatus.completed,
      ),
      _task('at-end', end, CareTaskStatus.completed),
    ];
    final schedule = MedicationScheduleVersion(
      id: 'schedule-a',
      medicationId: 'med-a',
      version: 1,
      petId: 'pet-a',
      petNameSnapshot: 'Mochi',
      medicationNameSnapshot: 'Medication',
      weekdays: const [5],
      slots: const [
        MedicationSlot(
          slotId: 'administered',
          hour: 9,
          minute: 0,
          doseText: 'Dose',
          instructions: null,
        ),
        MedicationSlot(
          slotId: 'skipped',
          hour: 10,
          minute: 0,
          doseText: 'Dose',
          instructions: null,
        ),
      ],
      timeZoneIdentifier: 'Asia/Tokyo',
      effectiveFromLocalDate: '2026-08-20',
      effectiveUntilLocalDate: '2026-08-21',
    );
    final medication = [
      _medicationOccurrence(
        slotId: 'administered',
        dueAt: start,
        status: MedicationOutcomeStatus.administered,
      ),
      _medicationOccurrence(
        slotId: 'skipped',
        dueAt: start.add(const Duration(hours: 1)),
        status: MedicationOutcomeStatus.skipped,
      ),
    ];

    final first = service.build(
      start: start,
      end: end,
      householdTimeZoneIdentifier: 'Asia/Tokyo',
      routines: const [],
      tasks: unresolved,
      medicationSchedules: [schedule],
      medicationOccurrences: medication,
    );
    final refreshed = service.build(
      start: start,
      end: end,
      householdTimeZoneIdentifier: 'Asia/Tokyo',
      routines: const [],
      tasks: [
        _task('at-start', start, CareTaskStatus.completed),
        unresolved[1],
        unresolved[2],
      ],
      medicationSchedules: [schedule],
      medicationOccurrences: medication,
    );

    expect(first.care.planned, 2, reason: 'end instant is excluded');
    expect(first.care.completed, 1);
    expect(first.care.unresolved, 1);
    expect(refreshed.care.planned, 2);
    expect(refreshed.care.completed, 2, reason: 'source is read again');
    expect(refreshed.care.unresolved, 0);
    expect(first.medication.planned, 2);
    expect(first.medication.administered, 1);
    expect(first.medication.skipped, 1);
    expect(first.medication.unresolved, 0);
  });
}

CareTask _task(String id, DateTime dueTime, CareTaskStatus status) => CareTask(
  id: id,
  title: id,
  category: CareCategory.feeding,
  dueTime: dueTime,
  kind: CareTaskKind.oneOff,
  priority: CarePriority.normal,
  routineId: null,
  status: status,
  assignmentRequest: null,
  assigneeId: status == CareTaskStatus.unclaimed ? null : 'user-a',
  assigneeNameSnapshot: status == CareTaskStatus.unclaimed ? null : 'Alex',
  claimedAt: status == CareTaskStatus.unclaimed ? null : dueTime,
  createdById: 'user-a',
  createdBy: 'Alex',
  createdAt: dueTime.subtract(const Duration(hours: 1)),
  completedById: status == CareTaskStatus.completed ? 'user-a' : null,
  completedBy: status == CareTaskStatus.completed ? 'Alex' : null,
  completedAt: status == CareTaskStatus.completed ? dueTime : null,
  revision: status == CareTaskStatus.completed ? 2 : 1,
);

MedicationOccurrence _medicationOccurrence({
  required String slotId,
  required DateTime dueAt,
  required MedicationOutcomeStatus status,
}) => MedicationOccurrence(
  id: 'med-a_schedule-a_2026-08-20_$slotId',
  medicationId: 'med-a',
  scheduleVersionId: 'schedule-a',
  scheduleVersion: 1,
  slotId: slotId,
  localDate: '2026-08-20',
  dueAt: dueAt,
  petId: 'pet-a',
  petNameSnapshot: 'Mochi',
  medicationNameSnapshot: 'Medication',
  doseText: 'Dose',
  instructions: null,
  responsibilityStatus: MedicationResponsibilityStatus.claimed,
  responsibleById: 'user-a',
  responsibleByNameSnapshot: 'Alex',
  claimedAt: dueAt,
  outcomeStatus: status,
  outcomeById: 'user-a',
  outcomeByNameSnapshot: 'Alex',
  outcomeAt: dueAt,
  skippedReasonCode: status == MedicationOutcomeStatus.skipped
      ? MedicationSkipReasonCode.petRefused
      : null,
  skippedReasonNote: null,
  revision: 2,
  isServerConfirmed: true,
);
