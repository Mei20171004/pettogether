import 'dart:math';

import 'package:firebase_core/firebase_core.dart';

import '../domain/legacy_firestore_codec.dart';
import '../domain/models.dart';
import 'care_task_mutation_gateway.dart';
import 'care_task_mutation_repository.dart';
import 'firebase_care_task_mutation_gateway.dart';
import 'household_data_gateway.dart';

final class FirebaseCareTaskMutationRepository
    implements CareTaskMutationRepository {
  FirebaseCareTaskMutationRepository({
    CareTaskMutationGateway? gateway,
    MutationIdGenerator? idGenerator,
  }) : _gateway = gateway ?? FirebaseCareTaskMutationGateway(),
       _idGenerator = idGenerator ?? RandomMutationIdGenerator();

  final CareTaskMutationGateway _gateway;
  final MutationIdGenerator _idGenerator;
  final LegacyFirestoreCodec _codec = const LegacyFirestoreCodec();

  @override
  Future<void> claim({
    required String householdId,
    required String taskId,
    required String actorId,
    CareTask? taskIfMissing,
  }) async {
    if (taskIfMissing != null) {
      await _materialize(
        householdId: householdId,
        taskId: taskId,
        actorId: actorId,
        task: taskIfMissing,
        action: 'claim',
      );
      return;
    }
    return _run(
      householdId: householdId,
      taskId: taskId,
      actorId: actorId,
      transform: (context, task, actor, _) {
        _requireUnclaimed(task);
        final request = task.assignmentRequest;
        if (request?.mode == AssignmentMode.direct &&
            request?.requestedById != actor.id &&
            request?.requestedToId != actor.id) {
          throw const CareTaskMutationException(
            CareTaskMutationErrorCode.invalidActor,
          );
        }
        return _claimPayload(
          task,
          actor,
          context.serverTimestamp,
          eventAction: 'taskClaimed',
        );
      },
    );
  }

  @override
  Future<String> requestDirect({
    required String householdId,
    required String taskId,
    required String actorId,
    required String recipientId,
    CareTask? taskIfMissing,
  }) async {
    if (recipientId == actorId) {
      throw const CareTaskMutationException(
        CareTaskMutationErrorCode.invalidActor,
      );
    }
    if (taskIfMissing != null) {
      final result = await _materialize(
        householdId: householdId,
        taskId: taskId,
        actorId: actorId,
        task: taskIfMissing,
        action: 'requestDirect',
        recipientId: recipientId,
      );
      return result.requestId!;
    }
    final requestId = _idGenerator.next();
    await _run(
      householdId: householdId,
      taskId: taskId,
      actorId: actorId,
      recipientId: recipientId,
      transform: (context, task, actor, recipient) {
        _requireUnclaimedWithoutRequest(task);
        if (recipient == null) {
          throw const CareTaskMutationException(
            CareTaskMutationErrorCode.invalidActor,
          );
        }
        return _requestPayload(
          task: task,
          requestId: requestId,
          actor: actor,
          recipient: recipient,
          serverTimestamp: context.serverTimestamp,
        );
      },
    );
    return requestId;
  }

  @override
  Future<String> requestOpen({
    required String householdId,
    required String taskId,
    required String actorId,
    CareTask? taskIfMissing,
  }) async {
    if (taskIfMissing != null) {
      final result = await _materialize(
        householdId: householdId,
        taskId: taskId,
        actorId: actorId,
        task: taskIfMissing,
        action: 'requestOpen',
      );
      return result.requestId!;
    }
    final requestId = _idGenerator.next();
    await _run(
      householdId: householdId,
      taskId: taskId,
      actorId: actorId,
      transform: (context, task, actor, _) {
        _requireUnclaimedWithoutRequest(task);
        return _requestPayload(
          task: task,
          requestId: requestId,
          actor: actor,
          recipient: null,
          serverTimestamp: context.serverTimestamp,
        );
      },
    );
    return requestId;
  }

  @override
  Future<void> accept({
    required String householdId,
    required String taskId,
    required String actorId,
    required String requestId,
  }) {
    return _run(
      householdId: householdId,
      taskId: taskId,
      actorId: actorId,
      transform: (context, task, actor, _) {
        final request = _requireRequest(task, requestId);
        if (request.mode != AssignmentMode.direct ||
            request.requestedToId != actor.id) {
          throw const CareTaskMutationException(
            CareTaskMutationErrorCode.invalidActor,
          );
        }
        return _claimPayload(
          task,
          actor,
          context.serverTimestamp,
          eventAction: 'taskAccepted',
        );
      },
    );
  }

  @override
  Future<void> decline({
    required String householdId,
    required String taskId,
    required String actorId,
    required String requestId,
  }) {
    return _run(
      householdId: householdId,
      taskId: taskId,
      actorId: actorId,
      transform: (context, task, actor, _) {
        final request = _requireRequest(task, requestId);
        if (request.mode != AssignmentMode.direct ||
            request.requestedToId != actor.id) {
          throw const CareTaskMutationException(
            CareTaskMutationErrorCode.invalidActor,
          );
        }
        return <String, Object?>{
          ..._clearedRequest,
          ..._collaborationMarker(
            action: 'taskDeclined',
            actor: actor,
            timestamp: context.serverTimestamp,
            targetId: request.requestedById,
            targetName: request.requestedByNameSnapshot,
            requestId: request.id,
          ),
          'revision': task.revision + 1,
        };
      },
    );
  }

  @override
  Future<void> cancel({
    required String householdId,
    required String taskId,
    required String actorId,
    required String requestId,
  }) {
    return _run(
      householdId: householdId,
      taskId: taskId,
      actorId: actorId,
      transform: (context, task, actor, _) {
        final request = _requireRequest(task, requestId);
        if (request.requestedById != actor.id) {
          throw const CareTaskMutationException(
            CareTaskMutationErrorCode.invalidActor,
          );
        }
        return <String, Object?>{
          ..._clearedRequest,
          ..._collaborationMarker(
            action: 'taskCancelled',
            actor: actor,
            timestamp: context.serverTimestamp,
            targetId: request.requestedToId,
            targetName: request.requestedToNameSnapshot,
            requestId: request.id,
          ),
          'revision': task.revision + 1,
        };
      },
    );
  }

  @override
  Future<void> complete({
    required String householdId,
    required String taskId,
    required String actorId,
  }) {
    return _run(
      householdId: householdId,
      taskId: taskId,
      actorId: actorId,
      transform: (context, task, actor, _) {
        if (task.status == CareTaskStatus.completed) {
          throw const CareTaskMutationException(
            CareTaskMutationErrorCode.terminal,
          );
        }
        if (task.status != CareTaskStatus.claimed) {
          throw const CareTaskMutationException(
            CareTaskMutationErrorCode.invalidTransition,
          );
        }
        if (task.assigneeId != actor.id) {
          throw const CareTaskMutationException(
            CareTaskMutationErrorCode.invalidActor,
          );
        }
        return <String, Object?>{
          'status': 'completed',
          'completedByID': actor.id,
          'completedBy': actor.displayName,
          'completedAt': context.serverTimestamp,
          ..._collaborationMarker(
            action: 'taskCompleted',
            actor: actor,
            timestamp: context.serverTimestamp,
          ),
          'revision': task.revision + 1,
        };
      },
    );
  }

  Future<void> _run({
    required String householdId,
    required String taskId,
    required String actorId,
    String? recipientId,
    required Map<String, Object?> Function(
      CareTaskMutationContext context,
      CareTask task,
      Caregiver actor,
      Caregiver? recipient,
    )
    transform,
  }) async {
    if (householdId.isEmpty || taskId.isEmpty || actorId.isEmpty) {
      throw const CareTaskMutationException(
        CareTaskMutationErrorCode.invalidActor,
      );
    }
    try {
      await _gateway.runTaskTransaction(
        householdId: householdId,
        taskId: taskId,
        actorId: actorId,
        recipientId: recipientId,
        transform: (context) {
          final task = _decodeTaskForMutation(context);
          final actor = _decodeMember(context.actor);
          final recipient = context.recipient == null
              ? null
              : _decodeMember(context.recipient!);
          return transform(context, task, actor, recipient);
        },
      );
    } on Object catch (error) {
      throw _mapped(error);
    }
  }

  CareTask _decodeTaskForMutation(CareTaskMutationContext context) {
    if (!context.task.exists) {
      throw const CareTaskMutationException(CareTaskMutationErrorCode.notFound);
    }
    final result = _codec.decodeTask(context.task.id, context.task.data);
    if (result.value == null ||
        result.diagnostics.any(
          (item) =>
              item.code == DomainDiagnosticCode.legacyUnsafeToMutate ||
              item.code == DomainDiagnosticCode.malformedData ||
              item.code == DomainDiagnosticCode.partialAssignmentRequest,
        )) {
      throw const CareTaskMutationException(
        CareTaskMutationErrorCode.legacyUnsafe,
      );
    }
    return result.value!;
  }

  Caregiver _decodeMember(StoredDocument document) {
    if (!document.exists) {
      throw const CareTaskMutationException(
        CareTaskMutationErrorCode.invalidActor,
      );
    }
    final result = _codec.decodeCaregiver(document.id, document.data);
    if (result.value == null) {
      throw const CareTaskMutationException(
        CareTaskMutationErrorCode.invalidActor,
      );
    }
    return result.value!;
  }

  static void _requireUnclaimed(CareTask task) {
    if (task.status == CareTaskStatus.completed) {
      throw const CareTaskMutationException(CareTaskMutationErrorCode.terminal);
    }
    if (task.status != CareTaskStatus.unclaimed) {
      throw const CareTaskMutationException(
        CareTaskMutationErrorCode.invalidTransition,
      );
    }
  }

  static void _requireUnclaimedWithoutRequest(CareTask task) {
    _requireUnclaimed(task);
    if (task.assignmentRequest != null) {
      throw const CareTaskMutationException(
        CareTaskMutationErrorCode.staleRequest,
      );
    }
  }

  static AssignmentRequest _requireRequest(CareTask task, String requestId) {
    _requireUnclaimed(task);
    final request = task.assignmentRequest;
    if (request == null || request.id != requestId) {
      throw const CareTaskMutationException(
        CareTaskMutationErrorCode.staleRequest,
      );
    }
    return request;
  }

  static Map<String, Object?> _claimPayload(
    CareTask task,
    Caregiver actor,
    Object serverTimestamp, {
    required String eventAction,
  }) => <String, Object?>{
    'status': 'claimed',
    ..._clearedRequest,
    'assigneeID': actor.id,
    'assigneeName': actor.displayName,
    'claimedAt': serverTimestamp,
    ..._collaborationMarker(
      action: eventAction,
      actor: actor,
      timestamp: serverTimestamp,
      targetId: task.assignmentRequest?.requestedById,
      targetName: task.assignmentRequest?.requestedByNameSnapshot,
      requestId: task.assignmentRequest?.id,
    ),
    'revision': task.revision + 1,
  };

  static Map<String, Object?> _requestPayload({
    required CareTask task,
    required String requestId,
    required Caregiver actor,
    required Caregiver? recipient,
    required Object serverTimestamp,
  }) => <String, Object?>{
    'assignmentRequestID': requestId,
    'assignmentMode': recipient == null ? 'open' : 'direct',
    'requestedByID': actor.id,
    'requestedByName': actor.displayName,
    'requestedToID': recipient?.id,
    'requestedToName': recipient?.displayName,
    'assignmentRequestedAt': serverTimestamp,
    ..._collaborationMarker(
      action: 'taskRequested',
      actor: actor,
      timestamp: serverTimestamp,
      targetId: recipient?.id,
      targetName: recipient?.displayName,
      requestId: requestId,
    ),
    'revision': task.revision + 1,
  };

  static Map<String, Object?> _collaborationMarker({
    required String action,
    required Caregiver actor,
    required Object timestamp,
    String? targetId,
    String? targetName,
    String? requestId,
  }) => <String, Object?>{
    'lastCollaborationAction': action,
    'lastCollaborationActorID': actor.id,
    'lastCollaborationActorName': actor.displayName,
    'lastCollaborationTargetID': targetId,
    'lastCollaborationTargetName': targetName,
    'lastCollaborationRequestID': requestId,
    'lastCollaborationAt': timestamp,
  };

  Future<MaterializedRoutineOccurrence> _materialize({
    required String householdId,
    required String taskId,
    required String actorId,
    required CareTask task,
    required String action,
    String? recipientId,
  }) async {
    if (householdId.isEmpty ||
        actorId.isEmpty ||
        task.kind != CareTaskKind.routine ||
        task.routineId == null ||
        task.id != taskId ||
        task.status != CareTaskStatus.unclaimed ||
        task.revision != 0) {
      throw const CareTaskMutationException(CareTaskMutationErrorCode.notFound);
    }
    final prefix = '${task.routineId}_';
    final localDate = taskId.startsWith(prefix)
        ? taskId.substring(prefix.length)
        : '';
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(localDate)) {
      throw const CareTaskMutationException(CareTaskMutationErrorCode.notFound);
    }
    try {
      return await _gateway.materializeRoutineOccurrence(
        householdId: householdId,
        routineId: task.routineId!,
        localDate: localDate,
        action: action,
        recipientId: recipientId,
      );
    } on Object catch (error) {
      throw _mapped(error);
    }
  }

  static const _clearedRequest = <String, Object?>{
    'assignmentRequestID': null,
    'assignmentMode': null,
    'requestedByID': null,
    'requestedByName': null,
    'requestedToID': null,
    'requestedToName': null,
    'assignmentRequestedAt': null,
  };

  static CareTaskMutationException _mapped(Object error) {
    if (error is CareTaskMutationException) return error;
    if (error is FirebaseException) {
      return CareTaskMutationException(switch (error.code) {
        'network-request-failed' ||
        'unavailable' => CareTaskMutationErrorCode.network,
        'permission-denied' ||
        'unauthenticated' => CareTaskMutationErrorCode.permission,
        'not-found' => CareTaskMutationErrorCode.notFound,
        'already-exists' ||
        'failed-precondition' ||
        'aborted' => CareTaskMutationErrorCode.invalidTransition,
        'invalid-argument' => CareTaskMutationErrorCode.invalidActor,
        _ => CareTaskMutationErrorCode.backendUnavailable,
      });
    }
    return const CareTaskMutationException(
      CareTaskMutationErrorCode.backendUnavailable,
    );
  }
}

final class RandomMutationIdGenerator implements MutationIdGenerator {
  RandomMutationIdGenerator({Random? random})
    : _random = random ?? Random.secure();

  final Random _random;

  @override
  String next() =>
      List.generate(24, (_) => _random.nextInt(16).toRadixString(16)).join();
}
