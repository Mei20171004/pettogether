import 'package:copaw_flutter/src/domain/health_models.dart';
import 'package:copaw_flutter/src/domain/medication_models.dart';
import 'package:copaw_flutter/src/domain/models.dart';
import 'package:copaw_flutter/src/domain/report_models.dart';
import 'package:copaw_flutter/src/domain/report_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('7-day report reconciles care medication health and source events', () {
    final report = ReportService().build(
      petId: 'pet-1',
      petName: 'Mochi',
      rangeDays: 7,
      endInstant: DateTime.utc(2026, 8, 13, 3),
      timeZoneIdentifier: 'Asia/Tokyo',
      routines: [_routine()],
      tasks: [
        _completedRoutineTask(),
        _oneOffTask(id: 'future-today', dueAt: DateTime.utc(2026, 8, 13, 9)),
      ],
      medicationSchedules: [_scheduleV1(), _scheduleV2()],
      medicationOccurrences: [
        _medicationOccurrence(
          id: 'med-1_v1_2026-08-08_morning',
          scheduleId: 'v1',
          scheduleVersion: 1,
          localDate: '2026-08-08',
          dueAt: DateTime.utc(2026, 8, 8),
          outcome: MedicationOutcomeStatus.administered,
          outcomeAt: DateTime.utc(2026, 8, 8),
          actor: 'Alex',
        ),
        _medicationOccurrence(
          id: 'med-1_v2_2026-08-11_morning',
          scheduleId: 'v2',
          scheduleVersion: 2,
          localDate: '2026-08-11',
          dueAt: DateTime.utc(2026, 8, 11, 1),
          outcome: MedicationOutcomeStatus.skipped,
          outcomeAt: DateTime.utc(2026, 8, 11, 1, 5),
          actor: 'Sam',
        ),
      ],
      healthRecords: [
        _health(
          'health-weight',
          HealthRecordType.weight,
          DateTime.utc(2026, 8, 9),
        ),
        _health(
          'health-note',
          HealthRecordType.note,
          DateTime.utc(2026, 8, 12),
        ),
        _health(
          'other-pet',
          HealthRecordType.note,
          DateTime.utc(2026, 8, 12),
          petId: 'pet-2',
        ),
        _health('too-old', HealthRecordType.note, DateTime.utc(2026, 8, 1)),
      ],
    );

    expect(report.care.planned, 7);
    expect(report.care.completed, 1);
    expect(report.care.unresolved, 6);
    expect(report.care.completedEvents.single.sourceId, 'routine-1_2026-08-08');
    expect(report.care.completedEvents.single.actorNameSnapshot, 'Alex');
    expect(report.medication.planned, 7);
    expect(report.medication.administered, 1);
    expect(report.medication.skipped, 1);
    expect(report.medication.unresolved, 5);
    expect(report.medication.late, 1);
    expect(report.medication.terminalEvents.map((event) => event.kind), [
      ReportEventKind.medicationAdministered,
      ReportEventKind.medicationSkipped,
    ]);
    expect(report.medication.terminalEvents.last.actorNameSnapshot, 'Sam');
    expect(report.health.total, 2);
    expect(report.health.countsByType[HealthRecordType.weight], 1);
    expect(report.health.countsByType[HealthRecordType.note], 1);
  });

  test('immutable medication versions preserve the historical denominator', () {
    final service = ReportService();
    final report = service.build(
      petId: 'pet-1',
      petName: 'Mochi',
      rangeDays: 7,
      endInstant: DateTime.utc(2026, 8, 13, 3),
      timeZoneIdentifier: 'Asia/Tokyo',
      routines: const [],
      tasks: const [],
      medicationSchedules: [_scheduleV1(), _scheduleV2()],
      medicationOccurrences: const [],
      healthRecords: const [],
    );
    final currentVersionOnly = service.build(
      petId: 'pet-1',
      petName: 'Mochi',
      rangeDays: 7,
      endInstant: DateTime.utc(2026, 8, 13, 3),
      timeZoneIdentifier: 'Asia/Tokyo',
      routines: const [],
      tasks: const [],
      medicationSchedules: [_scheduleV2()],
      medicationOccurrences: const [],
      healthRecords: const [],
    );

    expect(report.medication.planned, 7);
    expect(currentVersionOnly.medication.planned, 4);
  });

  test('a custom range covers whole household-local days inclusively', () {
    final service = ReportService();
    final report = service.build(
      petId: 'pet-1',
      petName: 'Mochi',
      startInstant: DateTime.utc(2026, 8, 8, 15),
      endInstant: DateTime.utc(2026, 8, 12, 3),
      timeZoneIdentifier: 'Asia/Tokyo',
      routines: const [],
      tasks: const [],
      medicationSchedules: const [],
      medicationOccurrences: const [],
      healthRecords: [
        _health('h-before', HealthRecordType.note, DateTime.utc(2026, 8, 8, 13)),
        _health('h-first', HealthRecordType.note, DateTime.utc(2026, 8, 8, 16)),
        _health('h-last', HealthRecordType.note, DateTime.utc(2026, 8, 12, 2)),
      ],
    );

    // 2026-08-09 through 2026-08-12 in Tokyo is four local days.
    expect(report.rangeDays, 4);
    expect(
      report.health.records.map((record) => record.id),
      ['h-first', 'h-last'],
    );
  });

  test('excluding a section never turns real activity into a zero', () {
    final service = ReportService();
    final report = service.build(
      petId: 'pet-1',
      petName: 'Mochi',
      rangeDays: 7,
      sections: const {ReportSection.care},
      endInstant: DateTime.utc(2026, 8, 13, 3),
      timeZoneIdentifier: 'Asia/Tokyo',
      routines: const [],
      tasks: const [],
      medicationSchedules: const [],
      medicationOccurrences: const [],
      healthRecords: [
        _health('h-1', HealthRecordType.note, DateTime.utc(2026, 8, 12, 1)),
      ],
    );

    expect(report.includes(ReportSection.care), isTrue);
    expect(report.includes(ReportSection.health), isFalse);
    expect(report.health.total, 1);
  });

  test('a custom range rejects an inverted span and one over a year', () {
    final service = ReportService();
    expect(
      () => service.build(
        petId: 'pet-1',
        petName: 'Mochi',
        startInstant: DateTime.utc(2026, 8, 12),
        endInstant: DateTime.utc(2026, 8, 10),
        timeZoneIdentifier: 'Asia/Tokyo',
        routines: const [],
        tasks: const [],
        medicationSchedules: const [],
        medicationOccurrences: const [],
        healthRecords: const [],
      ),
      throwsA(isA<ReportBuildException>()),
    );
    expect(
      () => service.build(
        petId: 'pet-1',
        petName: 'Mochi',
        startInstant: DateTime.utc(2024, 1, 1),
        endInstant: DateTime.utc(2026, 8, 10),
        timeZoneIdentifier: 'Asia/Tokyo',
        routines: const [],
        tasks: const [],
        medicationSchedules: const [],
        medicationOccurrences: const [],
        healthRecords: const [],
      ),
      throwsA(isA<ReportBuildException>()),
    );
    expect(
      () => service.build(
        petId: 'pet-1',
        petName: 'Mochi',
        rangeDays: 7,
        sections: const {},
        endInstant: DateTime.utc(2026, 8, 10),
        timeZoneIdentifier: 'Asia/Tokyo',
        routines: const [],
        tasks: const [],
        medicationSchedules: const [],
        medicationOccurrences: const [],
        healthRecords: const [],
      ),
      throwsA(isA<ReportBuildException>()),
    );
  });

  test('report rejects unsupported ranges and unknown timezones', () {
    final service = ReportService();
    PetCareReport build({required int days, String zone = 'Asia/Tokyo'}) =>
        service.build(
          petId: 'pet-1',
          petName: 'Mochi',
          rangeDays: days,
          endInstant: DateTime.utc(2026, 8, 13),
          timeZoneIdentifier: zone,
          routines: const [],
          tasks: const [],
          medicationSchedules: const [],
          medicationOccurrences: const [],
          healthRecords: const [],
        );

    expect(() => build(days: 14), throwsA(isA<ReportBuildException>()));
    expect(
      () => build(days: 7, zone: 'Tokyo'),
      throwsA(isA<ReportBuildException>()),
    );
  });

  test('water reducer sums only separate intake records for one local day', () {
    final report = _waterReport([
      _health(
        'intake-1',
        HealthRecordType.waterIntake,
        DateTime.utc(2026, 8, 12, 8),
        recordedLocalDate: '2026-08-12',
        waterMilliliters: 120,
        waterMeasurementBasis: WaterMeasurementBasis.singleIntake,
      ),
      _health(
        'intake-2',
        HealthRecordType.waterIntake,
        DateTime.utc(2026, 8, 12, 9),
        recordedLocalDate: '2026-08-12',
        waterMilliliters: 180,
        waterMeasurementBasis: WaterMeasurementBasis.singleIntake,
      ),
    ]);

    expect(report.health.waterDays, hasLength(1));
    expect(report.health.waterDays.single.milliliters, 300);
    expect(
      report.health.waterDays.single.basis,
      WaterDaySummaryBasis.summedSingleIntakes,
    );
    expect(report.health.waterDays.single.includedRecordCount, 2);
    expect(report.health.excludedWaterRecordCount, 0);
  });

  test(
    'water reducer prefers the strongest daily basis without double count',
    () {
      final report = _waterReport([
        _health(
          'intake',
          HealthRecordType.waterIntake,
          DateTime.utc(2026, 8, 12, 7),
          recordedLocalDate: '2026-08-12',
          waterMilliliters: 120,
          waterMeasurementBasis: WaterMeasurementBasis.singleIntake,
        ),
        _health(
          'partial',
          HealthRecordType.dailyCheckIn,
          DateTime.utc(2026, 8, 12, 8),
          recordedLocalDate: '2026-08-12',
          waterMilliliters: 180,
          waterMeasurementBasis: WaterMeasurementBasis.localDayToDate,
        ),
        _health(
          'full',
          HealthRecordType.waterIntake,
          DateTime.utc(2026, 8, 12, 10),
          recordedLocalDate: '2026-08-12',
          waterMilliliters: 450,
          waterMeasurementBasis: WaterMeasurementBasis.fullLocalDay,
        ),
        _health(
          'legacy',
          HealthRecordType.waterIntake,
          DateTime.utc(2026, 8, 12, 11),
          waterMilliliters: 999,
          waterMeasurementBasis: WaterMeasurementBasis.legacyUnknown,
        ),
      ]);

      expect(report.health.waterDays.single.milliliters, 450);
      expect(
        report.health.waterDays.single.basis,
        WaterDaySummaryBasis.fullLocalDay,
      );
      expect(report.health.waterDays.single.excludedRecordCount, 2);
      expect(report.health.excludedWaterRecordCount, 3);
    },
  );

  test(
    'v2 health range uses persisted local day while v1 falls back to time',
    () {
      final report = _waterReport([
        _health(
          'v2-in-range',
          HealthRecordType.waterIntake,
          DateTime.utc(2026, 8, 6, 14),
          recordedLocalDate: '2026-08-08',
          waterMilliliters: 100,
          waterMeasurementBasis: WaterMeasurementBasis.singleIntake,
        ),
        _health(
          'v1-before-range',
          HealthRecordType.note,
          DateTime.utc(2026, 8, 6, 14),
        ),
      ]);

      expect(report.health.records.map((record) => record.id), ['v2-in-range']);
      expect(report.health.waterDays.single.localDate, '2026-08-08');
    },
  );
}

PetCareReport _waterReport(List<HealthRecord> records) => ReportService().build(
  petId: 'pet-1',
  petName: 'Mochi',
  rangeDays: 7,
  endInstant: DateTime.utc(2026, 8, 13, 3),
  timeZoneIdentifier: 'Asia/Tokyo',
  routines: const [],
  tasks: const [],
  medicationSchedules: const [],
  medicationOccurrences: const [],
  healthRecords: records,
);

CareRoutine _routine() => CareRoutine(
  id: 'routine-1',
  title: 'Morning meal',
  category: CareCategory.feeding,
  priority: CarePriority.normal,
  frequency: CareRoutineFrequency.daily,
  weekdays: const [1, 2, 3, 4, 5, 6, 7],
  hour: 8,
  minute: 0,
  startDate: DateTime.utc(2026, 8, 6, 15),
  timeZoneIdentifier: 'Asia/Tokyo',
  createdById: 'user-1',
  createdByNameSnapshot: 'Alex',
  isActive: true,
  petId: 'pet-1',
  petNameSnapshot: 'Mochi',
);

CareTask _completedRoutineTask() => CareTask(
  id: 'routine-1_2026-08-08',
  title: 'Morning meal',
  category: CareCategory.feeding,
  dueTime: DateTime.utc(2026, 8, 7, 23),
  kind: CareTaskKind.routine,
  priority: CarePriority.normal,
  routineId: 'routine-1',
  status: CareTaskStatus.completed,
  assignmentRequest: null,
  assigneeId: 'user-1',
  assigneeNameSnapshot: 'Alex',
  claimedAt: DateTime.utc(2026, 8, 7, 22),
  createdById: 'user-1',
  createdBy: 'Alex',
  createdAt: DateTime.utc(2026, 8, 6),
  completedById: 'user-1',
  completedBy: 'Alex',
  completedAt: DateTime.utc(2026, 8, 7, 23, 5),
  revision: 2,
  petId: 'pet-1',
  petNameSnapshot: 'Mochi',
);

CareTask _oneOffTask({required String id, required DateTime dueAt}) => CareTask(
  id: id,
  title: 'Future care',
  category: CareCategory.other,
  dueTime: dueAt,
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
  createdAt: DateTime.utc(2026, 8, 1),
  completedById: null,
  completedBy: null,
  completedAt: null,
  revision: 0,
  petId: 'pet-1',
  petNameSnapshot: 'Mochi',
);

MedicationScheduleVersion _scheduleV1() => const MedicationScheduleVersion(
  id: 'v1',
  medicationId: 'med-1',
  version: 1,
  petId: 'pet-1',
  petNameSnapshot: 'Mochi',
  medicationNameSnapshot: 'Medicine',
  weekdays: [1, 2, 3, 4, 5, 6, 7],
  slots: [
    MedicationSlot(
      slotId: 'morning',
      hour: 9,
      minute: 0,
      doseText: '1 tablet',
      instructions: null,
    ),
  ],
  timeZoneIdentifier: 'Asia/Tokyo',
  effectiveFromLocalDate: '2026-08-07',
  effectiveUntilLocalDate: '2026-08-10',
);

MedicationScheduleVersion _scheduleV2() => const MedicationScheduleVersion(
  id: 'v2',
  medicationId: 'med-1',
  version: 2,
  petId: 'pet-1',
  petNameSnapshot: 'Mochi',
  medicationNameSnapshot: 'Medicine',
  weekdays: [1, 2, 3, 4, 5, 6, 7],
  slots: [
    MedicationSlot(
      slotId: 'morning',
      hour: 10,
      minute: 0,
      doseText: '1 tablet',
      instructions: null,
    ),
  ],
  timeZoneIdentifier: 'Asia/Tokyo',
  effectiveFromLocalDate: '2026-08-10',
  effectiveUntilLocalDate: null,
);

MedicationOccurrence _medicationOccurrence({
  required String id,
  required String scheduleId,
  required int scheduleVersion,
  required String localDate,
  required DateTime dueAt,
  required MedicationOutcomeStatus outcome,
  required DateTime outcomeAt,
  required String actor,
}) => MedicationOccurrence(
  id: id,
  medicationId: 'med-1',
  scheduleVersionId: scheduleId,
  scheduleVersion: scheduleVersion,
  slotId: 'morning',
  localDate: localDate,
  dueAt: dueAt,
  petId: 'pet-1',
  petNameSnapshot: 'Mochi',
  medicationNameSnapshot: 'Medicine',
  doseText: '1 tablet',
  instructions: null,
  responsibilityStatus: MedicationResponsibilityStatus.claimed,
  responsibleById: 'user-1',
  responsibleByNameSnapshot: actor,
  claimedAt: dueAt.subtract(const Duration(minutes: 1)),
  outcomeStatus: outcome,
  outcomeById: 'user-1',
  outcomeByNameSnapshot: actor,
  outcomeAt: outcomeAt,
  skippedReasonCode: outcome == MedicationOutcomeStatus.skipped
      ? MedicationSkipReasonCode.other
      : null,
  skippedReasonNote: null,
  revision: 2,
  isServerConfirmed: true,
);

HealthRecord _health(
  String id,
  HealthRecordType type,
  DateTime recordedAt, {
  String petId = 'pet-1',
  String? recordedLocalDate,
  double? waterMilliliters,
  WaterMeasurementBasis? waterMeasurementBasis,
}) => HealthRecord(
  id: id,
  petId: petId,
  petNameSnapshot: petId == 'pet-1' ? 'Mochi' : 'Nori',
  type: type,
  recordedAt: recordedAt,
  recordedLocalDate: recordedLocalDate,
  recordedTimeZoneIdentifier: recordedLocalDate == null ? null : 'Asia/Tokyo',
  detail: type == HealthRecordType.weight ? null : 'Observation',
  weightKilograms: type == HealthRecordType.weight ? 4.2 : null,
  waterMilliliters: waterMilliliters,
  waterMeasurementBasis: waterMeasurementBasis,
  createdById: 'user-1',
  createdByNameSnapshot: 'Alex',
  createdAt: recordedAt,
);
