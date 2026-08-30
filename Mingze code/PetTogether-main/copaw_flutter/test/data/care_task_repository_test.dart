import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:copaw_flutter/src/data/care_task_gateway.dart';
import 'package:copaw_flutter/src/data/care_task_repository.dart';
import 'package:copaw_flutter/src/data/firebase_care_task_repository.dart';
import 'package:copaw_flutter/src/data/household_data_gateway.dart';
import 'package:copaw_flutter/src/data/household_repository.dart';
import 'package:copaw_flutter/src/domain/legacy_firestore_codec.dart';
import 'package:copaw_flutter/src/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeCareTaskGateway gateway;
  late FirebaseCareTaskRepository repository;

  setUp(() {
    gateway = FakeCareTaskGateway();
    repository = FirebaseCareTaskRepository(gateway: gateway);
  });
  tearDown(() => repository.stopObserving());

  test('combines routine/task streams and preserves diagnostics', () async {
    final events = <CareTaskSnapshot>[];
    repository.observeCare('home-a').listen(events.add);
    await _settle();
    gateway.routines['home-a']!.add(_stored([_routine('routine-a')]));
    gateway.tasks['home-a']!.add(_stored([_legacyTask('task-a')]));
    await _settle();

    expect(events.single.routines.single.id, 'routine-a');
    expect(events.single.tasks.single.id, 'task-a');
    expect(
      events.single.diagnostics.map((item) => item.code),
      contains(DomainDiagnosticCode.legacyUnsafeToMutate),
    );
  });

  test(
    'source authority requires both Firestore streams to be confirmed',
    () async {
      final snapshots = repository.observeCare('home-a');
      final values = <CareTaskSnapshot>[];
      final subscription = snapshots.listen(values.add);
      await _settle();

      gateway.routines['home-a']!.add(
        const StoredCareDocuments(documents: [], isServerConfirmed: false),
      );
      gateway.tasks['home-a']!.add(_stored([]));
      await _settle();
      expect(values.last.isServerConfirmed, isFalse);

      gateway.routines['home-a']!.add(_stored([]));
      await _settle();
      expect(values.last.isServerConfirmed, isTrue);
      await subscription.cancel();
    },
  );

  test('session change cancels old listeners and drops old values', () async {
    final first = <CareTaskSnapshot>[];
    final second = <CareTaskSnapshot>[];
    repository.observeCare('home-a').listen(first.add);
    await _settle();
    repository.observeCare('home-b').listen(second.add);
    await _settle();

    gateway.routines['home-a']!.add(_stored([]));
    gateway.tasks['home-a']!.add(_stored([]));
    gateway.routines['home-b']!.add(_stored([]));
    gateway.tasks['home-b']!.add(_stored([]));
    await _settle();

    expect(first, isEmpty);
    expect(second, hasLength(1));
    expect(gateway.cancelled, containsAll(['r:home-a', 't:home-a']));
  });

  test('create validates, normalizes, and sends one command', () async {
    final due = DateTime.utc(2026, 8, 12, 10);
    final taskId = await repository.createOneOffTask(
      householdId: 'home-a',
      title: ' Vet call ',
      category: CareCategory.medication,
      dueTime: due,
      priority: CarePriority.urgent,
      createdById: 'user-a',
      createdByName: ' Caregiver ',
    );

    expect(gateway.commands, hasLength(1));
    expect(gateway.commands.single.title, 'Vet call');
    expect(gateway.commands.single.category, 'medication');
    expect(gateway.commands.single.priority, 'urgent');
    expect(gateway.commands.single.petId, legacyPrimaryPetId);
    expect(gateway.commands.single.petName, 'Mochi');
    expect(taskId, 'task-a');
  });

  test(
    'strict writer requires and normalizes an explicit pet snapshot',
    () async {
      final writer = repository as PetBoundCareTaskWriter;
      await writer.createOneOffTaskForPet(
        householdId: 'home-a',
        petId: ' pet-b ',
        petName: ' Nori ',
        title: 'Walk',
        category: CareCategory.walking,
        dueTime: DateTime.utc(2026, 8, 12, 10),
        priority: CarePriority.normal,
        createdById: 'user-a',
        createdByName: 'Caregiver',
      );

      expect(gateway.commands.single.petId, 'pet-b');
      expect(gateway.commands.single.petName, 'Nori');

      await expectLater(
        writer.createRoutineForPet(
          householdId: 'home-a',
          petId: 'pet-b',
          petName: ' ',
          title: 'Meal',
          category: CareCategory.feeding,
          priority: CarePriority.normal,
          frequency: CareRoutineFrequency.daily,
          weekdays: const [1, 2, 3, 4, 5, 6, 7],
          hour: 8,
          minute: 0,
          startDate: DateTime.utc(2026, 8, 12),
          timeZoneIdentifier: 'Asia/Tokyo',
          createdById: 'user-a',
          createdByName: 'Caregiver',
        ),
        throwsA(
          isA<HouseholdRepositoryException>().having(
            (error) => error.code,
            'code',
            HouseholdRepositoryErrorCode.invalidInput,
          ),
        ),
      );
    },
  );

  test('invalid create input is rejected before gateway write', () async {
    await expectLater(
      repository.createOneOffTask(
        householdId: 'home-a',
        title: ' ',
        category: CareCategory.other,
        dueTime: DateTime.utc(2026),
        priority: CarePriority.normal,
        createdById: 'user-a',
        createdByName: 'Caregiver',
      ),
      throwsA(
        isA<HouseholdRepositoryException>().having(
          (error) => error.code,
          'code',
          HouseholdRepositoryErrorCode.invalidInput,
        ),
      ),
    );
    expect(gateway.commands, isEmpty);
  });

  test(
    'routine creation validates its canonical schedule before writing',
    () async {
      await expectLater(
        repository.createRoutine(
          householdId: 'home-a',
          title: 'Morning meal',
          category: CareCategory.feeding,
          priority: CarePriority.normal,
          frequency: CareRoutineFrequency.selectedDays,
          weekdays: const [2, 2],
          hour: 8,
          minute: 0,
          startDate: DateTime.utc(2026, 8, 12),
          timeZoneIdentifier: 'Tokyo',
          createdById: 'user-a',
          createdByName: 'Caregiver',
        ),
        throwsA(
          isA<HouseholdRepositoryException>().having(
            (error) => error.code,
            'code',
            HouseholdRepositoryErrorCode.invalidInput,
          ),
        ),
      );
      expect(gateway.routineCommands, isEmpty);
    },
  );

  test('listener network error maps to stable category', () async {
    final errors = <Object>[];
    repository.observeCare('home-a').listen((_) {}, onError: errors.add);
    await _settle();
    gateway.tasks['home-a']!.addError(
      FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
    );
    await _settle();

    expect(
      (errors.single as HouseholdRepositoryException).code,
      HouseholdRepositoryErrorCode.network,
    );
  });
}

StoredDocument _routine(String id) => StoredDocument(
  id: id,
  exists: true,
  data: {
    'title': 'Morning meal',
    'category': 'feeding',
    'priority': 'normal',
    'frequency': 'daily',
    'weekdays': [1, 2, 3, 4, 5, 6, 7],
    'hour': 8,
    'minute': 0,
    'startDate': Timestamp.fromDate(DateTime.utc(2026, 8, 1)),
    'timeZoneIdentifier': 'Asia/Tokyo',
    'createdByID': 'user-a',
    'createdByName': 'Caregiver',
    'isActive': true,
  },
);

StoredDocument _legacyTask(String id) => StoredDocument(
  id: id,
  exists: true,
  data: {
    'title': 'Vet call',
    'category': 'medication',
    'dueTime': Timestamp.fromDate(DateTime.utc(2026, 8, 12, 10)),
    'status': 'pending',
    'createdBy': 'Caregiver',
  },
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

StoredCareDocuments _stored(List<StoredDocument> documents) =>
    StoredCareDocuments(documents: documents, isServerConfirmed: true);

final class FakeCareTaskGateway implements CareTaskGateway {
  final routines = <String, StreamController<StoredCareDocuments>>{};
  final tasks = <String, StreamController<StoredCareDocuments>>{};
  final commands = <CreateOneOffTaskCommand>[];
  final routineCommands = <CreateRoutineCommand>[];
  final cancelled = <String>[];

  @override
  Stream<StoredCareDocuments> observeRoutines(String householdId) {
    final controller = StreamController<StoredCareDocuments>.broadcast(
      onCancel: () => cancelled.add('r:$householdId'),
    );
    routines[householdId] = controller;
    return controller.stream;
  }

  @override
  Stream<StoredCareDocuments> observeTasks(String householdId) {
    final controller = StreamController<StoredCareDocuments>.broadcast(
      onCancel: () => cancelled.add('t:$householdId'),
    );
    tasks[householdId] = controller;
    return controller.stream;
  }

  @override
  String newTaskId(String householdId) => 'task-a';

  @override
  String newRoutineId(String householdId) => 'routine-a';

  @override
  Future<StoredDocument> readHousehold(String householdId) async =>
      StoredDocument(
        id: householdId,
        exists: true,
        data: const {
          'name': 'Home',
          'inviteCode': 'ABC234',
          'petName': 'Mochi',
          'timeZoneIdentifier': 'Asia/Tokyo',
        },
      );

  @override
  Future<void> createOneOffTask(CreateOneOffTaskCommand command) async {
    commands.add(command);
  }

  @override
  Future<void> createRoutine(CreateRoutineCommand command) async {
    routineCommands.add(command);
  }
}
