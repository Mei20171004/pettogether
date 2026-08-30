import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:copaw_flutter/src/data/firebase_task_responsibility_repository.dart';
import 'package:copaw_flutter/src/data/task_responsibility_gateway.dart';
import 'package:copaw_flutter/src/data/task_responsibility_repository.dart';
import 'package:copaw_flutter/src/domain/responsibility_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakeGateway gateway;
  late FirebaseTaskResponsibilityRepository repository;

  setUp(() {
    gateway = _FakeGateway();
    repository = FirebaseTaskResponsibilityRepository(gateway: gateway);
  });

  tearDown(() => repository.stopObserving());

  test('strictly decodes the pending transfer sidecar', () async {
    gateway.snapshot = StoredResponsibilityTransferSnapshot(
      documents: [
        StoredResponsibilityTransferDocument(
          id: 'transfer-a',
          data: _transfer(),
        ),
      ],
      pointers: [_pointer()],
      isFromCache: true,
    );

    final snapshot = await repository.observeTransfers('home-a').first;

    final transfer = snapshot.pendingByTaskId['task-a']!;
    expect(snapshot.isFromCache, isTrue);
    expect(snapshot.droppedTransferCount, 0);
    expect(transfer.kind, ResponsibilityTransferKind.reassign);
    expect(transfer.consentById, 'user-b');
    expect(transfer.taskRevisionAtProposal, 4);
  });

  test('malformed and duplicate pending authority is not guessed', () async {
    gateway.snapshot = StoredResponsibilityTransferSnapshot(
      documents: [
        StoredResponsibilityTransferDocument(
          id: 'transfer-a',
          data: _transfer(),
        ),
        StoredResponsibilityTransferDocument(
          id: 'transfer-b',
          data: _transfer(id: 'transfer-b'),
        ),
        StoredResponsibilityTransferDocument(
          id: 'bad',
          data: {
            ..._transfer(id: 'bad'),
            'unexpected': true,
          },
        ),
      ],
      pointers: [_pointer()],
      isFromCache: false,
    );

    final snapshot = await repository.observeTransfers('home-a').first;

    expect(snapshot.pendingByTaskId, isEmpty);
    expect(snapshot.droppedTransferCount, 2);
  });

  test('pointer mismatch blocks pending responsibility authority', () async {
    gateway.snapshot = StoredResponsibilityTransferSnapshot(
      documents: [
        StoredResponsibilityTransferDocument(
          id: 'transfer-a',
          data: _transfer(),
        ),
      ],
      pointers: [
        StoredResponsibilityPointerDocument(
          id: 'task-a',
          data: {..._pointer().data, 'transferID': 'different-transfer'},
        ),
      ],
      isFromCache: false,
    );

    final snapshot = await repository.observeTransfers('home-a').first;

    expect(snapshot.pendingByTaskId, isEmpty);
    expect(snapshot.authorityMalformed, isTrue);
  });

  test('sends exact callable payload and strictly decodes response', () async {
    gateway.response = _response();

    final result = await repository.requestReassign(
      householdId: 'home-a',
      taskId: 'task-a',
      targetMemberId: 'user-b',
      expectedTaskRevision: 4,
      clientMutationId: 'mutation-a',
    );

    expect(gateway.payload, {
      'householdID': 'home-a',
      'taskID': 'task-a',
      'action': 'requestReassign',
      'expectedTaskRevision': 4,
      'clientMutationID': 'mutation-a',
      'targetMemberID': 'user-b',
    });
    expect(result.transferId, 'transfer-a');
    expect(result.transferStatus, ResponsibilityTransferStatus.pending);
    expect(result.existing, isFalse);
  });

  test('identical retry preserves caller mutation ID', () async {
    gateway.response = _response(existing: false);
    await repository.complete(
      householdId: 'home-a',
      taskId: 'task-a',
      expectedTaskRevision: 4,
      clientMutationId: 'stable-id',
    );
    gateway.response = _response(existing: true);
    await repository.complete(
      householdId: 'home-a',
      taskId: 'task-a',
      expectedTaskRevision: 4,
      clientMutationId: 'stable-id',
    );

    expect(gateway.payloads, hasLength(2));
    expect(
      gateway.payloads.map((item) => item['clientMutationID']),
      everyElement('stable-id'),
    );
  });

  test('stale and offline callable failures remain distinct', () async {
    gateway.error = FirebaseFunctionsException(
      code: 'aborted',
      message: 'stale',
    );
    await expectLater(
      repository.release(
        householdId: 'home-a',
        taskId: 'task-a',
        expectedTaskRevision: 4,
        clientMutationId: 'mutation-a',
      ),
      _throws(TaskResponsibilityErrorCode.stale),
    );

    gateway.error = FirebaseFunctionsException(
      code: 'unavailable',
      message: 'offline',
    );
    await expectLater(
      repository.release(
        householdId: 'home-a',
        taskId: 'task-a',
        expectedTaskRevision: 4,
        clientMutationId: 'mutation-a',
      ),
      _throws(TaskResponsibilityErrorCode.network),
    );
  });

  test(
    'deterministic fake returns action-aware results without source mutation',
    () async {
      gateway.snapshot = StoredResponsibilityTransferSnapshot(
        documents: [
          StoredResponsibilityTransferDocument(
            id: 'transfer-a',
            data: _transfer(),
          ),
        ],
        pointers: [_pointer()],
        isFromCache: false,
      );
      final source = await repository.observeTransfers('home-a').first;
      final fake = FakeTaskResponsibilityRepository(snapshot: source);
      final before = await fake.observeTransfers('home-a').first;
      final released = await fake.release(
        householdId: 'home-a',
        taskId: 'task-a',
        expectedTaskRevision: 4,
        clientMutationId: 'release-a',
      );
      final proposed = await fake.requestReassign(
        householdId: 'home-a',
        taskId: 'task-a',
        targetMemberId: 'user-b',
        expectedTaskRevision: 4,
        clientMutationId: 'request-a',
      );
      final accepted = await fake.resolveTransfer(
        householdId: 'home-a',
        taskId: 'task-a',
        action: 'acceptTransfer',
        transferId: 'transfer-a',
        expectedTaskRevision: 4,
        expectedTransferRevision: 1,
        clientMutationId: 'accept-a',
      );
      final after = await fake.observeTransfers('home-a').first;

      expect(released.taskStatus, TaskResponsibilityStatus.unclaimed);
      expect(released.taskRevision, 5);
      expect(released.assigneeId, isNull);
      expect(proposed.taskStatus, TaskResponsibilityStatus.claimed);
      expect(proposed.taskRevision, 4);
      expect(proposed.transferStatus, ResponsibilityTransferStatus.pending);
      expect(proposed.transferRevision, 1);
      expect(accepted.taskRevision, 5);
      expect(accepted.assigneeId, 'user-b');
      expect(accepted.transferStatus, ResponsibilityTransferStatus.accepted);
      expect(accepted.transferRevision, 2);
      expect(after.pendingByTaskId, same(before.pendingByTaskId));
    },
  );
}

Matcher _throws(TaskResponsibilityErrorCode code) => throwsA(
  isA<TaskResponsibilityException>().having(
    (error) => error.code,
    'code',
    code,
  ),
);

Map<String, Object?> _transfer({String id = 'transfer-a'}) => {
  'schemaVersion': 1,
  'id': id,
  'taskID': 'task-a',
  'kind': 'reassign',
  'status': 'pending',
  'requestedByID': 'user-a',
  'requestedByName': 'Alex',
  'consentByID': 'user-b',
  'consentByName': 'Blair',
  'responsibilityFromID': 'user-a',
  'responsibilityFromName': 'Alex',
  'responsibilityToID': 'user-b',
  'responsibilityToName': 'Blair',
  'taskRevisionAtProposal': 4,
  'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 17)),
  'resolvedByID': null,
  'resolvedByName': null,
  'resolvedAt': null,
  'resultingTaskRevision': null,
  'revision': 1,
};

Map<String, Object?> _response({bool existing = false}) => {
  'taskID': 'task-a',
  'taskRevision': 4,
  'taskStatus': 'claimed',
  'assigneeID': 'user-a',
  'transferID': 'transfer-a',
  'transferRevision': 1,
  'transferStatus': 'pending',
  'existing': existing,
};

StoredResponsibilityPointerDocument _pointer() =>
    StoredResponsibilityPointerDocument(
      id: 'task-a',
      data: {
        'schemaVersion': 1,
        'taskID': 'task-a',
        'transferID': 'transfer-a',
        'taskRevisionAtProposal': 4,
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 8, 17)),
      },
    );

final class _FakeGateway implements TaskResponsibilityGateway {
  StoredResponsibilityTransferSnapshot snapshot =
      const StoredResponsibilityTransferSnapshot(
        documents: [],
        isFromCache: false,
      );
  Map<String, Object?> response = _response();
  Object? error;
  final payloads = <Map<String, Object?>>[];
  Map<String, Object?>? get payload => payloads.lastOrNull;

  @override
  Stream<StoredResponsibilityTransferSnapshot> observeTransfers(
    String householdId,
  ) => Stream.value(snapshot);

  @override
  Future<Map<String, Object?>> mutate(Map<String, Object?> payload) async {
    payloads.add(payload);
    if (error case final caught?) {
      error = null;
      throw caught;
    }
    return response;
  }
}
