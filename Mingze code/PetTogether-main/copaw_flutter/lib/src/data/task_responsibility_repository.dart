import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/responsibility_models.dart';

final class TaskResponsibilitySnapshot {
  const TaskResponsibilitySnapshot({
    required this.pendingByTaskId,
    required this.isFromCache,
    required this.droppedTransferCount,
    this.authorityMalformed = false,
  });

  final Map<String, ResponsibilityTransfer> pendingByTaskId;
  final bool isFromCache;
  final int droppedTransferCount;
  final bool authorityMalformed;
}

enum TaskResponsibilityErrorCode {
  invalidInput,
  permission,
  stale,
  notFound,
  blocked,
  unsafeLegacy,
  network,
  malformedData,
  backendUnavailable,
}

final class TaskResponsibilityException implements Exception {
  const TaskResponsibilityException(this.code, {this.diagnosticCode});

  final TaskResponsibilityErrorCode code;
  final String? diagnosticCode;
}

abstract interface class TaskResponsibilityRepository {
  Stream<TaskResponsibilitySnapshot> observeTransfers(String householdId);

  Future<TaskResponsibilityMutationResult> release({
    required String householdId,
    required String taskId,
    required int expectedTaskRevision,
    required String clientMutationId,
  });

  Future<TaskResponsibilityMutationResult> requestReassign({
    required String householdId,
    required String taskId,
    required String targetMemberId,
    required int expectedTaskRevision,
    required String clientMutationId,
  });

  Future<TaskResponsibilityMutationResult> requestTakeover({
    required String householdId,
    required String taskId,
    required int expectedTaskRevision,
    required String clientMutationId,
  });

  Future<TaskResponsibilityMutationResult> resolveTransfer({
    required String householdId,
    required String taskId,
    required String action,
    required String transferId,
    required int expectedTaskRevision,
    required int expectedTransferRevision,
    required String clientMutationId,
  });

  Future<TaskResponsibilityMutationResult> complete({
    required String householdId,
    required String taskId,
    required int expectedTaskRevision,
    required String clientMutationId,
  });

  Future<void> stopObserving();
}

final taskResponsibilityRepositoryProvider =
    Provider<TaskResponsibilityRepository>((ref) {
      throw StateError(
        'TaskResponsibilityRepository must be provided at the app boundary.',
      );
    });

final class FakeTaskResponsibilityRepository
    implements TaskResponsibilityRepository {
  FakeTaskResponsibilityRepository({
    this._snapshot = const TaskResponsibilitySnapshot(
      pendingByTaskId: {},
      isFromCache: false,
      droppedTransferCount: 0,
    ),
  });

  TaskResponsibilitySnapshot _snapshot;
  final _controllers = <StreamController<TaskResponsibilitySnapshot>>[];
  final calls = <Map<String, Object?>>[];
  Object? nextError;

  void replace(TaskResponsibilitySnapshot snapshot) {
    _snapshot = snapshot;
    for (final controller in List.of(_controllers)) {
      if (!controller.isClosed) controller.add(snapshot);
    }
  }

  @override
  Stream<TaskResponsibilitySnapshot> observeTransfers(String householdId) {
    late final StreamController<TaskResponsibilitySnapshot> controller;
    controller = StreamController(
      onListen: () => controller.add(_snapshot),
      onCancel: () => _controllers.remove(controller),
    );
    _controllers.add(controller);
    return controller.stream;
  }

  Future<TaskResponsibilityMutationResult> _record(
    Map<String, Object?> call,
  ) async {
    calls.add(call);
    if (nextError case final error?) {
      nextError = null;
      throw error;
    }
    final action = call['action']! as String;
    final expectedTaskRevision = call['expectedTaskRevision']! as int;
    final expectedTransferRevision = call['expectedTransferRevision'] as int?;
    final transferRequested =
        action == 'requestReassign' || action == 'requestTakeover';
    final transferResolved = const {
      'acceptTransfer',
      'declineTransfer',
      'cancelTransfer',
    }.contains(action);
    final taskStatus = switch (action) {
      'release' => TaskResponsibilityStatus.unclaimed,
      'complete' => TaskResponsibilityStatus.completed,
      _ => TaskResponsibilityStatus.claimed,
    };
    final transferStatus = switch (action) {
      'acceptTransfer' => ResponsibilityTransferStatus.accepted,
      'declineTransfer' => ResponsibilityTransferStatus.declined,
      'cancelTransfer' => ResponsibilityTransferStatus.cancelled,
      _ when transferRequested => ResponsibilityTransferStatus.pending,
      _ => null,
    };
    final pending = _snapshot.pendingByTaskId[call['taskID']! as String];
    final assigneeId = switch (action) {
      'release' => null,
      'acceptTransfer' => pending?.responsibilityToId ?? 'fake-assignee',
      'declineTransfer' ||
      'cancelTransfer' => pending?.responsibilityFromId ?? 'fake-assignee',
      _ => 'fake-assignee',
    };
    return TaskResponsibilityMutationResult(
      taskId: call['taskID']! as String,
      taskRevision:
          action == 'release' ||
              action == 'complete' ||
              action == 'acceptTransfer'
          ? expectedTaskRevision + 1
          : expectedTaskRevision,
      taskStatus: taskStatus,
      assigneeId: assigneeId,
      transferId: transferRequested
          ? 'fake-transfer'
          : transferResolved
          ? call['transferID']! as String
          : null,
      transferRevision: transferRequested
          ? 1
          : transferResolved
          ? expectedTransferRevision! + 1
          : null,
      transferStatus: transferStatus,
      existing: false,
    );
  }

  @override
  Future<TaskResponsibilityMutationResult> release({
    required String householdId,
    required String taskId,
    required int expectedTaskRevision,
    required String clientMutationId,
  }) => _record({
    'householdID': householdId,
    'taskID': taskId,
    'action': 'release',
    'expectedTaskRevision': expectedTaskRevision,
    'clientMutationID': clientMutationId,
  });

  @override
  Future<TaskResponsibilityMutationResult> requestReassign({
    required String householdId,
    required String taskId,
    required String targetMemberId,
    required int expectedTaskRevision,
    required String clientMutationId,
  }) => _record({
    'householdID': householdId,
    'taskID': taskId,
    'action': 'requestReassign',
    'targetMemberID': targetMemberId,
    'expectedTaskRevision': expectedTaskRevision,
    'clientMutationID': clientMutationId,
  });

  @override
  Future<TaskResponsibilityMutationResult> requestTakeover({
    required String householdId,
    required String taskId,
    required int expectedTaskRevision,
    required String clientMutationId,
  }) => _record({
    'householdID': householdId,
    'taskID': taskId,
    'action': 'requestTakeover',
    'expectedTaskRevision': expectedTaskRevision,
    'clientMutationID': clientMutationId,
  });

  @override
  Future<TaskResponsibilityMutationResult> resolveTransfer({
    required String householdId,
    required String taskId,
    required String action,
    required String transferId,
    required int expectedTaskRevision,
    required int expectedTransferRevision,
    required String clientMutationId,
  }) => _record({
    'householdID': householdId,
    'taskID': taskId,
    'action': action,
    'transferID': transferId,
    'expectedTaskRevision': expectedTaskRevision,
    'expectedTransferRevision': expectedTransferRevision,
    'clientMutationID': clientMutationId,
  });

  @override
  Future<TaskResponsibilityMutationResult> complete({
    required String householdId,
    required String taskId,
    required int expectedTaskRevision,
    required String clientMutationId,
  }) => _record({
    'householdID': householdId,
    'taskID': taskId,
    'action': 'complete',
    'expectedTaskRevision': expectedTaskRevision,
    'clientMutationID': clientMutationId,
  });

  @override
  Future<void> stopObserving() async {
    for (final controller in List.of(_controllers)) {
      await controller.close();
    }
    _controllers.clear();
  }
}
