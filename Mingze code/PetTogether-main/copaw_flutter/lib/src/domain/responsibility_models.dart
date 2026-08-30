enum ResponsibilityTransferKind { reassign, takeover }

enum ResponsibilityTransferStatus {
  pending,
  accepted,
  declined,
  cancelled,
  superseded,
}

final class ResponsibilityTransfer {
  const ResponsibilityTransfer({
    required this.id,
    required this.taskId,
    required this.kind,
    required this.status,
    required this.requestedById,
    required this.requestedByNameSnapshot,
    required this.consentById,
    required this.consentByNameSnapshot,
    required this.responsibilityFromId,
    required this.responsibilityFromNameSnapshot,
    required this.responsibilityToId,
    required this.responsibilityToNameSnapshot,
    required this.taskRevisionAtProposal,
    required this.createdAt,
    required this.resolvedById,
    required this.resolvedByNameSnapshot,
    required this.resolvedAt,
    required this.resultingTaskRevision,
    required this.revision,
  });

  final String id;
  final String taskId;
  final ResponsibilityTransferKind kind;
  final ResponsibilityTransferStatus status;
  final String requestedById;
  final String requestedByNameSnapshot;
  final String consentById;
  final String consentByNameSnapshot;
  final String responsibilityFromId;
  final String responsibilityFromNameSnapshot;
  final String responsibilityToId;
  final String responsibilityToNameSnapshot;
  final int taskRevisionAtProposal;
  final DateTime createdAt;
  final String? resolvedById;
  final String? resolvedByNameSnapshot;
  final DateTime? resolvedAt;
  final int? resultingTaskRevision;
  final int revision;
}

enum TaskResponsibilityStatus { unclaimed, claimed, completed }

final class TaskResponsibilityMutationResult {
  const TaskResponsibilityMutationResult({
    required this.taskId,
    required this.taskRevision,
    required this.taskStatus,
    required this.assigneeId,
    required this.transferId,
    required this.transferRevision,
    required this.transferStatus,
    required this.existing,
  });

  final String taskId;
  final int taskRevision;
  final TaskResponsibilityStatus taskStatus;
  final String? assigneeId;
  final String? transferId;
  final int? transferRevision;
  final ResponsibilityTransferStatus? transferStatus;
  final bool existing;
}
