import 'household_data_gateway.dart';

final class CareTaskMutationContext {
  const CareTaskMutationContext({
    required this.task,
    required this.actor,
    required this.recipient,
    required this.serverTimestamp,
  });

  final StoredDocument task;
  final StoredDocument actor;
  final StoredDocument? recipient;
  final Object serverTimestamp;
}

typedef CareTaskMutationTransform =
    Map<String, Object?> Function(CareTaskMutationContext context);

abstract interface class CareTaskMutationGateway {
  Future<MaterializedRoutineOccurrence> materializeRoutineOccurrence({
    required String householdId,
    required String routineId,
    required String localDate,
    required String action,
    String? recipientId,
  });

  Future<void> runTaskTransaction({
    required String householdId,
    required String taskId,
    required String actorId,
    String? recipientId,
    required CareTaskMutationTransform transform,
  });
}

final class MaterializedRoutineOccurrence {
  const MaterializedRoutineOccurrence({
    required this.taskId,
    required this.requestId,
  });

  final String taskId;
  final String? requestId;
}

abstract interface class MutationIdGenerator {
  String next();
}
