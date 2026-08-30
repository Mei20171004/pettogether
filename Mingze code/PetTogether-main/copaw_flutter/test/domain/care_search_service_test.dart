import 'package:copaw_flutter/src/domain/care_search_service.dart';
import 'package:copaw_flutter/src/domain/health_models.dart';
import 'package:copaw_flutter/src/domain/medication_models.dart';
import 'package:copaw_flutter/src/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as time_zone_data;

void main() {
  setUpAll(time_zone_data.initializeTimeZones);

  const service = CareSearchService();

  test('an empty query returns the whole history newest first', () {
    final outcome = service.search(
      query: const CareSearchQuery(),
      timeZoneIdentifier: 'Asia/Tokyo',
      healthRecords: [_health('h-1', DateTime.utc(2026, 8, 9, 1))],
      medicationOccurrences: [_medication('m-1', '2026-08-10')],
      tasks: [_task('t-1', DateTime.utc(2026, 8, 7, 23))],
    );

    expect(outcome.totalCount, 3);
    expect(
      outcome.days.map((day) => day.localDate),
      ['2026-08-10', '2026-08-09', '2026-08-08'],
    );
    expect(outcome.undatedCount, 0);
  });

  test('the household local day decides which date a record belongs to', () {
    // 23:00 UTC is already the next day in Tokyo.
    final outcome = service.search(
      query: const CareSearchQuery(),
      timeZoneIdentifier: 'Asia/Tokyo',
      tasks: [_task('t-1', DateTime.utc(2026, 8, 7, 23))],
    );

    expect(outcome.days.single.localDate, '2026-08-08');
  });

  test('an inclusive local date range keeps both bounds', () {
    final outcome = service.search(
      query: const CareSearchQuery(
        fromLocalDate: '2026-08-09',
        toLocalDate: '2026-08-10',
      ),
      timeZoneIdentifier: 'Asia/Tokyo',
      healthRecords: [
        _health('h-old', DateTime.utc(2026, 8, 7, 1)),
        _health('h-from', DateTime.utc(2026, 8, 9, 1)),
      ],
      medicationOccurrences: [
        _medication('m-to', '2026-08-10'),
        _medication('m-after', '2026-08-11'),
      ],
    );

    expect(
      outcome.days.expand((day) => day.results).map((result) => result.id),
      ['m-to', 'h-from'],
    );
  });

  test('text search matches stored text and never the localized labels', () {
    final outcome = service.search(
      query: const CareSearchQuery(text: 'TABLET'),
      timeZoneIdentifier: 'Asia/Tokyo',
      healthRecords: [_health('h-1', DateTime.utc(2026, 8, 9, 1))],
      medicationOccurrences: [_medication('m-1', '2026-08-10')],
    );

    expect(outcome.totalCount, 1);
    expect(outcome.days.single.results.single.id, 'm-1');
  });

  test('one pet filter excludes the other pet', () {
    final outcome = service.search(
      query: const CareSearchQuery(petId: 'pet-2'),
      timeZoneIdentifier: 'Asia/Tokyo',
      healthRecords: [
        _health('h-1', DateTime.utc(2026, 8, 9, 1)),
        _health('h-2', DateTime.utc(2026, 8, 9, 2), petId: 'pet-2'),
      ],
    );

    expect(outcome.days.single.results.single.id, 'h-2');
  });

  test('kind filters restrict which sources are searched', () {
    final outcome = service.search(
      query: const CareSearchQuery(kinds: {CareSearchKind.task}),
      timeZoneIdentifier: 'Asia/Tokyo',
      healthRecords: [_health('h-1', DateTime.utc(2026, 8, 9, 1))],
      medicationOccurrences: [_medication('m-1', '2026-08-10')],
      tasks: [_task('t-1', DateTime.utc(2026, 8, 7, 23))],
    );

    expect(outcome.days.single.results.single.kind, CareSearchKind.task);
  });

  test('an unconfirmed medication row is returned but stays marked', () {
    final outcome = service.search(
      query: const CareSearchQuery(),
      timeZoneIdentifier: 'Asia/Tokyo',
      medicationOccurrences: [
        _medication('m-1', '2026-08-10', isServerConfirmed: false),
      ],
    );

    expect(outcome.days.single.results.single.isServerConfirmed, isFalse);
  });

  test('an unusable household timezone reports undated instead of guessing', () {
    final outcome = service.search(
      query: const CareSearchQuery(),
      timeZoneIdentifier: 'Not/AZone',
      healthRecords: [_health('h-1', DateTime.utc(2026, 8, 9, 1))],
      tasks: [_task('t-1', DateTime.utc(2026, 8, 7, 23))],
    );

    expect(outcome.days, isEmpty);
    expect(outcome.totalCount, 0);
    expect(outcome.undatedCount, 2);
  });

  test('a stored local date is preferred over one derived from the instant', () {
    final outcome = service.search(
      query: const CareSearchQuery(),
      timeZoneIdentifier: 'America/New_York',
      healthRecords: [
        _health(
          'h-1',
          DateTime.utc(2026, 8, 9, 1),
          recordedLocalDate: '2026-08-09',
        ),
      ],
    );

    expect(outcome.days.single.localDate, '2026-08-09');
  });

  test('results within one day stay in a stable order', () {
    final outcome = service.search(
      query: const CareSearchQuery(),
      timeZoneIdentifier: 'Asia/Tokyo',
      healthRecords: [
        _health('h-b', DateTime.utc(2026, 8, 9, 1)),
        _health('h-a', DateTime.utc(2026, 8, 9, 1)),
      ],
    );

    expect(
      outcome.days.single.results.map((result) => result.id),
      ['h-a', 'h-b'],
    );
  });
}

HealthRecord _health(
  String id,
  DateTime recordedAt, {
  String petId = 'pet-1',
  String? recordedLocalDate,
}) => HealthRecord(
  id: id,
  petId: petId,
  petNameSnapshot: petId == 'pet-1' ? 'Mochi' : 'Nori',
  type: HealthRecordType.note,
  recordedAt: recordedAt,
  recordedLocalDate: recordedLocalDate,
  recordedTimeZoneIdentifier: recordedLocalDate == null ? null : 'Asia/Tokyo',
  detail: 'Observation',
  weightKilograms: null,
  createdById: 'user-1',
  createdByNameSnapshot: 'Alex',
  createdAt: recordedAt,
);

MedicationOccurrence _medication(
  String id,
  String localDate, {
  bool isServerConfirmed = true,
}) => MedicationOccurrence(
  id: id,
  medicationId: 'med-1',
  scheduleVersionId: 'v000001',
  scheduleVersion: 1,
  slotId: 'morning',
  localDate: localDate,
  dueAt: DateTime.utc(2026, 8, 10),
  petId: 'pet-1',
  petNameSnapshot: 'Mochi',
  medicationNameSnapshot: 'Medicine',
  doseText: '1 tablet',
  instructions: null,
  responsibilityStatus: MedicationResponsibilityStatus.claimed,
  responsibleById: 'user-1',
  responsibleByNameSnapshot: 'Alex',
  claimedAt: DateTime.utc(2026, 8, 9, 23),
  outcomeStatus: MedicationOutcomeStatus.administered,
  outcomeById: 'user-1',
  outcomeByNameSnapshot: 'Alex',
  outcomeAt: DateTime.utc(2026, 8, 10, 1),
  skippedReasonCode: null,
  skippedReasonNote: null,
  revision: 2,
  isServerConfirmed: isServerConfirmed,
);

CareTask _task(String id, DateTime dueTime) => CareTask(
  id: id,
  title: 'Morning meal',
  category: CareCategory.feeding,
  dueTime: dueTime,
  kind: CareTaskKind.oneOff,
  priority: CarePriority.normal,
  routineId: null,
  status: CareTaskStatus.unclaimed,
  assignmentRequest: null,
  assigneeId: null,
  assigneeNameSnapshot: null,
  claimedAt: null,
  createdById: 'user-1',
  createdBy: 'Alex',
  createdAt: DateTime.utc(2026, 8, 6),
  completedById: null,
  completedBy: null,
  completedAt: null,
  revision: 1,
  petId: 'pet-1',
  petNameSnapshot: 'Mochi',
);
