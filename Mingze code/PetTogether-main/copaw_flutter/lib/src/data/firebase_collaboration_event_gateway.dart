import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/collaboration_event_models.dart';
import 'collaboration_event_gateway.dart';

final class FirebaseCollaborationEventGateway
    implements CollaborationEventGateway {
  FirebaseCollaborationEventGateway({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Query<Map<String, dynamic>> _query(String householdId) => _firestore
      .collection('households')
      .doc(householdId)
      .collection('collaborationEvents')
      .orderBy('occurredAt', descending: true)
      .orderBy(FieldPath.documentId, descending: true);

  @override
  Stream<StoredCollaborationEventSnapshot> observeRecent(
    String householdId, {
    required int limit,
  }) => _query(householdId).limit(limit).snapshots().map(_stored);

  @override
  Future<StoredCollaborationEventSnapshot> readPage(
    String householdId, {
    required int limit,
    CollaborationPageCursor? after,
  }) async {
    var query = _query(householdId);
    if (after != null) {
      if (after is! _FirebaseCollaborationPageCursor) {
        throw ArgumentError.value(after, 'after', 'Unknown page cursor');
      }
      query = query.startAfterDocument(after.document);
    }
    return _stored(await query.limit(limit).get());
  }

  @override
  Stream<StoredCollaborationReadCursorSnapshot> observeReadCursor(
    String householdId,
    String memberId,
  ) => _cursor(householdId, memberId)
      .snapshots(includeMetadataChanges: true)
      .map(
        (snapshot) => StoredCollaborationReadCursorSnapshot(
          data: snapshot.data()?.cast<String, Object?>(),
          isFromCache: snapshot.metadata.isFromCache,
          hasPendingWrites: snapshot.metadata.hasPendingWrites,
        ),
      );

  @override
  Future<void> writeReadCursor(
    String householdId,
    String memberId,
    CollaborationReadCursor cursor,
  ) => _cursor(householdId, memberId).set({
    'schemaVersion': 1,
    'occurredAt': Timestamp.fromDate(cursor.occurredAt),
    'eventID': cursor.eventId,
    'updatedAt': FieldValue.serverTimestamp(),
  });

  DocumentReference<Map<String, dynamic>> _cursor(
    String householdId,
    String memberId,
  ) => _firestore
      .collection('households')
      .doc(householdId)
      .collection('members')
      .doc(memberId)
      .collection('updateState')
      .doc('collaboration');

  static StoredCollaborationEventSnapshot _stored(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) => StoredCollaborationEventSnapshot(
    documents: snapshot.docs
        .map(
          (document) => StoredCollaborationEventDocument(
            id: document.id,
            data: document.data().cast<String, Object?>(),
          ),
        )
        .toList(growable: false),
    isFromCache: snapshot.metadata.isFromCache,
    continuation: snapshot.docs.lastOrNull == null
        ? null
        : _FirebaseCollaborationPageCursor(snapshot.docs.last),
  );
}

final class _FirebaseCollaborationPageCursor
    implements CollaborationPageCursor {
  const _FirebaseCollaborationPageCursor(this.document);

  final DocumentSnapshot<Map<String, dynamic>> document;
}
