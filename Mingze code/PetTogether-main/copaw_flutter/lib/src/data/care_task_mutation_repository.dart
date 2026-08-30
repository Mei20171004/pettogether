import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';

final careTaskMutationRepositoryProvider = Provider<CareTaskMutationRepository>(
  (ref) {
    throw StateError(
      'CareTaskMutationRepository must be provided at the app boundary.',
    );
  },
);

enum CareTaskMutationErrorCode {
  notFound,
  invalidActor,
  staleRequest,
  legacyUnsafe,
  terminal,
  invalidTransition,
  network,
  permission,
  backendUnavailable,
}

final class CareTaskMutationException implements Exception {
  const CareTaskMutationException(this.code);

  final CareTaskMutationErrorCode code;

  @override
  String toString() => 'CareTaskMutationException($code)';
}

abstract interface class CareTaskMutationRepository {
  Future<void> claim({
    required String householdId,
    required String taskId,
    required String actorId,
    CareTask? taskIfMissing,
  });

  Future<String> requestDirect({
    required String householdId,
    required String taskId,
    required String actorId,
    required String recipientId,
    CareTask? taskIfMissing,
  });

  Future<String> requestOpen({
    required String householdId,
    required String taskId,
    required String actorId,
    CareTask? taskIfMissing,
  });

  Future<void> accept({
    required String householdId,
    required String taskId,
    required String actorId,
    required String requestId,
  });

  Future<void> decline({
    required String householdId,
    required String taskId,
    required String actorId,
    required String requestId,
  });

  Future<void> cancel({
    required String householdId,
    required String taskId,
    required String actorId,
    required String requestId,
  });

  Future<void> complete({
    required String householdId,
    required String taskId,
    required String actorId,
  });
}
