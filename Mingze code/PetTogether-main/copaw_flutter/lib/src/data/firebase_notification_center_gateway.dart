import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/notification_models.dart';
import 'notification_center_gateway.dart';
import 'notification_center_repository.dart';

final class FirebaseNotificationCenterGateway
    implements NotificationCenterGateway {
  FirebaseNotificationCenterGateway({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ??
           FirebaseFunctions.instanceFor(region: 'asia-northeast1');

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) throw StateError('Authentication required');
    return uid;
  }

  @override
  Stream<StoredNotificationDocument?> observePreferences(String householdId) =>
      _userCollection(
        'householdNotificationPreferences',
      ).doc(householdId).snapshots(includeMetadataChanges: true).map(_stored);

  Query<Map<String, dynamic>> _inboxQuery(
    String householdId,
    DateTime memberJoinedAt,
  ) => _userCollection('notificationInbox')
      .where('householdID', isEqualTo: householdId)
      .where(
        'recipientJoinedAtSnapshot',
        isEqualTo: Timestamp.fromDate(memberJoinedAt),
      )
      .orderBy('createdAt', descending: true)
      .orderBy(FieldPath.documentId, descending: true);

  @override
  Stream<StoredNotificationQuery> observeInboxRecent({
    required String householdId,
    required DateTime memberJoinedAt,
    required int rawLimit,
  }) => _inboxQuery(householdId, memberJoinedAt)
      .limit(rawLimit)
      .snapshots(includeMetadataChanges: true)
      .map(
        (snapshot) => StoredNotificationQuery(
          documents: snapshot.docs
              .map(
                (document) => _stored(
                  document,
                  cursor: _FirebaseNotificationPageCursor(document),
                ),
              )
              .toList(growable: false),
          isFromCache: snapshot.metadata.isFromCache,
          hasPendingWrites: snapshot.metadata.hasPendingWrites,
        ),
      );

  @override
  Future<List<StoredNotificationDocument>> loadInbox({
    required String householdId,
    required DateTime memberJoinedAt,
    required int rawLimit,
    NotificationInboxPageCursor? after,
  }) async {
    var query = _inboxQuery(householdId, memberJoinedAt);
    if (after != null) {
      if (after is! _FirebaseNotificationPageCursor) {
        throw ArgumentError.value(after, 'after', 'Unknown page cursor');
      }
      query = query.startAfterDocument(after.document);
    }
    try {
      final snapshot = await query.limit(rawLimit).get();
      return snapshot.docs
          .map(
            (document) => _stored(
              document,
              cursor: _FirebaseNotificationPageCursor(document),
            ),
          )
          .toList(growable: false);
    } on Object catch (error) {
      throw _notificationCenterException(error);
    }
  }

  @override
  Future<StoredNotificationDocument?> loadInboxByIdFromServer(
    String inboxItemId,
  ) async {
    try {
      final snapshot = await _userCollection(
        'notificationInbox',
      ).doc(inboxItemId).get(const GetOptions(source: Source.server));
      return snapshot.exists ? _stored(snapshot) : null;
    } on Object catch (error) {
      throw _notificationCenterException(error);
    }
  }

  @override
  Stream<StoredNotificationDocument?> observeReadCursor(String householdId) =>
      _userCollection(
        'notificationInboxState',
      ).doc(householdId).snapshots(includeMetadataChanges: true).map(_stored);

  @override
  Future<void> writeReadCursor(
    String householdId,
    DateTime memberJoinedAt,
    NotificationReadCursor cursor,
  ) async {
    try {
      await _userCollection('notificationInboxState').doc(householdId).set({
        'schemaVersion': 1,
        'householdID': householdId,
        'recipientJoinedAtSnapshot': Timestamp.fromDate(memberJoinedAt),
        'createdAt': Timestamp.fromDate(cursor.createdAt),
        'intentID': cursor.intentId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on Object catch (error) {
      throw _notificationCenterException(error);
    }
  }

  @override
  Stream<StoredNotificationQuery> observeDeliveryEvidence({
    required String householdId,
    required DateTime memberJoinedAt,
    required String installationHash,
  }) => _userCollection('notificationDeliveries')
      .where('householdID', isEqualTo: householdId)
      .where(
        'recipientJoinedAtSnapshot',
        isEqualTo: Timestamp.fromDate(memberJoinedAt),
      )
      .where('installationHash', isEqualTo: installationHash)
      .orderBy('updatedAt', descending: true)
      .orderBy(FieldPath.documentId, descending: true)
      .limit(1)
      .snapshots(includeMetadataChanges: true)
      .map(
        (snapshot) => StoredNotificationQuery(
          documents: snapshot.docs.map(_stored).toList(growable: false),
          isFromCache: snapshot.metadata.isFromCache,
          hasPendingWrites: snapshot.metadata.hasPendingWrites,
        ),
      );

  @override
  Future<Map<String, Object?>> call(
    String name,
    Map<String, Object?> payload,
  ) async {
    try {
      final result = await _functions
          .httpsCallable(name)
          .call<Object?>(payload);
      final data = result.data;
      if (data is! Map) {
        throw const NotificationCenterException(
          NotificationCenterErrorCode.malformed,
        );
      }
      return data.cast<String, Object?>();
    } on NotificationCenterException {
      rethrow;
    } on Object catch (error) {
      throw _notificationCenterException(error);
    }
  }

  CollectionReference<Map<String, dynamic>> _userCollection(String name) =>
      _firestore.collection('users').doc(_uid).collection(name);

  static StoredNotificationDocument _stored(
    DocumentSnapshot<Map<String, dynamic>> snapshot, {
    NotificationInboxPageCursor? cursor,
  }) => StoredNotificationDocument(
    id: snapshot.id,
    data: (snapshot.data() ?? const <String, dynamic>{})
        .cast<String, Object?>(),
    isFromCache: snapshot.metadata.isFromCache,
    hasPendingWrites: snapshot.metadata.hasPendingWrites,
    exists: snapshot.exists,
    cursor: cursor,
  );
}

NotificationCenterErrorCode notificationCenterErrorCodeForFirebaseCode(
  String code,
) => switch (code) {
  'permission-denied' ||
  'unauthenticated' => NotificationCenterErrorCode.permission,
  'invalid-argument' => NotificationCenterErrorCode.invalidInput,
  'aborted' || 'failed-precondition' => NotificationCenterErrorCode.stale,
  'deadline-exceeded' ||
  'network-request-failed' ||
  'cancelled' => NotificationCenterErrorCode.network,
  'data-loss' => NotificationCenterErrorCode.malformed,
  'unavailable' ||
  'internal' ||
  'resource-exhausted' => NotificationCenterErrorCode.backendUnavailable,
  _ => NotificationCenterErrorCode.backendUnavailable,
};

NotificationCenterException _notificationCenterException(Object error) {
  if (error is NotificationCenterException) return error;
  if (error is FirebaseException) {
    return NotificationCenterException(
      notificationCenterErrorCodeForFirebaseCode(error.code),
      diagnosticCode: error.code,
    );
  }
  if (error is StateError) {
    return const NotificationCenterException(
      NotificationCenterErrorCode.permission,
      diagnosticCode: 'unauthenticated',
    );
  }
  return const NotificationCenterException(
    NotificationCenterErrorCode.backendUnavailable,
  );
}

final class _FirebaseNotificationPageCursor
    implements NotificationInboxPageCursor {
  const _FirebaseNotificationPageCursor(this.document);

  final DocumentSnapshot<Map<String, dynamic>> document;
}
