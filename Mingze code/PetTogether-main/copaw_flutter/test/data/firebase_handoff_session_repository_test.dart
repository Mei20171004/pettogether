import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:copaw_flutter/src/data/firebase_handoff_session_repository.dart';
import 'package:copaw_flutter/src/data/handoff_session_gateway.dart';
import 'package:copaw_flutter/src/data/handoff_session_repository.dart';
import 'package:copaw_flutter/src/domain/handoff_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakeGateway gateway;
  late FirebaseHandoffSessionRepository repository;

  setUp(() {
    gateway = _FakeGateway();
    repository = FirebaseHandoffSessionRepository(gateway: gateway);
  });

  tearDown(() => repository.stopObserving());

  test('decodes only a pointer-matched active offered session', () async {
    gateway.authority = _authority();

    final snapshot = await repository.observeActiveSession('home-a').first;

    expect(snapshot.authorityMalformed, isFalse);
    expect(snapshot.droppedSessionCount, 0);
    expect(snapshot.activeSession?.status, HandoffSessionStatus.offered);
    expect(snapshot.activeSession?.recipientNameSnapshot, 'Blair');
    expect(snapshot.activeSession?.handoffRevisionSnapshot, 3);
    expect(snapshot.pinnedVersion?.id, 'v000003');
    expect(snapshot.pinnedVersion?.careInstructions, 'Pinned dinner at 18:00');
  });

  test(
    'missing or mismatched pointer never guesses active authority',
    () async {
      gateway.authority = StoredHandoffSessionAuthority(
        pointerExists: false,
        pointerData: const {},
        sessions: [
          StoredHandoffSessionDocument(id: 'session-a', data: _session()),
        ],
        versions: [
          StoredHandoffVersionDocument(id: 'v000003', data: _version()),
        ],
        isFromCache: false,
      );

      final snapshot = await repository.observeActiveSession('home-a').first;

      expect(snapshot.activeSession, isNull);
      expect(snapshot.authorityMalformed, isTrue);
    },
  );

  test(
    'missing pinned version keeps session metadata but blocks authority',
    () async {
      gateway.authority = StoredHandoffSessionAuthority(
        pointerExists: true,
        pointerData: _authority().pointerData,
        sessions: [
          StoredHandoffSessionDocument(id: 'session-a', data: _session()),
        ],
        versions: const [],
        isFromCache: false,
      );

      final snapshot = await repository.observeActiveSession('home-a').first;

      expect(snapshot.activeSession?.id, 'session-a');
      expect(snapshot.pinnedVersion, isNull);
      expect(snapshot.authorityMalformed, isTrue);
    },
  );

  test('version source revision mismatch blocks terminal authority', () async {
    gateway.authority = StoredHandoffSessionAuthority(
      pointerExists: true,
      pointerData: _authority().pointerData,
      sessions: [
        StoredHandoffSessionDocument(id: 'session-a', data: _session()),
      ],
      versions: [
        StoredHandoffVersionDocument(
          id: 'v000003',
          data: _version(overrides: {'sourceHandoffRevision': 2}),
        ),
      ],
      isFromCache: false,
    );

    final snapshot = await repository.observeActiveSession('home-a').first;

    expect(snapshot.pinnedVersion, isNull);
    expect(snapshot.droppedVersionCount, 1);
    expect(snapshot.authorityMalformed, isTrue);
  });

  test(
    'cached authority retains pinned content but is not authoritative',
    () async {
      final current = _authority();
      gateway.authority = StoredHandoffSessionAuthority(
        pointerExists: current.pointerExists,
        pointerData: current.pointerData,
        sessions: current.sessions,
        versions: current.versions,
        isFromCache: true,
      );

      final snapshot = await repository.observeActiveSession('home-a').first;

      expect(snapshot.activeSession?.id, 'session-a');
      expect(snapshot.pinnedVersion?.id, 'v000003');
      expect(snapshot.isFromCache, isTrue);
    },
  );

  test('terminal actor mismatch is dropped instead of trusted', () async {
    gateway.authority = StoredHandoffSessionAuthority(
      pointerExists: false,
      pointerData: const {},
      sessions: [
        StoredHandoffSessionDocument(
          id: 'session-a',
          data: _session(
            overrides: {
              'status': 'declined',
              'declinedByID': 'user-a',
              'declinedByName': 'Alex',
              'declinedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 18)),
              'revision': 2,
            },
          ),
        ),
      ],
      versions: [StoredHandoffVersionDocument(id: 'v000003', data: _version())],
      isFromCache: false,
    );

    final snapshot = await repository.observeActiveSession('home-a').first;

    expect(snapshot.activeSession, isNull);
    expect(snapshot.droppedSessionCount, 1);
  });

  test('authority listener errors remain classified', () async {
    gateway.observeError = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );

    await expectLater(
      repository.observeActiveSession('home-a').first,
      _throws(HandoffSessionErrorCode.permission),
    );
  });

  test('offer uses exact UTC millisecond payload and response', () async {
    gateway.response = _response();
    final start = DateTime.parse('2026-08-20T09:00:00+09:00');
    final end = DateTime.parse('2026-08-21T09:00:00+09:00');

    final result = await repository.offer(
      householdId: 'home-a',
      recipientId: 'user-b',
      expectedHandoffRevision: 3,
      plannedStart: start,
      plannedEnd: end,
      clientMutationId: 'offer-a',
    );

    expect(gateway.payload, {
      'householdID': 'home-a',
      'action': 'offer',
      'recipientID': 'user-b',
      'expectedHandoffRevision': 3,
      'plannedStartMilliseconds': start.toUtc().millisecondsSinceEpoch,
      'plannedEndMilliseconds': end.toUtc().millisecondsSinceEpoch,
      'clientMutationID': 'offer-a',
    });
    expect(result.sessionStatus, HandoffSessionStatus.offered);
    expect(result.activeSessionId, 'session-a');
  });

  test('stale transition and offline remain distinguishable', () async {
    gateway.error = FirebaseFunctionsException(
      code: 'aborted',
      message: 'stale',
    );
    await expectLater(
      repository.transition(
        householdId: 'home-a',
        action: 'accept',
        sessionId: 'session-a',
        expectedSessionRevision: 1,
        clientMutationId: 'accept-a',
      ),
      _throws(HandoffSessionErrorCode.stale),
    );

    gateway.error = FirebaseFunctionsException(
      code: 'unavailable',
      message: 'offline',
    );
    await expectLater(
      repository.transition(
        householdId: 'home-a',
        action: 'accept',
        sessionId: 'session-a',
        expectedSessionRevision: 1,
        clientMutationId: 'accept-a',
      ),
      _throws(HandoffSessionErrorCode.network),
    );
  });

  test(
    'deterministic fake is action-aware without optimistic snapshot mutation',
    () async {
      final fake = FakeHandoffSessionRepository();
      final before = await fake.observeActiveSession('home-a').first;
      final offered = await fake.offer(
        householdId: 'home-a',
        recipientId: 'user-b',
        expectedHandoffRevision: 3,
        plannedStart: DateTime.utc(2026, 8, 20),
        plannedEnd: DateTime.utc(2026, 8, 21),
        clientMutationId: 'offer-a',
      );
      final declined = await fake.transition(
        householdId: 'home-a',
        action: 'decline',
        sessionId: 'session-a',
        expectedSessionRevision: 1,
        clientMutationId: 'decline-a',
      );
      final after = await fake.observeActiveSession('home-a').first;

      expect(offered.sessionRevision, 1);
      expect(offered.sessionStatus, HandoffSessionStatus.offered);
      expect(offered.activeSessionId, 'fake-session');
      expect(offered.versionId, 'v000003');
      expect(declined.sessionRevision, 2);
      expect(declined.sessionStatus, HandoffSessionStatus.declined);
      expect(declined.activeSessionId, isNull);
      expect(after.activeSession, same(before.activeSession));
    },
  );
}

Matcher _throws(HandoffSessionErrorCode code) => throwsA(
  isA<HandoffSessionException>().having((error) => error.code, 'code', code),
);

StoredHandoffSessionAuthority _authority() => StoredHandoffSessionAuthority(
  pointerExists: true,
  pointerData: {
    'schemaVersion': 1,
    'sessionID': 'session-a',
    'sessionStatus': 'offered',
    'plannedEndAt': Timestamp.fromDate(DateTime.utc(2026, 8, 21)),
    'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 17)),
  },
  sessions: [StoredHandoffSessionDocument(id: 'session-a', data: _session())],
  versions: [StoredHandoffVersionDocument(id: 'v000003', data: _version())],
  isFromCache: false,
);

Map<String, Object?> _session({Map<String, Object?> overrides = const {}}) => {
  'schemaVersion': 1,
  'id': 'session-a',
  'versionID': 'v000003',
  'handoffRevisionSnapshot': 3,
  'creatorID': 'user-a',
  'creatorName': 'Alex',
  'recipientID': 'user-b',
  'recipientName': 'Blair',
  'timeZoneIdentifierSnapshot': 'Asia/Tokyo',
  'plannedStartAt': Timestamp.fromDate(DateTime.utc(2026, 8, 20)),
  'plannedEndAt': Timestamp.fromDate(DateTime.utc(2026, 8, 21)),
  'status': 'offered',
  'offeredAt': Timestamp.fromDate(DateTime.utc(2026, 8, 17)),
  'acceptedByID': null,
  'acceptedByName': null,
  'acceptedAt': null,
  'declinedByID': null,
  'declinedByName': null,
  'declinedAt': null,
  'cancelledByID': null,
  'cancelledByName': null,
  'cancelledAt': null,
  'closedByID': null,
  'closedByName': null,
  'closedAt': null,
  'resolutionReason': null,
  'revision': 1,
  ...overrides,
};

Map<String, Object?> _version({Map<String, Object?> overrides = const {}}) => {
  'schemaVersion': 1,
  'id': 'v000003',
  'sourceHandoffRevision': 3,
  'careInstructions': 'Pinned dinner at 18:00',
  'emergencyContactName': 'Taylor',
  'emergencyContactPhone': '090-0000-0000',
  'veterinaryHospitalName': 'Central Animal Hospital',
  'veterinaryHospitalPhone': '03-0000-0000',
  'updatedByID': 'user-a',
  'updatedByName': 'Alex',
  'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 16)),
  'materializedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 17)),
  ...overrides,
};

Map<String, Object?> _response() => {
  'sessionID': 'session-a',
  'sessionRevision': 1,
  'sessionStatus': 'offered',
  'activeSessionID': 'session-a',
  'versionID': 'v000003',
  'existing': false,
};

final class _FakeGateway implements HandoffSessionGateway {
  StoredHandoffSessionAuthority authority = _authority();
  Map<String, Object?> response = _response();
  Object? error;
  Object? observeError;
  Map<String, Object?>? payload;

  @override
  Stream<StoredHandoffSessionAuthority> observeAuthority(String householdId) {
    if (observeError case final error?) return Stream.error(error);
    return Stream.value(authority);
  }

  @override
  Future<Map<String, Object?>> mutate(Map<String, Object?> payload) async {
    this.payload = payload;
    if (error case final caught?) {
      error = null;
      throw caught;
    }
    return response;
  }
}
