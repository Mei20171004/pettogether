import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/handoff_models.dart';

final class HandoffSessionSnapshot {
  const HandoffSessionSnapshot({
    required this.activeSession,
    required this.pinnedVersion,
    required this.isFromCache,
    required this.droppedSessionCount,
    required this.droppedVersionCount,
    required this.authorityMalformed,
  });

  final HandoffSession? activeSession;
  final HandoffVersion? pinnedVersion;
  final bool isFromCache;
  final int droppedSessionCount;
  final int droppedVersionCount;
  final bool authorityMalformed;
}

enum HandoffSessionErrorCode {
  invalidInput,
  permission,
  stale,
  notFound,
  blocked,
  network,
  malformedData,
  backendUnavailable,
}

final class HandoffSessionException implements Exception {
  const HandoffSessionException(this.code, {this.diagnosticCode});

  final HandoffSessionErrorCode code;
  final String? diagnosticCode;
}

abstract interface class HandoffSessionRepository {
  Stream<HandoffSessionSnapshot> observeActiveSession(String householdId);

  Future<HandoffSessionMutationResult> offer({
    required String householdId,
    required String recipientId,
    required int expectedHandoffRevision,
    required DateTime plannedStart,
    required DateTime plannedEnd,
    required String clientMutationId,
  });

  Future<HandoffSessionMutationResult> transition({
    required String householdId,
    required String action,
    required String sessionId,
    required int expectedSessionRevision,
    required String clientMutationId,
  });

  Future<void> stopObserving();
}

final handoffSessionRepositoryProvider = Provider<HandoffSessionRepository>((
  ref,
) {
  throw StateError(
    'HandoffSessionRepository must be provided at the app boundary.',
  );
});

final class FakeHandoffSessionRepository implements HandoffSessionRepository {
  FakeHandoffSessionRepository({
    this._snapshot = const HandoffSessionSnapshot(
      activeSession: null,
      pinnedVersion: null,
      isFromCache: false,
      droppedSessionCount: 0,
      droppedVersionCount: 0,
      authorityMalformed: false,
    ),
    this.observeError,
  });

  HandoffSessionSnapshot _snapshot;
  final _controllers = <StreamController<HandoffSessionSnapshot>>[];
  final calls = <Map<String, Object?>>[];
  Object? nextError;
  Object? observeError;

  void replace(HandoffSessionSnapshot snapshot) {
    _snapshot = snapshot;
    for (final controller in List.of(_controllers)) {
      if (!controller.isClosed) controller.add(snapshot);
    }
  }

  @override
  Stream<HandoffSessionSnapshot> observeActiveSession(String householdId) {
    late final StreamController<HandoffSessionSnapshot> controller;
    controller = StreamController(
      onListen: () {
        if (observeError case final error?) {
          controller.addError(error);
        } else {
          controller.add(_snapshot);
        }
      },
      onCancel: () => _controllers.remove(controller),
    );
    _controllers.add(controller);
    return controller.stream;
  }

  Future<HandoffSessionMutationResult> _record(
    Map<String, Object?> call,
  ) async {
    calls.add(call);
    if (nextError case final error?) {
      nextError = null;
      throw error;
    }
    final action = call['action']! as String;
    final status = switch (action) {
      'offer' => HandoffSessionStatus.offered,
      'accept' => HandoffSessionStatus.accepted,
      'decline' => HandoffSessionStatus.declined,
      'cancel' => HandoffSessionStatus.cancelled,
      _ => HandoffSessionStatus.closed,
    };
    final expectedRevision = call['expectedSessionRevision'] as int?;
    final active =
        status == HandoffSessionStatus.offered ||
        status == HandoffSessionStatus.accepted;
    final sessionId = call['sessionID'] as String? ?? 'fake-session';
    return HandoffSessionMutationResult(
      sessionId: sessionId,
      sessionRevision: action == 'offer' ? 1 : expectedRevision! + 1,
      sessionStatus: status,
      activeSessionId: active ? sessionId : null,
      versionId: action == 'offer'
          ? 'v${(call['expectedHandoffRevision']! as int).toString().padLeft(6, '0')}'
          : _snapshot.activeSession?.versionId ?? 'v000001',
      existing: false,
    );
  }

  @override
  Future<HandoffSessionMutationResult> offer({
    required String householdId,
    required String recipientId,
    required int expectedHandoffRevision,
    required DateTime plannedStart,
    required DateTime plannedEnd,
    required String clientMutationId,
  }) => _record({
    'householdID': householdId,
    'action': 'offer',
    'recipientID': recipientId,
    'expectedHandoffRevision': expectedHandoffRevision,
    'plannedStartMilliseconds': plannedStart.millisecondsSinceEpoch,
    'plannedEndMilliseconds': plannedEnd.millisecondsSinceEpoch,
    'clientMutationID': clientMutationId,
  });

  @override
  Future<HandoffSessionMutationResult> transition({
    required String householdId,
    required String action,
    required String sessionId,
    required int expectedSessionRevision,
    required String clientMutationId,
  }) => _record({
    'householdID': householdId,
    'action': action,
    'sessionID': sessionId,
    'expectedSessionRevision': expectedSessionRevision,
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
