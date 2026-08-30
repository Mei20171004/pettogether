import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../domain/responsibility_models.dart';
import 'firebase_task_responsibility_gateway.dart';
import 'task_responsibility_gateway.dart';
import 'task_responsibility_repository.dart';

final class FirebaseTaskResponsibilityRepository
    implements TaskResponsibilityRepository {
  FirebaseTaskResponsibilityRepository({TaskResponsibilityGateway? gateway})
    : _gateway = gateway ?? FirebaseTaskResponsibilityGateway();

  static const _transferKeys = {
    'schemaVersion',
    'id',
    'taskID',
    'kind',
    'status',
    'requestedByID',
    'requestedByName',
    'consentByID',
    'consentByName',
    'responsibilityFromID',
    'responsibilityFromName',
    'responsibilityToID',
    'responsibilityToName',
    'taskRevisionAtProposal',
    'createdAt',
    'resolvedByID',
    'resolvedByName',
    'resolvedAt',
    'resultingTaskRevision',
    'revision',
  };
  static const _responseKeys = {
    'taskID',
    'taskRevision',
    'taskStatus',
    'assigneeID',
    'transferID',
    'transferRevision',
    'transferStatus',
    'existing',
  };
  static const _pointerKeys = {
    'schemaVersion',
    'taskID',
    'transferID',
    'taskRevisionAtProposal',
    'createdAt',
  };

  final TaskResponsibilityGateway _gateway;
  StreamSubscription<StoredResponsibilityTransferSnapshot>? _subscription;
  StreamController<TaskResponsibilitySnapshot>? _controller;

  @override
  Stream<TaskResponsibilitySnapshot> observeTransfers(String householdId) {
    if (!_id(householdId)) {
      return Stream.error(
        const TaskResponsibilityException(
          TaskResponsibilityErrorCode.invalidInput,
        ),
      );
    }
    final controller = StreamController<TaskResponsibilitySnapshot>();
    unawaited(_replaceObservation(householdId, controller));
    return controller.stream;
  }

  Future<void> _replaceObservation(
    String householdId,
    StreamController<TaskResponsibilitySnapshot> controller,
  ) async {
    await stopObserving();
    _controller = controller;
    _subscription = _gateway.observeTransfers(householdId).listen((snapshot) {
      final pending = <String, ResponsibilityTransfer>{};
      final conflictedTaskIds = <String>{};
      var dropped = 0;
      for (final document in snapshot.documents) {
        try {
          final transfer = _decodeTransfer(document);
          if (transfer.status != ResponsibilityTransferStatus.pending) continue;
          if (pending.containsKey(transfer.taskId) ||
              conflictedTaskIds.contains(transfer.taskId)) {
            dropped += 1;
            pending.remove(transfer.taskId);
            conflictedTaskIds.add(transfer.taskId);
          } else {
            pending[transfer.taskId] = transfer;
          }
        } on FormatException {
          dropped += 1;
        }
      }
      var authorityMalformed = false;
      final pointers = <String, _ResponsibilityPointer>{};
      for (final document in snapshot.pointers) {
        try {
          final pointer = _decodePointer(document);
          if (pointers.containsKey(pointer.taskId)) {
            authorityMalformed = true;
          } else {
            pointers[pointer.taskId] = pointer;
          }
        } on FormatException {
          authorityMalformed = true;
        }
      }
      for (final entry in Map.of(pending).entries) {
        final pointer = pointers.remove(entry.key);
        final transfer = entry.value;
        if (pointer == null ||
            pointer.transferId != transfer.id ||
            pointer.taskRevisionAtProposal != transfer.taskRevisionAtProposal ||
            !pointer.createdAt.isAtSameMomentAs(transfer.createdAt)) {
          authorityMalformed = true;
          pending.remove(entry.key);
        }
      }
      if (pointers.isNotEmpty) authorityMalformed = true;
      controller.add(
        TaskResponsibilitySnapshot(
          pendingByTaskId: Map.unmodifiable(pending),
          isFromCache: snapshot.isFromCache,
          droppedTransferCount: dropped,
          authorityMalformed: authorityMalformed,
        ),
      );
    }, onError: (Object error) => controller.addError(_mapped(error)));
  }

  @override
  Future<TaskResponsibilityMutationResult> release({
    required String householdId,
    required String taskId,
    required int expectedTaskRevision,
    required String clientMutationId,
  }) => _mutate(
    householdId: householdId,
    taskId: taskId,
    action: 'release',
    expectedTaskRevision: expectedTaskRevision,
    clientMutationId: clientMutationId,
  );

  @override
  Future<TaskResponsibilityMutationResult> requestReassign({
    required String householdId,
    required String taskId,
    required String targetMemberId,
    required int expectedTaskRevision,
    required String clientMutationId,
  }) {
    if (!_id(targetMemberId)) return _invalidResult();
    return _mutate(
      householdId: householdId,
      taskId: taskId,
      action: 'requestReassign',
      expectedTaskRevision: expectedTaskRevision,
      clientMutationId: clientMutationId,
      extras: {'targetMemberID': targetMemberId},
    );
  }

  @override
  Future<TaskResponsibilityMutationResult> requestTakeover({
    required String householdId,
    required String taskId,
    required int expectedTaskRevision,
    required String clientMutationId,
  }) => _mutate(
    householdId: householdId,
    taskId: taskId,
    action: 'requestTakeover',
    expectedTaskRevision: expectedTaskRevision,
    clientMutationId: clientMutationId,
  );

  @override
  Future<TaskResponsibilityMutationResult> resolveTransfer({
    required String householdId,
    required String taskId,
    required String action,
    required String transferId,
    required int expectedTaskRevision,
    required int expectedTransferRevision,
    required String clientMutationId,
  }) {
    if (!const {
          'acceptTransfer',
          'declineTransfer',
          'cancelTransfer',
        }.contains(action) ||
        !_id(transferId) ||
        expectedTransferRevision < 1) {
      return _invalidResult();
    }
    return _mutate(
      householdId: householdId,
      taskId: taskId,
      action: action,
      expectedTaskRevision: expectedTaskRevision,
      clientMutationId: clientMutationId,
      extras: {
        'transferID': transferId,
        'expectedTransferRevision': expectedTransferRevision,
      },
    );
  }

  @override
  Future<TaskResponsibilityMutationResult> complete({
    required String householdId,
    required String taskId,
    required int expectedTaskRevision,
    required String clientMutationId,
  }) => _mutate(
    householdId: householdId,
    taskId: taskId,
    action: 'complete',
    expectedTaskRevision: expectedTaskRevision,
    clientMutationId: clientMutationId,
  );

  Future<TaskResponsibilityMutationResult> _mutate({
    required String householdId,
    required String taskId,
    required String action,
    required int expectedTaskRevision,
    required String clientMutationId,
    Map<String, Object?> extras = const {},
  }) async {
    if (!_id(householdId) ||
        !_id(taskId) ||
        expectedTaskRevision < 0 ||
        !_mutationId(clientMutationId)) {
      return _invalidResult();
    }
    try {
      final response = await _gateway.mutate({
        'householdID': householdId,
        'taskID': taskId,
        'action': action,
        'expectedTaskRevision': expectedTaskRevision,
        'clientMutationID': clientMutationId,
        ...extras,
      });
      return _decodeResponse(response);
    } on Object catch (error) {
      throw _mapped(error);
    }
  }

  static Future<TaskResponsibilityMutationResult> _invalidResult() =>
      Future.error(
        const TaskResponsibilityException(
          TaskResponsibilityErrorCode.invalidInput,
        ),
      );

  @override
  Future<void> stopObserving() async {
    final subscription = _subscription;
    final controller = _controller;
    _subscription = null;
    _controller = null;
    await subscription?.cancel();
    await controller?.close();
  }

  static ResponsibilityTransfer _decodeTransfer(
    StoredResponsibilityTransferDocument document,
  ) {
    final data = document.data;
    final kind = _enumByName(ResponsibilityTransferKind.values, data['kind']);
    final status = _enumByName(
      ResponsibilityTransferStatus.values,
      data['status'],
    );
    final createdAt = data['createdAt'];
    final resolvedAt = data['resolvedAt'];
    final terminal =
        status != null && status != ResponsibilityTransferStatus.pending;
    final participantShapeValid = kind == ResponsibilityTransferKind.reassign
        ? data['requestedByID'] == data['responsibilityFromID'] &&
              data['consentByID'] == data['responsibilityToID']
        : data['requestedByID'] == data['responsibilityToID'] &&
              data['consentByID'] == data['responsibilityFromID'];
    if (data.length != _transferKeys.length ||
        !data.keys.every(_transferKeys.contains) ||
        data['schemaVersion'] != 1 ||
        data['id'] != document.id ||
        !_id(document.id) ||
        !_id(data['taskID']) ||
        kind == null ||
        status == null ||
        !_memberPair(data['requestedByID'], data['requestedByName']) ||
        !_memberPair(data['consentByID'], data['consentByName']) ||
        !_memberPair(
          data['responsibilityFromID'],
          data['responsibilityFromName'],
        ) ||
        !_memberPair(
          data['responsibilityToID'],
          data['responsibilityToName'],
        ) ||
        data['responsibilityFromID'] == data['responsibilityToID'] ||
        !participantShapeValid ||
        data['taskRevisionAtProposal'] is! int ||
        (data['taskRevisionAtProposal'] as int) < 0 ||
        createdAt is! Timestamp ||
        !_nullableMemberPair(data['resolvedByID'], data['resolvedByName']) ||
        (resolvedAt != null && resolvedAt is! Timestamp) ||
        (data['resultingTaskRevision'] != null &&
            (data['resultingTaskRevision'] is! int ||
                (data['resultingTaskRevision'] as int) < 0)) ||
        data['revision'] != (terminal ? 2 : 1) ||
        (!terminal &&
            (data['resolvedByID'] != null ||
                resolvedAt != null ||
                data['resultingTaskRevision'] != null)) ||
        (terminal && (data['resolvedByID'] == null || resolvedAt == null)) ||
        (status == ResponsibilityTransferStatus.accepted &&
            data['resolvedByID'] != data['consentByID']) ||
        (status == ResponsibilityTransferStatus.declined &&
            data['resolvedByID'] != data['consentByID']) ||
        (status == ResponsibilityTransferStatus.cancelled &&
            data['resolvedByID'] != data['requestedByID']) ||
        (status == ResponsibilityTransferStatus.superseded &&
            data['resolvedByID'] != data['responsibilityFromID']) ||
        ((status == ResponsibilityTransferStatus.accepted ||
                status == ResponsibilityTransferStatus.superseded) !=
            (data['resultingTaskRevision'] != null))) {
      throw const FormatException('Malformed responsibility transfer');
    }
    return ResponsibilityTransfer(
      id: document.id,
      taskId: data['taskID']! as String,
      kind: kind,
      status: status,
      requestedById: data['requestedByID']! as String,
      requestedByNameSnapshot: data['requestedByName']! as String,
      consentById: data['consentByID']! as String,
      consentByNameSnapshot: data['consentByName']! as String,
      responsibilityFromId: data['responsibilityFromID']! as String,
      responsibilityFromNameSnapshot: data['responsibilityFromName']! as String,
      responsibilityToId: data['responsibilityToID']! as String,
      responsibilityToNameSnapshot: data['responsibilityToName']! as String,
      taskRevisionAtProposal: data['taskRevisionAtProposal']! as int,
      createdAt: createdAt.toDate(),
      resolvedById: data['resolvedByID'] as String?,
      resolvedByNameSnapshot: data['resolvedByName'] as String?,
      resolvedAt: (resolvedAt as Timestamp?)?.toDate(),
      resultingTaskRevision: data['resultingTaskRevision'] as int?,
      revision: data['revision']! as int,
    );
  }

  static _ResponsibilityPointer _decodePointer(
    StoredResponsibilityPointerDocument document,
  ) {
    final data = document.data;
    final createdAt = data['createdAt'];
    if (data.length != _pointerKeys.length ||
        !data.keys.every(_pointerKeys.contains) ||
        data['schemaVersion'] != 1 ||
        data['taskID'] != document.id ||
        !_id(document.id) ||
        !_id(data['transferID']) ||
        data['taskRevisionAtProposal'] is! int ||
        (data['taskRevisionAtProposal'] as int) < 0 ||
        createdAt is! Timestamp) {
      throw const FormatException('Malformed responsibility pointer');
    }
    return _ResponsibilityPointer(
      taskId: document.id,
      transferId: data['transferID']! as String,
      taskRevisionAtProposal: data['taskRevisionAtProposal']! as int,
      createdAt: createdAt.toDate(),
    );
  }

  static TaskResponsibilityMutationResult _decodeResponse(
    Map<String, Object?> data,
  ) {
    final status = _enumByName(
      TaskResponsibilityStatus.values,
      data['taskStatus'],
    );
    final transferStatus = data['transferStatus'] == null
        ? null
        : _enumByName(
            ResponsibilityTransferStatus.values,
            data['transferStatus'],
          );
    if (data.length != _responseKeys.length ||
        !data.keys.every(_responseKeys.contains) ||
        !_id(data['taskID']) ||
        data['taskRevision'] is! int ||
        (data['taskRevision'] as int) < 0 ||
        status == null ||
        ((status == TaskResponsibilityStatus.unclaimed) !=
            (data['assigneeID'] == null)) ||
        (data['assigneeID'] != null && !_id(data['assigneeID'])) ||
        (data['transferID'] != null && !_id(data['transferID'])) ||
        (data['transferRevision'] != null &&
            (data['transferRevision'] is! int ||
                (data['transferRevision'] as int) < 1)) ||
        (data['transferStatus'] != null && transferStatus == null) ||
        ((data['transferID'] == null) != (data['transferRevision'] == null)) ||
        ((data['transferID'] == null) != (transferStatus == null)) ||
        data['existing'] is! bool) {
      throw const TaskResponsibilityException(
        TaskResponsibilityErrorCode.malformedData,
      );
    }
    return TaskResponsibilityMutationResult(
      taskId: data['taskID']! as String,
      taskRevision: data['taskRevision']! as int,
      taskStatus: status,
      assigneeId: data['assigneeID'] as String?,
      transferId: data['transferID'] as String?,
      transferRevision: data['transferRevision'] as int?,
      transferStatus: transferStatus,
      existing: data['existing']! as bool,
    );
  }

  static T? _enumByName<T extends Enum>(Iterable<T> values, Object? value) =>
      value is String
      ? values.where((item) => item.name == value).firstOrNull
      : null;

  static bool _id(Object? value) =>
      value is String &&
      value.isNotEmpty &&
      value.length <= 128 &&
      !value.contains('/');

  static bool _text(Object? value, int maximum) =>
      value is String && value.trim().isNotEmpty && value.length <= maximum;

  static bool _memberPair(Object? id, Object? name) =>
      _id(id) && _text(name, 50);

  static bool _nullableMemberPair(Object? id, Object? name) =>
      (id == null && name == null) || _memberPair(id, name);

  static bool _mutationId(String value) =>
      value.isNotEmpty && value.length <= 128 && !value.contains('/');

  static TaskResponsibilityException _mapped(Object error) {
    if (error is TaskResponsibilityException) return error;
    final code = switch (error) {
      FirebaseFunctionsException() => error.code,
      FirebaseException() => error.code,
      _ => 'unknown',
    };
    final details = error is FirebaseFunctionsException ? error.details : null;
    final diagnosticValue = details is Map
        ? details['code'] ?? details['reason']
        : null;
    final diagnostic = diagnosticValue is String ? diagnosticValue : null;
    return TaskResponsibilityException(switch (code) {
      'invalid-argument' => TaskResponsibilityErrorCode.invalidInput,
      'permission-denied' ||
      'unauthenticated' => TaskResponsibilityErrorCode.permission,
      'aborted' => TaskResponsibilityErrorCode.stale,
      'not-found' => TaskResponsibilityErrorCode.notFound,
      'failed-precondition' when diagnostic == 'unsafe-legacy-task' =>
        TaskResponsibilityErrorCode.unsafeLegacy,
      'failed-precondition' => TaskResponsibilityErrorCode.blocked,
      'unavailable' ||
      'deadline-exceeded' ||
      'network-request-failed' => TaskResponsibilityErrorCode.network,
      'data-loss' => TaskResponsibilityErrorCode.malformedData,
      _ => TaskResponsibilityErrorCode.backendUnavailable,
    }, diagnosticCode: diagnostic);
  }
}

final class _ResponsibilityPointer {
  const _ResponsibilityPointer({
    required this.taskId,
    required this.transferId,
    required this.taskRevisionAtProposal,
    required this.createdAt,
  });

  final String taskId;
  final String transferId;
  final int taskRevisionAtProposal;
  final DateTime createdAt;
}
