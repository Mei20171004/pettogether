import 'package:copaw_flutter/src/domain/medication_models.dart';
import 'package:copaw_flutter/src/domain/medication_occurrence_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = MedicationOccurrenceService();

  test('multi-slot schedule uses household local date and stable IDs', () {
    final result = service.forDay(
      selectedInstant: DateTime.parse('2026-08-12T15:30:00Z'),
      schedules: [_schedule()],
      persisted: const [],
    );

    expect(result.map((item) => item.id), [
      'med-1_v000001_2026-08-13_0800',
      'med-1_v000001_2026-08-13_2000',
    ]);
    expect(result.first.dueAt, DateTime.parse('2026-08-12T23:00:00Z'));
    expect(result.last.dueAt, DateTime.parse('2026-08-13T11:00:00Z'));
  });

  test('old version end is exclusive and future version starts once', () {
    final old = _schedule(effectiveUntil: '2026-08-14');
    final next = _schedule(
      id: 'v000002',
      version: 2,
      effectiveFrom: '2026-08-14',
      slots: const [
        MedicationSlot(
          slotId: '0930',
          hour: 9,
          minute: 30,
          doseText: '2 tablets',
          instructions: null,
        ),
      ],
    );

    final result = service.forDay(
      selectedInstant: DateTime.parse('2026-08-14T00:00:00Z'),
      schedules: [old, next],
      persisted: const [],
    );

    expect(result, hasLength(1));
    expect(result.single.scheduleVersionId, 'v000002');
    expect(result.single.doseText, '2 tablets');
  });

  test('cached terminal occurrence remains visibly unresolved', () {
    final occurrence = _occurrence(isServerConfirmed: false);
    final result = service.forDay(
      selectedInstant: DateTime.parse('2026-08-13T00:00:00Z'),
      schedules: [_schedule()],
      persisted: [occurrence],
    );

    expect(result.first.persisted, same(occurrence));
    expect(result.first.outcomeStatus, MedicationOutcomeStatus.unresolved);
    expect(result.first.isServerConfirmed, isFalse);
  });
}

MedicationScheduleVersion _schedule({
  String id = 'v000001',
  int version = 1,
  String effectiveFrom = '2026-08-01',
  String? effectiveUntil,
  List<MedicationSlot> slots = const [
    MedicationSlot(
      slotId: '0800',
      hour: 8,
      minute: 0,
      doseText: '1 tablet',
      instructions: 'With breakfast',
    ),
    MedicationSlot(
      slotId: '2000',
      hour: 20,
      minute: 0,
      doseText: '1 tablet',
      instructions: null,
    ),
  ],
}) => MedicationScheduleVersion(
  id: id,
  medicationId: 'med-1',
  version: version,
  petId: 'pet-1',
  petNameSnapshot: 'Mochi',
  medicationNameSnapshot: 'Tablet A',
  weekdays: const [1, 2, 3, 4, 5, 6, 7],
  slots: slots,
  timeZoneIdentifier: 'Asia/Tokyo',
  effectiveFromLocalDate: effectiveFrom,
  effectiveUntilLocalDate: effectiveUntil,
);

MedicationOccurrence _occurrence({required bool isServerConfirmed}) =>
    MedicationOccurrence(
      id: 'med-1_v000001_2026-08-13_0800',
      medicationId: 'med-1',
      scheduleVersionId: 'v000001',
      scheduleVersion: 1,
      slotId: '0800',
      localDate: '2026-08-13',
      dueAt: DateTime.parse('2026-08-12T23:00:00Z'),
      petId: 'pet-1',
      petNameSnapshot: 'Mochi',
      medicationNameSnapshot: 'Tablet A',
      doseText: '1 tablet',
      instructions: 'With breakfast',
      responsibilityStatus: MedicationResponsibilityStatus.claimed,
      responsibleById: 'user-1',
      responsibleByNameSnapshot: 'Alex',
      claimedAt: DateTime.parse('2026-08-12T22:30:00Z'),
      outcomeStatus: MedicationOutcomeStatus.administered,
      outcomeById: 'user-1',
      outcomeByNameSnapshot: 'Alex',
      outcomeAt: DateTime.parse('2026-08-12T23:05:00Z'),
      skippedReasonCode: null,
      skippedReasonNote: null,
      revision: 2,
      isServerConfirmed: isServerConfirmed,
    );
