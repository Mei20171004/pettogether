import '../domain/notification_models.dart';

abstract interface class NotificationInboxPageCursor {}

final class StoredNotificationPageCursor
    implements NotificationInboxPageCursor {
  const StoredNotificationPageCursor(this.documentId);

  final String documentId;
}

final class StoredNotificationDocument {
  const StoredNotificationDocument({
    required this.id,
    required this.data,
    required this.isFromCache,
    required this.hasPendingWrites,
    this.exists = true,
    this.cursor,
  });

  final String id;
  final Map<String, Object?> data;
  final bool isFromCache;
  final bool hasPendingWrites;
  final bool exists;
  final NotificationInboxPageCursor? cursor;
}

final class StoredNotificationQuery {
  const StoredNotificationQuery({
    required this.documents,
    required this.isFromCache,
    required this.hasPendingWrites,
  });

  final List<StoredNotificationDocument> documents;
  final bool isFromCache;
  final bool hasPendingWrites;
}

abstract interface class NotificationCenterGateway {
  Stream<StoredNotificationDocument?> observePreferences(String householdId);

  Stream<StoredNotificationQuery> observeInboxRecent({
    required String householdId,
    required DateTime memberJoinedAt,
    required int rawLimit,
  });

  Future<List<StoredNotificationDocument>> loadInbox({
    required String householdId,
    required DateTime memberJoinedAt,
    required int rawLimit,
    NotificationInboxPageCursor? after,
  });

  Future<StoredNotificationDocument?> loadInboxByIdFromServer(
    String inboxItemId,
  );

  Stream<StoredNotificationDocument?> observeReadCursor(String householdId);

  Future<void> writeReadCursor(
    String householdId,
    DateTime memberJoinedAt,
    NotificationReadCursor cursor,
  );

  Stream<StoredNotificationQuery> observeDeliveryEvidence({
    required String householdId,
    required DateTime memberJoinedAt,
    required String installationHash,
  });

  Future<Map<String, Object?>> call(String name, Map<String, Object?> payload);
}
