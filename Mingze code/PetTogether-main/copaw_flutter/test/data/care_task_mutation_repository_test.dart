import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:copaw_flutter/src/data/care_task_mutation_gateway.dart';
import 'package:copaw_flutter/src/data/care_task_mutation_repository.dart';
import 'package:copaw_flutter/src/data/firebase_care_task_mutation_repository.dart';
import 'package:copaw_flutter/src/data/household_data_gateway.dart';
import 'package:copaw_flutter/src/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeMutationGateway gateway;
  late FirebaseCareTaskMutationRepository repository;

  setUp(() {
    gateway = FakeMutationGateway();
    repository = FirebaseCareTaskMutationRepository(
      gateway: gateway,
      idGenerator: SequenceMutationIdGenerator(['request-a', 'request-b']),
    );
  });

  test(
    'self claim reads authoritative actor and writes exact overlay',
    () async {
      gateway.task = _task();

      await repository.claim(
        householdId: 'home-a',
        taskId: 'task-a',
        actorId: 'user-a',
      );

      expect(gateway.lastUpdate, {
        'status': 'claimed',
        ..._clearedRequest,
        'assigneeID': 'user-a',
        'assigneeName': 'Authoritative A',
        'claimedAt': gateway.serverTimestamp,
        ..._marker(
          action: 'taskClaimed',
          actorId: 'user-a',
          actorName: 'Authoritative A',
          timestamp: gateway.serverTimestamp,
        ),
        'revision': 1,
      });
    },
  );

  test(
    'persisted routine occurrence uses the same claim transaction',
    () async {
      gateway.task = _task(kind: 'routine', routineId: 'routine-a');

      await repository.claim(
        householdId: 'home-a',
        taskId: 'task-a',
        actorId: 'user-a',
      );

      expect(gateway.lastUpdate?['status'], 'claimed');
      expect(gateway.lastUpdate?['revision'], 1);
    },
  );

  test('virtual routine occurrence is materialized on first claim', () async {
    gateway.task = const StoredDocument(
      id: 'routine-a_2026-08-12',
      exists: false,
    );
    final occurrence = CareTask(
      id: 'routine-a_2026-08-12',
      title: 'Morning meal',
      category: CareCategory.feeding,
      dueTime: DateTime.utc(2026, 8, 12, 1),
      kind: CareTaskKind.routine,
      priority: CarePriority.normal,
      routineId: 'routine-a',
      status: CareTaskStatus.unclaimed,
      assignmentRequest: null,
      assigneeId: null,
      assigneeNameSnapshot: null,
      claimedAt: null,
      createdById: 'user-a',
      createdBy: 'Authoritative A',
      createdAt: DateTime.utc(2026, 8, 1),
      completedById: null,
      completedBy: null,
      completedAt: null,
      revision: 0,
    );

    await repository.claim(
      householdId: 'home-a',
      taskId: occurrence.id,
      actorId: 'user-b',
      taskIfMissing: occurrence,
    );

    expect(gateway.materializeCalls.single, {
      'householdId': 'home-a',
      'routineId': 'routine-a',
      'localDate': '2026-08-12',
      'action': 'claim',
      'recipientId': null,
    });
    expect(gateway.lastUpdate, isNull);
  });

  test(
    'direct and open requests write trusted snapshots and server time',
    () async {
      gateway.task = _task();
      final directId = await repository.requestDirect(
        householdId: 'home-a',
        taskId: 'task-a',
        actorId: 'user-a',
        recipientId: 'user-b',
      );

      expect(directId, 'request-a');
      expect(gateway.lastUpdate, {
        'assignmentRequestID': 'request-a',
        'assignmentMode': 'direct',
        'requestedByID': 'user-a',
        'requestedByName': 'Authoritative A',
        'requestedToID': 'user-b',
        'requestedToName': 'Authoritative B',
        'assignmentRequestedAt': gateway.serverTimestamp,
        ..._marker(
          action: 'taskRequested',
          actorId: 'user-a',
          actorName: 'Authoritative A',
          targetId: 'user-b',
          targetName: 'Authoritative B',
          requestId: 'request-a',
          timestamp: gateway.serverTimestamp,
        ),
        'revision': 1,
      });

      gateway.task = _task();
      final openId = await repository.requestOpen(
        householdId: 'home-a',
        taskId: 'task-a',
        actorId: 'user-a',
      );
      expect(openId, 'request-b');
      expect(gateway.lastUpdate, {
        'assignmentRequestID': 'request-b',
        'assignmentMode': 'open',
        'requestedByID': 'user-a',
        'requestedByName': 'Authoritative A',
        'requestedToID': null,
        'requestedToName': null,
        'assignmentRequestedAt': gateway.serverTimestamp,
        ..._marker(
          action: 'taskRequested',
          actorId: 'user-a',
          actorName: 'Authoritative A',
          requestId: 'request-b',
          timestamp: gateway.serverTimestamp,
        ),
        'revision': 1,
      });
    },
  );

  test('direct recipient accepts then assignee completes', () async {
    gateway.task = _requestedTask();

    await repository.accept(
      householdId: 'home-a',
      taskId: 'task-a',
      actorId: 'user-b',
      requestId: 'request-a',
    );
    expect(gateway.lastUpdate, {
      'status': 'claimed',
      ..._clearedRequest,
      'assigneeID': 'user-b',
      'assigneeName': 'Authoritative B',
      'claimedAt': gateway.serverTimestamp,
      ..._marker(
        action: 'taskAccepted',
        actorId: 'user-b',
        actorName: 'Authoritative B',
        targetId: 'user-a',
        targetName: 'Authoritative A',
        requestId: 'request-a',
        timestamp: gateway.serverTimestamp,
      ),
      'revision': 2,
    });

    await repository.complete(
      householdId: 'home-a',
      taskId: 'task-a',
      actorId: 'user-b',
    );
    expect(gateway.lastUpdate, {
      'status': 'completed',
      'completedByID': 'user-b',
      'completedBy': 'Authoritative B',
      'completedAt': gateway.serverTimestamp,
      ..._marker(
        action: 'taskCompleted',
        actorId: 'user-b',
        actorName: 'Authoritative B',
        timestamp: gateway.serverTimestamp,
      ),
      'revision': 3,
    });
  });

  test(
    'recipient decline and requester cancel only clear request overlay',
    () async {
      gateway.task = _requestedTask();
      await repository.decline(
        householdId: 'home-a',
        taskId: 'task-a',
        actorId: 'user-b',
        requestId: 'request-a',
      );
      expect(gateway.lastUpdate, {
        ..._clearedRequest,
        ..._marker(
          action: 'taskDeclined',
          actorId: 'user-b',
          actorName: 'Authoritative B',
          targetId: 'user-a',
          targetName: 'Authoritative A',
          requestId: 'request-a',
          timestamp: gateway.serverTimestamp,
        ),
        'revision': 2,
      });

      gateway.task = _requestedTask(mode: 'open', recipientId: null);
      await repository.cancel(
        householdId: 'home-a',
        taskId: 'task-a',
        actorId: 'user-a',
        requestId: 'request-a',
      );
      expect(gateway.lastUpdate, {
        ..._clearedRequest,
        ..._marker(
          action: 'taskCancelled',
          actorId: 'user-a',
          actorName: 'Authoritative A',
          requestId: 'request-a',
          timestamp: gateway.serverTimestamp,
        ),
        'revision': 2,
      });
    },
  );

  test('open request can be claimed by another household member', () async {
    gateway.task = _requestedTask(mode: 'open', recipientId: null);

    await repository.claim(
      householdId: 'home-a',
      taskId: 'task-a',
      actorId: 'user-c',
    );

    expect(gateway.lastUpdate?['assigneeID'], 'user-c');
    expect(gateway.lastUpdate?['revision'], 2);
  });

  test('invalid actor and stale request have stable classifications', () async {
    gateway.task = _requestedTask();
    await expectLater(
      repository.accept(
        householdId: 'home-a',
        taskId: 'task-a',
        actorId: 'user-c',
        requestId: 'request-a',
      ),
      _throws(CareTaskMutationErrorCode.invalidActor),
    );
    await expectLater(
      repository.cancel(
        householdId: 'home-a',
        taskId: 'task-a',
        actorId: 'user-a',
        requestId: 'stale',
      ),
      _throws(CareTaskMutationErrorCode.staleRequest),
    );
  });

  test('not found, legacy unsafe, and terminal classify distinctly', () async {
    gateway.task = const StoredDocument(id: 'task-a', exists: false);
    await expectLater(
      repository.claim(
        householdId: 'home-a',
        taskId: 'task-a',
        actorId: 'user-a',
      ),
      _throws(CareTaskMutationErrorCode.notFound),
    );

    gateway.task = _legacyTask();
    await expectLater(
      repository.claim(
        householdId: 'home-a',
        taskId: 'task-a',
        actorId: 'user-a',
      ),
      _throws(CareTaskMutationErrorCode.legacyUnsafe),
    );

    gateway.task = _completedTask();
    await expectLater(
      repository.complete(
        householdId: 'home-a',
        taskId: 'task-a',
        actorId: 'user-a',
      ),
      _throws(CareTaskMutationErrorCode.terminal),
    );
  });

  test('concurrent claims read latest state and only one succeeds', () async {
    gateway.task = _task();
    final results = await Future.wait([
      _capture(
        repository.claim(
          householdId: 'home-a',
          taskId: 'task-a',
          actorId: 'user-a',
        ),
      ),
      _capture(
        repository.claim(
          householdId: 'home-a',
          taskId: 'task-a',
          actorId: 'user-b',
        ),
      ),
    ]);

    expect(results.where((result) => result == null), hasLength(1));
    expect(
      results.whereType<CareTaskMutationException>().single.code,
      CareTaskMutationErrorCode.invalidTransition,
    );
  });

  test('provider network error maps without leaking raw detail', () async {
    gateway.error = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'unavailable',
      message: 'sensitive raw provider detail',
    );
    await expectLater(
      repository.claim(
        householdId: 'home-a',
        taskId: 'task-a',
        actorId: 'user-a',
      ),
      _throws(CareTaskMutationErrorCode.network),
    );
  });
}

Matcher _throws(CareTaskMutationErrorCode code) => throwsA(
  isA<CareTaskMutationException>().having((error) => error.code, 'code', code),
);

Future<Object?> _capture(Future<void> action) async {
  try {
    await action;
    return null;
  } on Object catch (error) {
    return error;
  }
}

StoredDocument _task({String kind = 'oneOff', String? routineId}) =>
    StoredDocument(
      id: 'task-a',
      exists: true,
      data: _baseTask(kind: kind, routineId: routineId),
    );

StoredDocument _requestedTask({
  String mode = 'direct',
  String? recipientId = 'user-b',
}) {
  final data = _baseTask()
    ..addAll({
      'assignmentRequestID': 'request-a',
      'assignmentMode': mode,
      'requestedByID': 'user-a',
      'requestedByName': 'Authoritative A',
      'requestedToID': recipientId,
      'requestedToName': recipientId == null ? null : 'Authoritative B',
      'assignmentRequestedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 12, 9)),
      'revision': 1,
    });
  return StoredDocument(id: 'task-a', exists: true, data: data);
}

StoredDocument _completedTask() {
  final data = _baseTask()
    ..addAll({
      'status': 'completed',
      'assigneeID': 'user-a',
      'assigneeName': 'Authoritative A',
      'claimedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 12, 9)),
      'completedByID': 'user-a',
      'completedBy': 'Authoritative A',
      'completedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 12, 10)),
      'revision': 2,
    });
  return StoredDocument(id: 'task-a', exists: true, data: data);
}

StoredDocument _legacyTask() => StoredDocument(
  id: 'task-a',
  exists: true,
  data: {
    'title': 'Task',
    'category': 'feeding',
    'dueTime': Timestamp.fromDate(DateTime.utc(2026, 8, 12, 10)),
    'status': 'pending',
    'createdBy': 'Legacy caregiver',
  },
);

Map<String, Object?> _baseTask({String kind = 'oneOff', String? routineId}) =>
    <String, Object?>{
      'id': 'task-a',
      'title': 'Task',
      'category': 'feeding',
      'dueTime': Timestamp.fromDate(DateTime.utc(2026, 8, 12, 10)),
      'kind': kind,
      'priority': 'normal',
      'routineID': routineId,
      'petID': 'pet-a',
      'petName': 'Mochi',
      'status': 'unclaimed',
      ..._clearedRequest,
      'assigneeID': null,
      'assigneeName': null,
      'claimedAt': null,
      'createdByID': 'user-a',
      'createdBy': 'Authoritative A',
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 12, 8)),
      'completedByID': null,
      'completedBy': null,
      'completedAt': null,
      'revision': 0,
    };

const _clearedRequest = <String, Object?>{
  'assignmentRequestID': null,
  'assignmentMode': null,
  'requestedByID': null,
  'requestedByName': null,
  'requestedToID': null,
  'requestedToName': null,
  'assignmentRequestedAt': null,
};

final class SequenceMutationIdGenerator implements MutationIdGenerator {
  SequenceMutationIdGenerator(this.ids);

  final List<String> ids;
  int index = 0;

  @override
  String next() => ids[index++];
}

final class FakeMutationGateway implements CareTaskMutationGateway {
  StoredDocument task = _task();
  final members = <String, StoredDocument>{
    'user-a': _member('user-a', 'Authoritative A'),
    'user-b': _member('user-b', 'Authoritative B'),
    'user-c': _member('user-c', 'Authoritative C'),
  };
  final serverTimestamp = Timestamp.fromDate(DateTime.utc(2026, 8, 12, 11));
  Map<String, Object?>? lastUpdate;
  Object? error;
  final materializeCalls = <Map<String, Object?>>[];

  @override
  Future<MaterializedRoutineOccurrence> materializeRoutineOccurrence({
    required String householdId,
    required String routineId,
    required String localDate,
    required String action,
    String? recipientId,
  }) async {
    if (error case final Object value) throw value;
    materializeCalls.add({
      'householdId': householdId,
      'routineId': routineId,
      'localDate': localDate,
      'action': action,
      'recipientId': recipientId,
    });
    return MaterializedRoutineOccurrence(
      taskId: '${routineId}_$localDate',
      requestId: action == 'claim' ? null : 'server-request-a',
    );
  }

  @override
  Future<void> runTaskTransaction({
    required String householdId,
    required String taskId,
    required String actorId,
    String? recipientId,
    required CareTaskMutationTransform transform,
  }) async {
    if (error case final Object value) throw value;
    final update = transform(
      CareTaskMutationContext(
        task: task,
        actor: members[actorId] ?? StoredDocument(id: actorId, exists: false),
        recipient: recipientId == null
            ? null
            : members[recipientId] ??
                  StoredDocument(id: recipientId, exists: false),
        serverTimestamp: serverTimestamp,
      ),
    );
    lastUpdate = Map.unmodifiable(update);
    task = StoredDocument(
      id: task.id,
      exists: true,
      data: {...task.data, ...update},
    );
  }
}

Map<String, Object?> _marker({
  required String action,
  required String actorId,
  required String actorName,
  required Object timestamp,
  String? targetId,
  String? targetName,
  String? requestId,
}) => <String, Object?>{
  'lastCollaborationAction': action,
  'lastCollaborationActorID': actorId,
  'lastCollaborationActorName': actorName,
  'lastCollaborationTargetID': targetId,
  'lastCollaborationTargetName': targetName,
  'lastCollaborationRequestID': requestId,
  'lastCollaborationAt': timestamp,
};

StoredDocument _member(String id, String name) =>
    StoredDocument(id: id, exists: true, data: {'displayName': name});
