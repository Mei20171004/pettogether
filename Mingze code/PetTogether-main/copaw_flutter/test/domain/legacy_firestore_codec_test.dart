import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:copaw_flutter/src/domain/legacy_firestore_codec.dart';
import 'package:copaw_flutter/src/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const codec = LegacyFirestoreCodec();
  final dueTime = DateTime.utc(2026, 8, 12, 9, 30);
  final createdAt = DateTime.utc(2026, 8, 10, 12);

  group('pet codec', () {
    test('canonical pet round trips with document ID authority', () {
      final pet = Pet(
        id: 'pet-a',
        name: 'Mochi',
        species: PetSpecies.dog,
        isArchived: true,
        createdAt: createdAt,
        updatedAt: dueTime,
      );

      final encoded = codec.encodePetStorageFields(pet)..['id'] = 'stale-id';
      final result = codec.decodePet('pet-a', encoded);

      expect(result.value?.id, 'pet-a');
      expect(result.value?.species, PetSpecies.dog);
      expect(result.value?.isArchived, isTrue);
      expect(result.value?.createdAt, createdAt);
      expect(result.value?.updatedAt, dueTime);
      expect(result.diagnostics, isEmpty);
    });

    test('rabbit is canonical while unknown species is malformed', () {
      final canonical = <String, Object?>{
        'id': 'pet-a',
        'name': 'Mochi',
        'species': null,
        'isArchived': false,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(createdAt),
      };

      expect(codec.decodePet('pet-a', canonical).value?.species, isNull);
      expect(
        codec
            .decodePet('pet-a', {...canonical, 'species': 'rabbit'})
            .value
            ?.species,
        PetSpecies.rabbit,
      );
      expect(
        codec.decodePet('pet-a', {...canonical, 'species': 'hamster'}).value,
        isNull,
      );
    });

    test('canonical encoder rejects synthesized legacy pets', () {
      const pet = Pet(
        id: legacyPrimaryPetId,
        name: 'Mochi',
        species: null,
        isArchived: false,
        createdAt: null,
        updatedAt: null,
      );

      expect(pet.isSynthesizedLegacy, isTrue);
      expect(() => codec.encodePetStorageFields(pet), throwsArgumentError);
    });
  });

  group('household codec', () {
    test('canonical document ID is authoritative over stored id', () {
      final result = codec.decodeHousehold('document-household', {
        'id': 'stale-stored-id',
        'name': 'Home',
        'inviteCode': 'ABC123',
        'petName': 'Mochi',
        'timeZoneIdentifier': 'Asia/Tokyo',
      });

      expect(result.value?.id, 'document-household');
      expect(result.value?.timeZoneIdentifier, 'Asia/Tokyo');
      expect(result.value?.legacyNeedsTimezone, isFalse);
      expect(result.diagnostics, isEmpty);
    });

    test('legacy missing timezone remains readable and requires repair', () {
      final result = codec.decodeHousehold('household-1', {
        'name': 'Home',
        'inviteCode': 'ABC123',
        'petName': 'Mochi',
      });

      expect(result.hasValue, isTrue);
      expect(result.value?.legacyNeedsTimezone, isTrue);
      expect(result.value?.timeZoneIdentifier, isNull);
      expect(
        result.diagnostics.single.code,
        DomainDiagnosticCode.legacyNeedsTimezone,
      );
    });

    test('invalid timezone is marked and cannot be written canonically', () {
      final result = codec.decodeHousehold('household-1', {
        'name': 'Home',
        'inviteCode': 'ABC123',
        'petName': 'Mochi',
        'timeZoneIdentifier': '',
      });

      expect(result.value?.legacyNeedsTimezone, isTrue);
      expect(
        () => codec.encodeHouseholdStorageFields(result.value!),
        throwsArgumentError,
      );
    });
  });

  group('caregiver codec', () {
    test('canonical decode and encode use document ID', () {
      final result = codec.decodeCaregiver('member-1', {
        'id': 'stale-member-id',
        'displayName': 'Alex',
      });

      expect(result.value?.id, 'member-1');
      expect(result.value?.displayName, 'Alex');
      expect(
        codec.encodeCaregiverStorageFields(result.value!)['id'],
        'member-1',
      );
    });

    test('missing display name returns observable malformed result', () {
      final result = codec.decodeCaregiver('member-1', const {});

      expect(result.value, isNull);
      expect(
        result.diagnostics.single.code,
        DomainDiagnosticCode.malformedData,
      );
    });
  });

  group('routine codec', () {
    test('canonical writer round trips all fields', () {
      final routine = CareRoutine(
        id: 'routine-1',
        title: 'Breakfast',
        category: CareCategory.feeding,
        priority: CarePriority.urgent,
        frequency: CareRoutineFrequency.selectedDays,
        weekdays: const [2, 4, 6],
        hour: 7,
        minute: 15,
        startDate: createdAt,
        timeZoneIdentifier: 'Asia/Tokyo',
        createdById: 'member-1',
        createdByNameSnapshot: 'Alex',
        isActive: true,
        petId: 'pet-a',
        petNameSnapshot: 'Mochi',
      );

      final result = codec.decodeRoutine(
        routine.id,
        codec.encodeRoutineStorageFields(routine),
      );

      expect(result.diagnostics, isEmpty);
      expect(result.value?.frequency, CareRoutineFrequency.selectedDays);
      expect(result.value?.weekdays, [2, 4, 6]);
      expect(result.value?.priority, CarePriority.urgent);
      expect(result.value?.startDate, createdAt);
      expect(result.value?.petId, 'pet-a');
      expect(result.value?.petNameSnapshot, 'Mochi');
    });

    test('legacy missing frequency and weekdays receives daily defaults', () {
      final result = codec.decodeRoutine('routine-document-id', {
        'id': 'stale-routine-id',
        'title': 'Breakfast',
        'category': 'feeding',
        'priority': 'normal',
        'hour': 7,
        'minute': 15,
        'startDate': Timestamp.fromDate(createdAt),
        'timeZoneIdentifier': 'Asia/Tokyo',
        'createdByID': 'member-1',
        'createdByName': 'Alex',
        'isActive': true,
      });

      expect(result.value?.id, 'routine-document-id');
      expect(result.value?.frequency, CareRoutineFrequency.daily);
      expect(result.value?.weekdays, [1, 2, 3, 4, 5, 6, 7]);
      expect(result.value?.petId, legacyPrimaryPetId);
      expect(result.value?.petNameSnapshot, isNull);
      expect(result.diagnostics, isEmpty);
    });

    test('missing required legacy fields returns malformed result', () {
      final data = _canonicalRoutineData(createdAt)
        ..remove('timeZoneIdentifier');

      final result = codec.decodeRoutine('routine-1', data);

      expect(result.value, isNull);
      expect(
        result.diagnostics.single.code,
        DomainDiagnosticCode.malformedData,
      );
    });

    test(
      'integral numbers decode while fractional and duplicate weekdays fail',
      () {
        final integralNumber = _canonicalRoutineData(createdAt)..['hour'] = 7.0;
        final fractionalNumber = _canonicalRoutineData(createdAt)
          ..['hour'] = 7.5;
        final wrongWeekday = _canonicalRoutineData(createdAt)
          ..['weekdays'] = [0, 8];
        final duplicateWeekday = _canonicalRoutineData(createdAt)
          ..['weekdays'] = [2, 2];

        expect(codec.decodeRoutine('routine-1', integralNumber).value?.hour, 7);
        expect(
          codec.decodeRoutine('routine-1', fractionalNumber).value,
          isNull,
        );
        expect(codec.decodeRoutine('routine-1', wrongWeekday).value, isNull);
        expect(
          codec.decodeRoutine('routine-1', duplicateWeekday).value,
          isNull,
        );
      },
    );
  });

  group('task codec', () {
    test(
      'canonical no-request writer round trips with explicit null overlays',
      () {
        final task = _task(
          dueTime: dueTime,
          createdAt: createdAt,
          status: CareTaskStatus.unclaimed,
        );

        final encoded = codec.encodeTaskStorageFields(task);
        const nullableKeys = {
          'routineID',
          'assignmentRequestID',
          'assignmentMode',
          'requestedByID',
          'requestedByName',
          'requestedToID',
          'requestedToName',
          'assignmentRequestedAt',
          'assigneeID',
          'assigneeName',
          'claimedAt',
          'completedByID',
          'completedBy',
          'completedAt',
        };
        for (final key in nullableKeys) {
          expect(
            encoded.containsKey(key),
            isTrue,
            reason: '$key must be explicit',
          );
          expect(encoded[key], isNull, reason: '$key must be null');
        }

        final result = codec.decodeTask(task.id, encoded);
        expect(result.value?.id, task.id);
        expect(result.value?.status, CareTaskStatus.unclaimed);
        expect(result.value?.assignmentRequest, isNull);
        expect(result.value?.createdAt, createdAt);
        expect(result.value?.petId, 'pet-a');
        expect(result.value?.petNameSnapshot, 'Mochi');
        expect(result.diagnostics, isEmpty);
      },
    );

    test('canonical direct request round trips', () {
      final requestTime = DateTime.utc(2026, 8, 11, 8);
      final task = _task(
        dueTime: dueTime,
        createdAt: createdAt,
        status: CareTaskStatus.unclaimed,
        assignmentRequest: AssignmentRequest(
          id: 'request-1',
          requestedById: 'member-1',
          requestedByNameSnapshot: 'Alex',
          requestedToId: 'member-2',
          requestedToNameSnapshot: 'Sam',
          mode: AssignmentMode.direct,
          createdAt: requestTime,
        ),
      );

      final result = codec.decodeTask(
        task.id,
        codec.encodeTaskStorageFields(task),
      );

      expect(result.diagnostics, isEmpty);
      expect(result.value?.assignmentRequest?.mode, AssignmentMode.direct);
      expect(result.value?.assignmentRequest?.requestedToId, 'member-2');
      expect(result.value?.assignmentRequest?.createdAt, requestTime);
    });

    test('legacy pending and missing fields use compatibility defaults', () {
      final result = codec.decodeTask('task-document-id', {
        'id': 'stale-task-id',
        'title': 'Walk',
        'category': 'walking',
        'dueTime': Timestamp.fromDate(dueTime),
        'status': 'pending',
        'createdBy': 'Alex',
      });

      expect(result.value?.id, 'task-document-id');
      expect(result.value?.status, CareTaskStatus.unclaimed);
      expect(result.value?.kind, CareTaskKind.oneOff);
      expect(result.value?.priority, CarePriority.normal);
      expect(result.value?.createdAt, dueTime);
      expect(result.value?.revision, 0);
      expect(result.value?.petId, legacyPrimaryPetId);
      expect(result.value?.petNameSnapshot, isNull);
      expect(
        result.diagnostics.map((item) => item.code),
        contains(DomainDiagnosticCode.legacyUnsafeToMutate),
      );
    });

    test('unknown legacy kind and priority also default safely', () {
      final data = _canonicalTaskData(dueTime, createdAt)
        ..['kind'] = 'futureKind'
        ..['priority'] = 'futurePriority';

      final result = codec.decodeTask('task-1', data);

      expect(result.value?.kind, CareTaskKind.oneOff);
      expect(result.value?.priority, CarePriority.normal);
      expect(
        result.diagnostics.map((item) => item.code),
        contains(DomainDiagnosticCode.legacyUnsafeToMutate),
      );
    });

    test('missing request mode is inferred for open and direct requests', () {
      final openData = _canonicalTaskData(dueTime, createdAt)
        ..addAll(_requestOverlay(dueTime));
      final directData = _canonicalTaskData(dueTime, createdAt)
        ..addAll({
          ..._requestOverlay(dueTime),
          'requestedToID': 'member-2',
          'requestedToName': 'Sam',
        });

      expect(
        codec.decodeTask('open-task', openData).value?.assignmentRequest?.mode,
        AssignmentMode.open,
      );
      expect(
        codec
            .decodeTask('direct-task', directData)
            .value
            ?.assignmentRequest
            ?.mode,
        AssignmentMode.direct,
      );
    });

    test('partial request remains readable with malformed diagnostic', () {
      final data = _canonicalTaskData(dueTime, createdAt)
        ..['assignmentRequestID'] = 'request-1'
        ..['requestedByID'] = 'member-1';

      final result = codec.decodeTask('task-1', data);

      expect(result.hasValue, isTrue);
      expect(result.value?.assignmentRequest, isNull);
      expect(
        result.diagnostics.map((item) => item.code),
        contains(DomainDiagnosticCode.partialAssignmentRequest),
      );
      expect(
        result.diagnostics.map((item) => item.code),
        contains(DomainDiagnosticCode.legacyUnsafeToMutate),
      );
    });

    test('claimed and completed canonical states decode', () {
      final claimed = _canonicalTaskData(dueTime, createdAt)
        ..['status'] = 'claimed'
        ..['assigneeID'] = 'member-2'
        ..['assigneeName'] = 'Sam'
        ..['claimedAt'] = Timestamp.fromDate(dueTime);
      final completed = Map<String, Object?>.from(claimed)
        ..['status'] = 'completed'
        ..['completedByID'] = 'member-2'
        ..['completedBy'] = 'Sam'
        ..['completedAt'] = Timestamp.fromDate(dueTime);

      expect(
        codec.decodeTask('claimed', claimed).value?.status,
        CareTaskStatus.claimed,
      );
      expect(
        codec.decodeTask('completed', completed).value?.status,
        CareTaskStatus.completed,
      );
    });

    test('inconsistent claimed state remains visible with diagnostic', () {
      final claimed = _canonicalTaskData(dueTime, createdAt)
        ..['status'] = 'claimed';

      final result = codec.decodeTask('claimed', claimed);

      expect(result.value?.status, CareTaskStatus.claimed);
      expect(
        result.diagnostics.map((item) => item.code),
        contains(DomainDiagnosticCode.malformedData),
      );
      expect(
        result.diagnostics.map((item) => item.code),
        contains(DomainDiagnosticCode.legacyUnsafeToMutate),
      );
    });

    test('canonical storage writer rejects unsafe task state', () {
      final invalid = CareTask(
        id: 'task-1',
        title: 'Walk',
        category: CareCategory.walking,
        dueTime: dueTime,
        kind: CareTaskKind.oneOff,
        priority: CarePriority.normal,
        routineId: null,
        status: CareTaskStatus.claimed,
        assignmentRequest: null,
        assigneeId: null,
        assigneeNameSnapshot: null,
        claimedAt: null,
        createdById: 'member-1',
        createdBy: 'Alex',
        createdAt: createdAt,
        completedById: null,
        completedBy: null,
        completedAt: null,
        revision: 1,
      );

      expect(() => codec.encodeTaskStorageFields(invalid), throwsArgumentError);
    });

    test('unknown status and wrong required timestamp are malformed', () {
      final unknownStatus = _canonicalTaskData(dueTime, createdAt)
        ..['status'] = 'futureStatus';
      final wrongTimestamp = _canonicalTaskData(dueTime, createdAt)
        ..['dueTime'] = dueTime.toIso8601String();

      expect(codec.decodeTask('task-1', unknownStatus).value, isNull);
      expect(codec.decodeTask('task-1', wrongTimestamp).value, isNull);
    });

    test('fractional revision is malformed', () {
      final data = _canonicalTaskData(dueTime, createdAt)..['revision'] = 1.5;

      final result = codec.decodeTask('task-1', data);

      expect(result.value, isNull);
      expect(
        result.diagnostics.single.code,
        DomainDiagnosticCode.malformedData,
      );
    });
  });
}

Map<String, Object?> _canonicalRoutineData(DateTime startDate) =>
    <String, Object?>{
      'id': 'routine-1',
      'title': 'Breakfast',
      'category': 'feeding',
      'priority': 'normal',
      'frequency': 'daily',
      'weekdays': [1, 2, 3, 4, 5, 6, 7],
      'hour': 7,
      'minute': 15,
      'startDate': Timestamp.fromDate(startDate),
      'timeZoneIdentifier': 'Asia/Tokyo',
      'createdByID': 'member-1',
      'createdByName': 'Alex',
      'isActive': true,
    };

Map<String, Object?> _canonicalTaskData(DateTime dueTime, DateTime createdAt) =>
    <String, Object?>{
      'id': 'task-1',
      'title': 'Walk',
      'category': 'walking',
      'dueTime': Timestamp.fromDate(dueTime),
      'kind': 'oneOff',
      'priority': 'normal',
      'routineID': null,
      'status': 'unclaimed',
      'assignmentRequestID': null,
      'assignmentMode': null,
      'requestedByID': null,
      'requestedByName': null,
      'requestedToID': null,
      'requestedToName': null,
      'assignmentRequestedAt': null,
      'assigneeID': null,
      'assigneeName': null,
      'claimedAt': null,
      'createdByID': 'member-1',
      'createdBy': 'Alex',
      'createdAt': Timestamp.fromDate(createdAt),
      'completedByID': null,
      'completedBy': null,
      'completedAt': null,
      'revision': 0,
      'petID': 'pet-a',
      'petName': 'Mochi',
    };

Map<String, Object?> _requestOverlay(DateTime requestedAt) => <String, Object?>{
  'assignmentRequestID': 'request-1',
  'assignmentMode': null,
  'requestedByID': 'member-1',
  'requestedByName': 'Alex',
  'requestedToID': null,
  'requestedToName': null,
  'assignmentRequestedAt': Timestamp.fromDate(requestedAt),
};

CareTask _task({
  required DateTime dueTime,
  required DateTime createdAt,
  required CareTaskStatus status,
  AssignmentRequest? assignmentRequest,
}) => CareTask(
  id: 'task-1',
  title: 'Walk',
  category: CareCategory.walking,
  dueTime: dueTime,
  kind: CareTaskKind.oneOff,
  priority: CarePriority.normal,
  routineId: null,
  status: status,
  assignmentRequest: assignmentRequest,
  assigneeId: null,
  assigneeNameSnapshot: null,
  claimedAt: null,
  createdById: 'member-1',
  createdBy: 'Alex',
  createdAt: createdAt,
  completedById: null,
  completedBy: null,
  completedAt: null,
  revision: 0,
  petId: 'pet-a',
  petNameSnapshot: 'Mochi',
);
