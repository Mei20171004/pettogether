enum CollaborationEventAction {
  taskCreated,
  taskRequested,
  taskClaimed,
  taskAccepted,
  taskDeclined,
  taskCancelled,
  taskCompleted,
  taskReleased,
  taskReassignRequested,
  taskTakeoverRequested,
  taskReassigned,
  taskTakenOver,
  taskTransferDeclined,
  taskTransferCancelled,
  taskTransferSuperseded,
  handoffOffered,
  handoffAccepted,
  handoffDeclined,
  handoffCancelled,
  handoffClosed,
}

enum CollaborationTaskState { unclaimed, claimed, completed }

enum CollaborationEventSourceType {
  task,
  taskResponsibilityTransfer,
  handoffSession,
}

/// An eventually consistent history item. Source task state remains authoritative.
final class CollaborationEvent {
  const CollaborationEvent({
    required this.id,
    required this.sourceId,
    required this.sourceRevision,
    required this.action,
    required this.actorId,
    required this.actorNameSnapshot,
    required this.targetMemberId,
    required this.targetMemberNameSnapshot,
    required this.requestId,
    required this.assignmentMode,
    required this.petId,
    required this.petNameSnapshot,
    required this.taskTitleSnapshot,
    required this.taskCategorySnapshot,
    required this.taskPrioritySnapshot,
    required this.taskDueTime,
    required this.stateAfter,
    required this.occurredAt,
    required this.recordedAt,
    this.sourceType = CollaborationEventSourceType.task,
    this.responsibilityFromId,
    this.responsibilityFromNameSnapshot,
    this.responsibilityToId,
    this.responsibilityToNameSnapshot,
    this.handoffCreatorId,
    this.handoffCreatorNameSnapshot,
    this.handoffRecipientId,
    this.handoffRecipientNameSnapshot,
    this.handoffStatus,
  });

  final String id;
  final String sourceId;
  final int sourceRevision;
  final CollaborationEventAction action;
  final String actorId;
  final String actorNameSnapshot;
  final String? targetMemberId;
  final String? targetMemberNameSnapshot;
  final String? requestId;
  final String? assignmentMode;
  final String? petId;
  final String? petNameSnapshot;
  final String? taskTitleSnapshot;
  final String? taskCategorySnapshot;
  final String? taskPrioritySnapshot;
  final DateTime? taskDueTime;
  final CollaborationTaskState? stateAfter;
  final DateTime occurredAt;
  final DateTime recordedAt;
  final CollaborationEventSourceType sourceType;
  final String? responsibilityFromId;
  final String? responsibilityFromNameSnapshot;
  final String? responsibilityToId;
  final String? responsibilityToNameSnapshot;
  final String? handoffCreatorId;
  final String? handoffCreatorNameSnapshot;
  final String? handoffRecipientId;
  final String? handoffRecipientNameSnapshot;
  final String? handoffStatus;

  bool get isHandoff =>
      sourceType == CollaborationEventSourceType.handoffSession;
}

abstract interface class CollaborationPageCursor {
  const CollaborationPageCursor();
}

final class CollaborationReadCursor {
  const CollaborationReadCursor({
    required this.occurredAt,
    required this.eventId,
  });

  final DateTime occurredAt;
  final String eventId;
}
