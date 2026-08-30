import 'package:copaw_flutter/src/data/notification_center_gateway.dart';
import 'package:copaw_flutter/src/data/notification_center_repository.dart';
import 'package:copaw_flutter/src/data/firebase_notification_center_repository.dart';
import 'package:copaw_flutter/src/data/firebase_notification_center_gateway.dart';
import 'package:copaw_flutter/src/domain/notification_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Firebase error taxonomy distinguishes permission network and backend',
    () {
      expect(
        notificationCenterErrorCodeForFirebaseCode('permission-denied'),
        NotificationCenterErrorCode.permission,
      );
      expect(
        notificationCenterErrorCodeForFirebaseCode('deadline-exceeded'),
        NotificationCenterErrorCode.network,
      );
      expect(
        notificationCenterErrorCodeForFirebaseCode('unavailable'),
        NotificationCenterErrorCode.backendUnavailable,
      );
    },
  );

  test('strict preference decode preserves four-layer authority', () async {
    final gateway = _Gateway(
      preference: StoredNotificationDocument(
        id: 'household-1',
        data: _preferenceData(),
        isFromCache: false,
        hasPendingWrites: false,
      ),
    );
    final repository = FirebaseNotificationPreferencesRepository(
      gateway: gateway,
    );
    final snapshot = await repository
        .observe(
          householdId: 'household-1',
          memberId: 'member-1',
          memberJoinedAt: DateTime.utc(2026, 8, 17),
          timeZoneIdentifier: 'Asia/Tokyo',
        )
        .first;
    expect(snapshot.authority, NotificationPreferenceAuthority.serverConfirmed);
    expect(snapshot.preferences?.summaryMinute, 1080);
    expect(snapshot.preferences?.memberJoinedAt, DateTime.utc(2026, 8, 17));
  });

  test(
    'malformed preference becomes repair state without guessed values',
    () async {
      final gateway = _Gateway(
        preference: StoredNotificationDocument(
          id: 'household-1',
          data: {..._preferenceData(), 'unknown': true},
          isFromCache: false,
          hasPendingWrites: false,
        ),
      );
      final repository = FirebaseNotificationPreferencesRepository(
        gateway: gateway,
      );
      final snapshot = await repository
          .observe(
            householdId: 'household-1',
            memberId: 'member-1',
            memberJoinedAt: DateTime.utc(2026, 8, 17),
            timeZoneIdentifier: 'Asia/Tokyo',
          )
          .first;
      expect(snapshot.authority, NotificationPreferenceAuthority.malformed);
      expect(snapshot.preferences, isNull);
    },
  );

  test('cached missing preference is not promoted to defaults', () async {
    final repository = FirebaseNotificationPreferencesRepository(
      gateway: _Gateway(
        preference: const StoredNotificationDocument(
          id: 'household-1',
          data: {},
          isFromCache: true,
          hasPendingWrites: false,
          exists: false,
        ),
      ),
    );

    final snapshot = await repository
        .observe(
          householdId: 'household-1',
          memberId: 'member-1',
          memberJoinedAt: DateTime.utc(2026, 8, 17),
          timeZoneIdentifier: 'Asia/Tokyo',
        )
        .first;

    expect(snapshot.preferences, isNull);
    expect(snapshot.authority, NotificationPreferenceAuthority.cached);
  });

  test(
    'inbox raw 21 exposes 20 and continues after twentieth raw document',
    () async {
      final documents = List.generate(
        21,
        (index) => StoredNotificationDocument(
          id: index.toString().padLeft(64, 'a'),
          data: _inboxData(index),
          isFromCache: false,
          hasPendingWrites: false,
        ),
      );
      final gateway = _Gateway(inbox: documents);
      final repository = FirebaseNotificationInboxRepository(gateway: gateway);
      final page = await repository.loadRecent(
        householdId: 'household-1',
        memberId: 'member-1',
        memberJoinedAt: DateTime.utc(2026, 8, 17),
      );
      expect(page.items, hasLength(20));
      expect(page.mayHaveMore, isTrue);
      expect(page.nextCursor, isNotNull);
      expect(gateway.lastCursorDocumentId, isNull);
    },
  );

  test(
    'malformed raw item increments dropped count without truncating cursor',
    () async {
      final documents = List.generate(
        21,
        (index) => StoredNotificationDocument(
          id: index.toString().padLeft(64, 'a'),
          data: index == 19 ? {'schemaVersion': 99} : _inboxData(index),
          isFromCache: false,
          hasPendingWrites: false,
        ),
      );
      final repository = FirebaseNotificationInboxRepository(
        gateway: _Gateway(inbox: documents),
      );
      final page = await repository.loadRecent(
        householdId: 'household-1',
        memberId: 'member-1',
        memberJoinedAt: DateTime.utc(2026, 8, 17),
      );
      expect(page.items, hasLength(19));
      expect(page.droppedItemCount, 1);
      expect(page.nextCursor, isNotNull);
    },
  );

  test(
    'direct server load pins only strict matching membership item',
    () async {
      final document = StoredNotificationDocument(
        id: 'a' * 64,
        data: _inboxData(0, id: 'a' * 64),
        isFromCache: false,
        hasPendingWrites: false,
      );
      final repository = FirebaseNotificationInboxRepository(
        gateway: _Gateway(direct: document),
      );
      final item = await repository.loadByIDFromServer(
        householdId: 'household-1',
        memberId: 'member-1',
        memberJoinedAt: DateTime.utc(2026, 8, 17),
        inboxItemId: 'a' * 64,
      );
      expect(item.id, 'a' * 64);
    },
  );

  test(
    'inbox strict union rejects mismatched source level and reason',
    () async {
      final malformed = _inboxData(0, id: 'f' * 64)
        ..['sourceType'] = 'handoffSession'
        ..['sourceID'] = 'session-1'
        ..['sourcePath'] = 'handoffSessions/session-1'
        ..['nextDispatchAt'] = null
        ..['coalescingKey'] = 'e' * 64;
      final repository = FirebaseNotificationInboxRepository(
        gateway: _Gateway(
          direct: StoredNotificationDocument(
            id: 'f' * 64,
            data: malformed,
            isFromCache: false,
            hasPendingWrites: false,
          ),
        ),
      );

      await expectLater(
        repository.loadByIDFromServer(
          householdId: 'household-1',
          memberId: 'member-1',
          memberJoinedAt: DateTime.utc(2026, 8, 17),
          inboxItemId: 'f' * 64,
        ),
        throwsA(
          isA<NotificationCenterException>().having(
            (error) => error.code,
            'code',
            NotificationCenterErrorCode.malformed,
          ),
        ),
      );
    },
  );

  test(
    'inbox exact union rejects preference dispatch and digest mismatches',
    () async {
      final invalid = <Map<String, Object?>>[
        _inboxData(0, id: 'f' * 64)
          ..['routeReason'] = 'medicationOptIn'
          ..['preferenceRevision'] = null
          ..['nextDispatchAt'] = null,
        _inboxData(0, id: 'f' * 64)..['nextDispatchAt'] = null,
        _inboxData(0, id: 'f' * 64)..['coalescingKey'] = 'e' * 64,
        _inboxData(0, id: 'f' * 64)
          ..['sourceType'] = 'notificationDigest'
          ..['sourceID'] = 'd' * 64
          ..['sourcePath'] = 'notificationDigests/${'d' * 64}'
          ..['sourceRevision'] = 2
          ..['category'] = 'summary'
          ..['level'] = 'dailySummary'
          ..['routeReason'] = 'summary'
          ..['coalescingKey'] = 'e' * 64
          ..['nextDispatchAt'] = DateTime.utc(2026, 8, 17),
      ];
      for (final data in invalid) {
        final repository = FirebaseNotificationInboxRepository(
          gateway: _Gateway(
            direct: StoredNotificationDocument(
              id: 'f' * 64,
              data: data,
              isFromCache: false,
              hasPendingWrites: false,
            ),
          ),
        );
        await expectLater(
          repository.loadByIDFromServer(
            householdId: 'household-1',
            memberId: 'member-1',
            memberJoinedAt: DateTime.utc(2026, 8, 17),
            inboxItemId: 'f' * 64,
          ),
          throwsA(isA<NotificationCenterException>()),
        );
      }
    },
  );

  test(
    'delivery evidence requires exact current installation record',
    () async {
      final repository = FirebaseNotificationDeliveryEvidenceRepository(
        gateway: _Gateway(
          delivery: StoredNotificationQuery(
            documents: [
              StoredNotificationDocument(
                id: 'd' * 64,
                data: _deliveryData(),
                isFromCache: false,
                hasPendingWrites: false,
              ),
            ],
            isFromCache: false,
            hasPendingWrites: false,
          ),
        ),
      );
      final snapshot = await repository
          .observe(
            householdId: 'household-1',
            memberId: 'member-1',
            memberJoinedAt: DateTime.utc(2026, 8, 17),
            installationHash: 'c' * 64,
          )
          .first;
      expect(snapshot.evidence, NotificationProviderEvidence.providerAccepted);
      expect(
        snapshot.authority,
        NotificationObservationAuthority.serverConfirmed,
      );
      expect(snapshot.attemptCount, 1);
    },
  );

  test('cached delivery never becomes current provider evidence', () async {
    final repository = FirebaseNotificationDeliveryEvidenceRepository(
      gateway: _Gateway(
        delivery: StoredNotificationQuery(
          documents: [
            StoredNotificationDocument(
              id: 'd' * 64,
              data: _deliveryData(),
              isFromCache: true,
              hasPendingWrites: false,
            ),
          ],
          isFromCache: true,
          hasPendingWrites: false,
        ),
      ),
    );
    final snapshot = await repository
        .observe(
          householdId: 'household-1',
          memberId: 'member-1',
          memberJoinedAt: DateTime.utc(2026, 8, 17),
          installationHash: 'c' * 64,
        )
        .first;
    expect(snapshot.evidence, NotificationProviderEvidence.providerAccepted);
    expect(snapshot.authority, NotificationObservationAuthority.cached);
  });

  test(
    'delivery strict decode rejects recipient or terminal mismatch',
    () async {
      final malformed = _deliveryData()
        ..['recipientID'] = 'other-member'
        ..['terminalAt'] = DateTime.utc(2026, 8, 17, 9, 1);
      final repository = FirebaseNotificationDeliveryEvidenceRepository(
        gateway: _Gateway(
          delivery: StoredNotificationQuery(
            documents: [
              StoredNotificationDocument(
                id: 'd' * 64,
                data: malformed,
                isFromCache: false,
                hasPendingWrites: false,
              ),
            ],
            isFromCache: false,
            hasPendingWrites: false,
          ),
        ),
      );

      await expectLater(
        repository
            .observe(
              householdId: 'household-1',
              memberId: 'member-1',
              memberJoinedAt: DateTime.utc(2026, 8, 17),
              installationHash: 'c' * 64,
            )
            .first,
        throwsA(
          isA<NotificationCenterException>().having(
            (error) => error.code,
            'code',
            NotificationCenterErrorCode.malformed,
          ),
        ),
      );
    },
  );
}

Map<String, Object?> _preferenceData() => {
  'schemaVersion': 1,
  'uid': 'member-1',
  'householdID': 'household-1',
  'memberJoinedAtSnapshot': DateTime.utc(2026, 8, 17),
  'medicationRemindersEnabled': true,
  'assignmentAlertsEnabled': true,
  'urgentAlertsEnabled': false,
  'pushEnabled': true,
  'backupForMemberIDs': <String>[],
  'quietHoursEnabled': false,
  'quietStartMinute': 1320,
  'quietEndMinute': 420,
  'summaryEnabled': false,
  'summaryMinute': 1080,
  'timeZoneIdentifierSnapshot': 'Asia/Tokyo',
  'revision': 1,
  'createdAt': DateTime.utc(2026, 8, 17),
  'updatedAt': DateTime.utc(2026, 8, 17),
};

Map<String, Object?> _inboxData(int index, {String? id}) {
  final intentId = id ?? index.toString().padLeft(64, 'a');
  final createdAt = DateTime.utc(
    2026,
    8,
    17,
    9,
  ).subtract(Duration(minutes: index));
  return {
    'schemaVersion': 1,
    'id': intentId,
    'householdID': 'household-1',
    'recipientID': 'member-1',
    'recipientJoinedAtSnapshot': DateTime.utc(2026, 8, 17),
    'category': 'medication',
    'level': 'due',
    'routeReason': 'responsible',
    'sourceType': 'medicationOccurrence',
    'sourceID': 'occurrence-$index',
    'sourcePath': 'medicationOccurrences/occurrence-$index',
    'sourceRevision': 1,
    'preferenceRevision': 1,
    'status': 'active',
    'availableAt': createdAt,
    'expiresAt': createdAt.add(const Duration(minutes: 15)),
    'nextDispatchAt': createdAt,
    'coalescingKey': null,
    'cancelReason': null,
    'cancelledAt': null,
    'createdAt': createdAt,
    'updatedAt': createdAt,
  };
}

Map<String, Object?> _deliveryData() => {
  'schemaVersion': 2,
  'id': 'd' * 64,
  'intentID': 'a' * 64,
  'householdID': 'household-1',
  'recipientID': 'member-1',
  'recipientJoinedAtSnapshot': DateTime.utc(2026, 8, 17),
  'installationHash': 'c' * 64,
  'status': 'providerAccepted',
  'attemptCount': 1,
  'nextAttemptAt': null,
  'leaseID': null,
  'leaseExpiresAt': null,
  'providerRequestStartedAt': null,
  'providerAcceptedAt': DateTime.utc(2026, 8, 17, 9),
  'providerUnknownAt': null,
  'terminalAt': DateTime.utc(2026, 8, 17, 9),
  'safeErrorCode': null,
  'createdAt': DateTime.utc(2026, 8, 17, 8, 59),
  'updatedAt': DateTime.utc(2026, 8, 17, 9),
};

final class _Gateway implements NotificationCenterGateway {
  _Gateway({
    this.preference,
    this.inbox = const [],
    this.direct,
    this.delivery = const StoredNotificationQuery(
      documents: [],
      isFromCache: false,
      hasPendingWrites: false,
    ),
  });

  final StoredNotificationDocument? preference;
  final List<StoredNotificationDocument> inbox;
  final StoredNotificationDocument? direct;
  final StoredNotificationQuery delivery;
  String? lastCursorDocumentId;

  @override
  Stream<StoredNotificationDocument?> observePreferences(String householdId) =>
      Stream.value(preference);

  @override
  Stream<StoredNotificationQuery> observeInboxRecent({
    required String householdId,
    required DateTime memberJoinedAt,
    required int rawLimit,
  }) => Stream.value(
    StoredNotificationQuery(
      documents: inbox.take(rawLimit).toList(growable: false),
      isFromCache: inbox.any((document) => document.isFromCache),
      hasPendingWrites: inbox.any((document) => document.hasPendingWrites),
    ),
  );

  @override
  Future<List<StoredNotificationDocument>> loadInbox({
    required String householdId,
    required DateTime memberJoinedAt,
    required int rawLimit,
    NotificationInboxPageCursor? after,
  }) async {
    if (after case final StoredNotificationPageCursor cursor) {
      lastCursorDocumentId = cursor.documentId;
    }
    return inbox.take(rawLimit).toList(growable: false);
  }

  @override
  Future<StoredNotificationDocument?> loadInboxByIdFromServer(
    String inboxItemId,
  ) async => direct;

  @override
  Stream<StoredNotificationDocument?> observeReadCursor(String householdId) =>
      const Stream.empty();

  @override
  Stream<StoredNotificationQuery> observeDeliveryEvidence({
    required String householdId,
    required DateTime memberJoinedAt,
    required String installationHash,
  }) => Stream.value(delivery);

  @override
  Future<Map<String, Object?>> call(
    String name,
    Map<String, Object?> payload,
  ) async => const {};

  @override
  Future<void> writeReadCursor(
    String householdId,
    DateTime memberJoinedAt,
    NotificationReadCursor cursor,
  ) async {}
}
