import '../domain/collaboration_event_models.dart';

final class StoredCollaborationEventDocument {
  const StoredCollaborationEventDocument({
    required this.id,
    required this.data,
  });

  final String id;
  final Map<String, Object?> data;
}

final class StoredCollaborationEventSnapshot {
  const StoredCollaborationEventSnapshot({
    required this.documents,
    required this.isFromCache,
    this.continuation,
  });

  final List<StoredCollaborationEventDocument> documents;
  final bool isFromCache;
  final CollaborationPageCursor? continuation;
}

final class StoredCollaborationReadCursorSnapshot {
  const StoredCollaborationReadCursorSnapshot({
    required this.data,
    required this.isFromCache,
    required this.hasPendingWrites,
  });

  final Map<String, Object?>? data;
  final bool isFromCache;
  final bool hasPendingWrites;
}

abstract interface class CollaborationEventGateway {
  Stream<StoredCollaborationEventSnapshot> observeRecent(
    String householdId, {
    required int limit,
  });

  Future<StoredCollaborationEventSnapshot> readPage(
    String householdId, {
    required int limit,
    CollaborationPageCursor? after,
  });

  Stream<StoredCollaborationReadCursorSnapshot> observeReadCursor(
    String householdId,
    String memberId,
  );

  Future<void> writeReadCursor(
    String householdId,
    String memberId,
    CollaborationReadCursor cursor,
  );
}
