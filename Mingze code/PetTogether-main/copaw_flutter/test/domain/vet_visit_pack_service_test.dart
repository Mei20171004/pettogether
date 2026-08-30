import 'package:copaw_flutter/src/domain/handoff_models.dart';
import 'package:copaw_flutter/src/domain/health_models.dart';
import 'package:copaw_flutter/src/domain/medication_models.dart';
import 'package:copaw_flutter/src/domain/models.dart';
import 'package:copaw_flutter/src/domain/vet_visit_pack_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as time_zone_data;

void main() {
  setUpAll(time_zone_data.initializeTimeZones);

  const service = VetVisitPackService();
  final pet = Pet(
    id: 'pet-1',
    name: 'Mochi',
    species: null,
    isArchived: false,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );

  test('every line carries who recorded it and when', () {
    final pack = service.build(
      pet: pet,
      endInstant: DateTime.utc(2026, 8, 13, 3),
      rangeDays: 7,
      timeZoneIdentifier: 'Asia/Tokyo',
      handoff: _handoff(),
      healthRecords: [_health('h-1', DateTime.utc(2026, 8, 12, 1))],
    );

    for (final entry in pack.entriesFor(VetVisitSection.healthObservations)) {
      expect(entry.recordedBy, 'Alex');
      expect(entry.recordedAt, isNotNull);
    }
    final contact = pack.entriesFor(VetVisitSection.emergencyContacts).first;
    expect(contact.recordedBy, 'Owner');
    expect(contact.recordedAt, DateTime.utc(2026, 8, 1));
  });

  test('an active medication with no recorded time is not given one', () {
    final pack = service.build(
      pet: pet,
      endInstant: DateTime.utc(2026, 8, 13, 3),
      rangeDays: 7,
      timeZoneIdentifier: 'Asia/Tokyo',
      medications: [_medication(isActive: true)],
    );

    final entry = pack.entriesFor(VetVisitSection.activeMedications).single;
    expect(entry.label, 'Medicine');
    expect(entry.recordedAt, isNull);
    expect(entry.recordedBy, isNull);
  });

  test('a stopped medication is left out', () {
    final pack = service.build(
      pet: pet,
      endInstant: DateTime.utc(2026, 8, 13, 3),
      rangeDays: 7,
      timeZoneIdentifier: 'Asia/Tokyo',
      medications: [_medication(isActive: false)],
    );

    expect(pack.entriesFor(VetVisitSection.activeMedications), isEmpty);
    expect(
      pack.missingSections,
      contains(VetVisitSection.activeMedications),
    );
  });

  test('an unresolved medication is not reported as an outcome', () {
    final pack = service.build(
      pet: pet,
      endInstant: DateTime.utc(2026, 8, 13, 3),
      rangeDays: 7,
      timeZoneIdentifier: 'Asia/Tokyo',
      medicationOccurrences: [
        _occurrence('m-1', '2026-08-12', MedicationOutcomeStatus.unresolved),
        _occurrence('m-2', '2026-08-12', MedicationOutcomeStatus.administered),
      ],
    );

    expect(
      pack.entriesFor(VetVisitSection.medicationOutcomes).single.label,
      'Medicine',
    );
  });

  test('records outside the range are excluded', () {
    final pack = service.build(
      pet: pet,
      endInstant: DateTime.utc(2026, 8, 13, 3),
      rangeDays: 7,
      timeZoneIdentifier: 'Asia/Tokyo',
      healthRecords: [
        _health('old', DateTime.utc(2026, 7, 1, 1)),
        _health('recent', DateTime.utc(2026, 8, 12, 1)),
      ],
    );

    expect(
      pack.entriesFor(VetVisitSection.healthObservations).single.value,
      'Observation',
    );
    expect(pack.entries.length, 1);
  });

  test('another pet never appears in this pet pack', () {
    final pack = service.build(
      pet: pet,
      endInstant: DateTime.utc(2026, 8, 13, 3),
      rangeDays: 7,
      timeZoneIdentifier: 'Asia/Tokyo',
      healthRecords: [
        _health('other', DateTime.utc(2026, 8, 12, 1), petId: 'pet-2'),
      ],
      medications: [_medication(isActive: true, petId: 'pet-2')],
    );

    expect(pack.isEmpty, isTrue);
  });

  test('missing sections are named so silence is not mistaken for omission', () {
    final pack = service.build(
      pet: pet,
      endInstant: DateTime.utc(2026, 8, 13, 3),
      rangeDays: 7,
      timeZoneIdentifier: 'Asia/Tokyo',
    );

    expect(pack.missingSections, VetVisitSection.values.toSet());
  });

  test('an unconfirmed outcome stays marked in the pack', () {
    final pack = service.build(
      pet: pet,
      endInstant: DateTime.utc(2026, 8, 13, 3),
      rangeDays: 7,
      timeZoneIdentifier: 'Asia/Tokyo',
      medicationOccurrences: [
        _occurrence(
          'm-1',
          '2026-08-12',
          MedicationOutcomeStatus.administered,
          isServerConfirmed: false,
        ),
      ],
    );

    expect(
      pack.entriesFor(VetVisitSection.medicationOutcomes).single
          .isServerConfirmed,
      isFalse,
    );
  });

  test('an unusable timezone yields an empty pack instead of guessed dates', () {
    final pack = service.build(
      pet: pet,
      endInstant: DateTime.utc(2026, 8, 13, 3),
      rangeDays: 7,
      timeZoneIdentifier: 'Not/AZone',
      healthRecords: [_health('h-1', DateTime.utc(2026, 8, 12, 1))],
    );

    expect(pack.fromLocalDate, isNull);
    expect(pack.entriesFor(VetVisitSection.healthObservations), isEmpty);
  });

  test('blank handoff fields are omitted rather than shown as empty lines', () {
    final pack = service.build(
      pet: pet,
      endInstant: DateTime.utc(2026, 8, 13, 3),
      rangeDays: 7,
      timeZoneIdentifier: 'Asia/Tokyo',
      handoff: _handoff(emergencyContactPhone: '   ', careInstructions: ''),
    );

    expect(
      pack.entriesFor(VetVisitSection.emergencyContacts).length,
      3,
    );
    expect(pack.missingSections, contains(VetVisitSection.careInstructions));
  });
}

HouseholdHandoff _handoff({
  String emergencyContactPhone = '090-0000-0000',
  String careInstructions = 'Feed twice a day',
}) => HouseholdHandoff(
  careInstructions: careInstructions,
  emergencyContactName: 'Emergency',
  emergencyContactPhone: emergencyContactPhone,
  veterinaryHospitalName: 'Clinic',
  veterinaryHospitalPhone: '090-1111-1111',
  revision: 2,
  updatedById: 'user-1',
  updatedByNameSnapshot: 'Owner',
  updatedAt: DateTime.utc(2026, 8, 1),
);

Medication _medication({required bool isActive, String petId = 'pet-1'}) =>
    Medication(
      id: 'med-1',
      petId: petId,
      displayName: 'Medicine',
      purpose: 'Prescription record',
      isActive: isActive,
      currentScheduleVersion: 1,
      currentScheduleVersionId: 'v000001',
      revision: 0,
    );

MedicationOccurrence _occurrence(
  String id,
  String localDate,
  MedicationOutcomeStatus outcome, {
  bool isServerConfirmed = true,
}) => MedicationOccurrence(
  id: id,
  medicationId: 'med-1',
  scheduleVersionId: 'v000001',
  scheduleVersion: 1,
  slotId: 'morning',
  localDate: localDate,
  dueAt: DateTime.utc(2026, 8, 12),
  petId: 'pet-1',
  petNameSnapshot: 'Mochi',
  medicationNameSnapshot: 'Medicine',
  doseText: '1 tablet',
  instructions: null,
  responsibilityStatus: MedicationResponsibilityStatus.claimed,
  responsibleById: 'user-1',
  responsibleByNameSnapshot: 'Alex',
  claimedAt: DateTime.utc(2026, 8, 11, 23),
  outcomeStatus: outcome,
  outcomeById: outcome == MedicationOutcomeStatus.unresolved ? null : 'user-1',
  outcomeByNameSnapshot:
      outcome == MedicationOutcomeStatus.unresolved ? null : 'Alex',
  outcomeAt: outcome == MedicationOutcomeStatus.unresolved
      ? null
      : DateTime.utc(2026, 8, 12, 1),
  skippedReasonCode: null,
  skippedReasonNote: null,
  revision: 2,
  isServerConfirmed: isServerConfirmed,
);

HealthRecord _health(String id, DateTime recordedAt, {String petId = 'pet-1'}) =>
    HealthRecord(
      id: id,
      petId: petId,
      petNameSnapshot: 'Mochi',
      type: HealthRecordType.note,
      recordedAt: recordedAt,
      detail: 'Observation',
      weightKilograms: null,
      createdById: 'user-1',
      createdByNameSnapshot: 'Alex',
      createdAt: recordedAt,
    );
