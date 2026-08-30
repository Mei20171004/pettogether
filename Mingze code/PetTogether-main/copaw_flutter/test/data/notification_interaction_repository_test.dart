import 'dart:async';

import 'package:copaw_flutter/src/data/notification_center_gateway.dart';
import 'package:copaw_flutter/src/data/notification_center_repository.dart';
import 'package:copaw_flutter/src/data/notification_interaction_repository.dart';
import 'package:copaw_flutter/src/domain/notification_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'pending route rejects extra payload keys and persists exact click',
    () async {
      final store = MemoryNotificationPendingRouteStore();
      final repository = StoredNotificationInteractionRepository(
        gateway: _InteractionGateway(),
        store: store,
      );
      await expectLater(
        repository.persistClick({
          'schemaVersion': '1',
          'destination': 'notificationInbox',
          'householdID': 'household-1',
          'inboxItemID': 'a' * 64,
          'extra': 'blocked',
        }),
        throwsA(isA<NotificationCenterException>()),
      );
      final route = await repository.persistClick({
        'schemaVersion': '1',
        'destination': 'notificationInbox',
        'householdID': 'household-1',
        'inboxItemID': 'a' * 64,
      });
      expect(route.state, NotificationPendingRouteState.waitingForSession);
      expect((await store.read())?.generation, 1);
    },
  );

  test(
    'process relaunch normalizes persisted resolving route to retryable',
    () async {
      final store = MemoryNotificationPendingRouteStore();
      await store.write(
        NotificationPendingRoute(
          payload: NotificationRoutePayload(
            householdId: 'household-1',
            inboxItemId: 'a' * 64,
          ),
          state: NotificationPendingRouteState.resolving,
          generation: 8,
        ),
      );
      final repository = StoredNotificationInteractionRepository(
        gateway: _InteractionGateway(),
        store: store,
      );
      final route = await repository.readPendingRoute();
      expect(route?.state, NotificationPendingRouteState.retryable);
      expect(
        (await store.read())?.state,
        NotificationPendingRouteState.retryable,
      );
    },
  );

  test(
    'read A then persist B cannot let delayed normalization overwrite B',
    () async {
      final routeA = NotificationPendingRoute(
        payload: NotificationRoutePayload(
          householdId: 'household-1',
          inboxItemId: 'a' * 64,
        ),
        state: NotificationPendingRouteState.resolving,
        generation: 8,
      );
      final store = _DelayedFirstReadStore(routeA);
      final repository = StoredNotificationInteractionRepository(
        gateway: _InteractionGateway(),
        store: store,
      );

      final read = repository.readPendingRoute();
      await store.firstReadCaptured.future;
      final persisted = repository.persistClick(_payload('b'));
      await Future<void>.delayed(Duration.zero);
      store.releaseFirstRead.complete();

      await read;
      final routeB = await persisted;
      expect(store.value?.generation, routeB.generation);
      expect(store.value?.payload.inboxItemId, 'b' * 64);
      expect(
        store.value?.state,
        NotificationPendingRouteState.waitingForSession,
      );
    },
  );

  test(
    'resolver strict-decodes open response without advancing read state',
    () async {
      final repository = StoredNotificationInteractionRepository(
        gateway: _InteractionGateway(),
        store: MemoryNotificationPendingRouteStore(),
      );
      final result = await repository.resolve(
        NotificationRoutePayload(
          householdId: 'household-1',
          inboxItemId: 'a' * 64,
        ),
      );
      expect(result.disposition, NotificationRouteDisposition.open);
      expect(result.level, NotificationInboxLevel.due);
      expect(result.serverCheckedAt, DateTime.utc(2026, 8, 17, 9));
    },
  );

  for (final targetState in const [
    NotificationPendingRouteState.resolving,
    NotificationPendingRouteState.retryable,
  ]) {
    test('new B survives stale A ${targetState.name} CAS', () async {
      final store = MemoryNotificationPendingRouteStore();
      final repository = StoredNotificationInteractionRepository(
        gateway: _InteractionGateway(),
        store: store,
      );
      final routeA = await repository.persistClick(_payload('a'));
      final routeB = await repository.persistClick(_payload('b'));

      final updated = await repository.compareAndSetPendingRoute(
        expected: routeA,
        next: routeA.copyWith(state: targetState),
      );

      expect(updated, isFalse);
      expect((await store.read())?.generation, routeB.generation);
      expect((await store.read())?.payload.inboxItemId, 'b' * 64);
    });
  }

  test('new B survives stale A clear CAS', () async {
    final store = MemoryNotificationPendingRouteStore();
    final repository = StoredNotificationInteractionRepository(
      gateway: _InteractionGateway(),
      store: store,
    );
    final routeA = await repository.persistClick(_payload('a'));
    final routeB = await repository.persistClick(_payload('b'));

    expect(
      await repository.clearPendingRouteIfGeneration(routeA.generation),
      isFalse,
    );
    expect((await store.read())?.generation, routeB.generation);
  });
}

final class _DelayedFirstReadStore implements NotificationPendingRouteStore {
  _DelayedFirstReadStore(this.value);

  NotificationPendingRoute? value;
  final firstReadCaptured = Completer<void>();
  final releaseFirstRead = Completer<void>();
  var _readCount = 0;

  @override
  Future<NotificationPendingRoute?> read() async {
    _readCount += 1;
    final captured = value;
    if (_readCount == 1) {
      firstReadCaptured.complete();
      await releaseFirstRead.future;
    }
    return captured;
  }

  @override
  Future<void> write(NotificationPendingRoute route) async => value = route;

  @override
  Future<bool> compareAndSet({
    required NotificationPendingRoute expected,
    required NotificationPendingRoute next,
  }) async {
    final current = value;
    if (current?.generation != expected.generation ||
        current?.state != expected.state ||
        current?.payload.householdId != expected.payload.householdId ||
        current?.payload.inboxItemId != expected.payload.inboxItemId) {
      return false;
    }
    value = next;
    return true;
  }

  @override
  Future<void> clear() async => value = null;
}

Map<String, String> _payload(String seed) => {
  'schemaVersion': '1',
  'destination': 'notificationInbox',
  'householdID': 'household-1',
  'inboxItemID': seed * 64,
};

final class _InteractionGateway implements NotificationCenterGateway {
  @override
  Future<Map<String, Object?>> call(
    String name,
    Map<String, Object?> payload,
  ) async => {
    'disposition': 'open',
    'householdID': payload['householdID'],
    'inboxItemID': payload['inboxItemID'],
    'category': 'medication',
    'level': 'due',
    'serverCheckedAt': '2026-08-17T09:00:00.000Z',
  };

  @override
  Future<List<StoredNotificationDocument>> loadInbox({
    required String householdId,
    required DateTime memberJoinedAt,
    required int rawLimit,
    NotificationInboxPageCursor? after,
  }) async => const [];

  @override
  Future<StoredNotificationDocument?> loadInboxByIdFromServer(
    String inboxItemId,
  ) async => null;

  @override
  Stream<StoredNotificationQuery> observeDeliveryEvidence({
    required String householdId,
    required DateTime memberJoinedAt,
    required String installationHash,
  }) => const Stream.empty();

  @override
  Stream<StoredNotificationDocument?> observePreferences(String householdId) =>
      const Stream.empty();

  @override
  Stream<StoredNotificationQuery> observeInboxRecent({
    required String householdId,
    required DateTime memberJoinedAt,
    required int rawLimit,
  }) => const Stream.empty();

  @override
  Stream<StoredNotificationDocument?> observeReadCursor(String householdId) =>
      const Stream.empty();

  @override
  Future<void> writeReadCursor(
    String householdId,
    DateTime memberJoinedAt,
    NotificationReadCursor cursor,
  ) async {}
}
