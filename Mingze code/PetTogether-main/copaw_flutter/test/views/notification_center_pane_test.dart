import 'dart:async';

import 'package:copaw_flutter/src/data/notification_center_gateway.dart';
import 'package:copaw_flutter/src/data/notification_center_repository.dart';
import 'package:copaw_flutter/src/data/notification_repository.dart';
import 'package:copaw_flutter/src/domain/models.dart';
import 'package:copaw_flutter/src/domain/notification_models.dart';
import 'package:copaw_flutter/src/localization/app_locale.dart';
import 'package:copaw_flutter/src/views/notification_center_pane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reminder cursor advances only after Reminders is visible', (
    tester,
  ) async {
    final inbox = FakeNotificationInboxRepository(items: [_item]);
    var unread = false;
    await tester.pumpWidget(
      _app(
        inbox: inbox,
        interaction: FakeNotificationInteractionRepository(),
        onUnreadChanged: (value) => unread = value,
      ),
    );
    await tester.pumpAndSettle();

    expect(unread, isTrue);
    expect(inbox.markReadCalls, 0);

    await tester.tap(find.byKey(const Key('notificationUpdates.reminders')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(Key('notificationInbox.item.${_item.id}')),
      findsOneWidget,
    );
    expect(inbox.markReadCalls, 1);
    expect(inbox.cursor?.intentId, _item.id);
  });

  testWidgets('pending click resolves, direct-loads and pins before clear', (
    tester,
  ) async {
    final inbox = FakeNotificationInboxRepository(items: [_item]);
    final interaction = FakeNotificationInteractionRepository()
      ..pendingRoute = NotificationPendingRoute(
        payload: NotificationRoutePayload(
          householdId: _item.householdId,
          inboxItemId: _item.id,
        ),
        state: NotificationPendingRouteState.resolving,
        generation: 3,
      );
    var opens = 0;
    await tester.pumpWidget(
      _app(
        inbox: inbox,
        interaction: interaction,
        onRouteOpened: () => opens += 1,
      ),
    );
    await tester.pumpAndSettle();

    expect(opens, 1);
    expect(inbox.directLoadCalls, 1);
    expect(
      find.byKey(Key('notificationInbox.item.${_item.id}')),
      findsOneWidget,
    );
    expect(interaction.pendingRoute, isNull);
  });

  testWidgets('realtime refresh preserves an advanced pagination cursor', (
    tester,
  ) async {
    final inbox = _PagedInboxRepository();
    await tester.pumpWidget(
      _app(inbox: inbox, interaction: FakeNotificationInteractionRepository()),
    );
    inbox.emitRecent(_page([_item], const _Cursor('recent-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notificationUpdates.reminders')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('notificationInbox.loadMore')));
    await tester.pumpAndSettle();
    expect(inbox.afterLabels, ['recent-1']);

    inbox.emitRecent(
      _page([_item.copyWith(id: 'b' * 64)], const _Cursor('recent-2')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notificationInbox.loadMore')));
    await tester.pumpAndSettle();

    expect(inbox.afterLabels, ['recent-1', 'older-2']);
  });

  testWidgets('new click survives an older route clear', (tester) async {
    final inbox = FakeNotificationInboxRepository(items: [_item]);
    final interaction = FakeNotificationInteractionRepository()
      ..pendingRoute = NotificationPendingRoute(
        payload: NotificationRoutePayload(
          householdId: _item.householdId,
          inboxItemId: _item.id,
        ),
        state: NotificationPendingRouteState.retryable,
        generation: 3,
      );
    interaction.beforeConditionalClear = () => interaction.persistClick({
      'schemaVersion': '1',
      'destination': 'notificationInbox',
      'householdID': 'household-1',
      'inboxItemID': 'b' * 64,
    });

    await tester.pumpWidget(_app(inbox: inbox, interaction: interaction));
    await tester.pumpAndSettle();

    expect(interaction.pendingRoute?.generation, 4);
    expect(interaction.pendingRoute?.payload.inboxItemId, 'b' * 64);
  });

  testWidgets('wrong household route returns to Today after generic copy', (
    tester,
  ) async {
    final interaction = FakeNotificationInteractionRepository()
      ..pendingRoute = NotificationPendingRoute(
        payload: NotificationRoutePayload(
          householdId: 'another-household',
          inboxItemId: _item.id,
        ),
        state: NotificationPendingRouteState.retryable,
        generation: 2,
      );
    var rejected = 0;
    await tester.pumpWidget(
      _app(
        inbox: FakeNotificationInboxRepository(items: [_item]),
        interaction: interaction,
        onRouteRejected: () => rejected += 1,
      ),
    );
    await tester.pumpAndSettle();

    expect(rejected, 1);
    expect(interaction.pendingRoute, isNull);
  });

  testWidgets('mark read failure is visible and retryable by taxonomy', (
    tester,
  ) async {
    final inbox = FakeNotificationInboxRepository(items: [_item])
      ..nextMarkReadError = const NotificationCenterException(
        NotificationCenterErrorCode.permission,
      );
    await tester.pumpWidget(
      _app(inbox: inbox, interaction: FakeNotificationInteractionRepository()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notificationUpdates.reminders')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        const AppStrings(AppLocale.english).notificationPermissionError,
      ),
      findsOneWidget,
    );
    expect(inbox.markReadCalls, 1);

    await tester.tap(find.byKey(const Key('notificationInbox.retry')));
    await tester.pumpAndSettle();
    expect(inbox.markReadCalls, 2);
    expect(
      inbox.attemptedReadCursors[1].createdAt,
      inbox.attemptedReadCursors[0].createdAt,
    );
    expect(
      inbox.attemptedReadCursors[1].intentId,
      inbox.attemptedReadCursors[0].intentId,
    );
  });

  testWidgets('read candidate rejects dropped cached and pending pages', (
    tester,
  ) async {
    final unsafePages = [
      _page([_item], null).copyWith(droppedItemCount: 1),
      _page([
        _item,
      ], null).copyWith(authority: NotificationObservationAuthority.cached),
      _page([_item], null).copyWith(hasPendingWrites: true),
    ];
    for (final page in unsafePages) {
      final inbox = _SinglePageInboxRepository(page);
      await tester.pumpWidget(
        _app(
          inbox: inbox,
          interaction: FakeNotificationInteractionRepository(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notificationUpdates.reminders')));
      await tester.pumpAndSettle();
      expect(inbox.markReadCalls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('load more re-evaluates and marks newly visible safe candidate', (
    tester,
  ) async {
    final inbox = _LoadMoreMarkRepository();
    await tester.pumpWidget(
      _app(inbox: inbox, interaction: FakeNotificationInteractionRepository()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notificationUpdates.reminders')));
    await tester.pumpAndSettle();
    expect(inbox.markReadCalls, 0);

    await tester.tap(find.byKey(const Key('notificationInbox.loadMore')));
    await tester.pumpAndSettle();
    expect(inbox.markReadCalls, 1);
    expect(inbox.marked?.intentId, _item.id);
  });

  testWidgets(
    'load more retry keeps failed cursor after realtime continuation changes',
    (tester) async {
      final inbox = _ExactLoadMoreRetryRepository();
      await tester.pumpWidget(
        _app(
          inbox: inbox,
          interaction: FakeNotificationInteractionRepository(),
        ),
      );
      inbox.emitRecent(
        _page([
          _item.copyWith(status: NotificationInboxStatus.cancelled),
        ], const _Cursor('a')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notificationUpdates.reminders')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('notificationInbox.loadMore')));
      await tester.pumpAndSettle();
      expect(inbox.afterLabels, ['a']);
      expect(find.byKey(const Key('notificationInbox.retry')), findsOneWidget);

      inbox.emitRecent(
        _page([
          _item.copyWith(status: NotificationInboxStatus.cancelled),
        ], const _Cursor('b')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notificationInbox.retry')));
      await tester.pumpAndSettle();

      expect(inbox.afterLabels, ['a', 'a']);
      expect(find.byKey(const Key('notificationInbox.retry')), findsNothing);
      expect(inbox.markReadCalls, 1);
      expect(inbox.marked?.intentId, _item.id);
    },
  );

  testWidgets('cursor convergence triggers a safe visible mark', (
    tester,
  ) async {
    final inbox = _CursorConvergenceInboxRepository();
    await tester.pumpWidget(
      _app(inbox: inbox, interaction: FakeNotificationInteractionRepository()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notificationUpdates.reminders')));
    await tester.pump();
    expect(inbox.markReadCalls, 0);

    inbox.confirmCursor();
    await tester.pumpAndSettle();
    expect(inbox.markReadCalls, 1);
  });

  testWidgets('server recent never upgrades a cached older item authority', (
    tester,
  ) async {
    final inbox = _MixedAuthorityInboxRepository();
    await tester.pumpWidget(
      _app(inbox: inbox, interaction: FakeNotificationInteractionRepository()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notificationUpdates.reminders')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notificationInbox.loadMore')));
    await tester.pumpAndSettle();
    inbox.emitServerRecent();
    await tester.pumpAndSettle();

    expect(
      find.text(
        const AppStrings(AppLocale.english).notificationInboxCachedItem,
      ),
      findsOneWidget,
    );
    expect(inbox.markReadCalls, 0);
  });

  testWidgets('preference observation error hides stale controls until retry', (
    tester,
  ) async {
    final preferences = FakeNotificationPreferencesRepository(
      NotificationPreferencesSnapshot(
        preferences: HouseholdNotificationPreferences.conservative(
          uid: 'user-1',
          householdId: 'household-1',
          memberJoinedAt: _joinedAt,
          timeZoneIdentifier: 'Asia/Tokyo',
        ),
        authority: NotificationPreferenceAuthority.serverConfirmed,
      ),
    );
    await tester.pumpWidget(
      _app(
        inbox: FakeNotificationInboxRepository(items: [_item]),
        interaction: FakeNotificationInteractionRepository(),
        mode: NotificationCenterPaneMode.profile,
        preferences: preferences,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SwitchListTile), findsWidgets);

    preferences.emitError(
      const NotificationCenterException(NotificationCenterErrorCode.network),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SwitchListTile), findsNothing);
    expect(
      find.byKey(const Key('notifications.preferences.retry')),
      findsOneWidget,
    );
  });

  testWidgets(
    'preference save failure keeps draft and exact mutation id for retry',
    (tester) async {
      final preferences =
          FakeNotificationPreferencesRepository(
              NotificationPreferencesSnapshot(
                preferences: HouseholdNotificationPreferences.conservative(
                  uid: 'user-1',
                  householdId: 'household-1',
                  memberJoinedAt: _joinedAt,
                  timeZoneIdentifier: 'Asia/Tokyo',
                ),
                authority: NotificationPreferenceAuthority.serverConfirmed,
              ),
            )
            ..nextError = const NotificationCenterException(
              NotificationCenterErrorCode.network,
            );
      await tester.pumpWidget(
        _app(
          inbox: FakeNotificationInboxRepository(items: [_item]),
          interaction: FakeNotificationInteractionRepository(),
          mode: NotificationCenterPaneMode.profile,
          preferences: preferences,
        ),
      );
      await tester.pumpAndSettle();

      final medication = find.byKey(
        const Key('notifications.preferences.medication'),
      );
      await tester.tap(medication);
      await tester.pumpAndSettle();

      expect(
        find.text(
          const AppStrings(
            AppLocale.english,
          ).notificationPreferencesNetworkError,
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Switch>(
              find.descendant(of: medication, matching: find.byType(Switch)),
            )
            .value,
        isTrue,
      );
      final firstMutationId = preferences.clientMutationIds.single;

      await tester.tap(
        find.byKey(const Key('notifications.preferences.saveRetry')),
      );
      await tester.pumpAndSettle();

      expect(preferences.clientMutationIds, [firstMutationId, firstMutationId]);
      expect(
        find.byKey(const Key('notifications.preferences.saveRetry')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const Key('notifications.preferences.assignment')),
      );
      await tester.pumpAndSettle();
      expect(preferences.clientMutationIds.last, isNot(firstMutationId));
    },
  );

  testWidgets('preference repair failure retries the exact mutation id', (
    tester,
  ) async {
    final preferences =
        FakeNotificationPreferencesRepository(
            const NotificationPreferencesSnapshot(
              preferences: null,
              authority: NotificationPreferenceAuthority.malformed,
            ),
          )
          ..nextResetError = const NotificationCenterException(
            NotificationCenterErrorCode.backendUnavailable,
          );
    await tester.pumpWidget(
      _app(
        inbox: FakeNotificationInboxRepository(items: [_item]),
        interaction: FakeNotificationInteractionRepository(),
        mode: NotificationCenterPaneMode.profile,
        preferences: preferences,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('notifications.preferences.repair')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        const AppStrings(AppLocale.english).notificationPreferencesBackendError,
      ),
      findsOneWidget,
    );
    final firstMutationId = preferences.resetMutationIds.single;

    await tester.tap(
      find.byKey(const Key('notifications.preferences.saveRetry')),
    );
    await tester.pump();
    expect(preferences.resetMutationIds, [firstMutationId, firstMutationId]);
  });

  testWidgets(
    'epoch switch clears A and ignores stale callbacks while configuring B',
    (tester) async {
      final identity = ValueNotifier<String>('household-a');
      final inbox = _EpochInboxRepository();
      final device = _DelayedDeviceRepository();
      final delivery = _TrackingDeliveryRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationRepositoryProvider.overrideWithValue(
              const _NotificationRepository(),
            ),
            notificationDeviceRepositoryProvider.overrideWithValue(device),
            notificationPreferencesRepositoryProvider.overrideWithValue(
              FakeNotificationPreferencesRepository(
                const NotificationPreferencesSnapshot(
                  preferences: null,
                  authority: NotificationPreferenceAuthority.missingDefaults,
                ),
              ),
            ),
            notificationInboxRepositoryProvider.overrideWithValue(inbox),
            notificationDeliveryEvidenceRepositoryProvider.overrideWithValue(
              delivery,
            ),
            notificationInteractionRepositoryProvider.overrideWithValue(
              FakeNotificationInteractionRepository(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ValueListenableBuilder<String>(
                  valueListenable: identity,
                  builder: (context, householdId, _) => NotificationCenterPane(
                    mode: NotificationCenterPaneMode.updates,
                    householdId: householdId,
                    memberId: 'user-1',
                    memberJoinedAt: _joinedAt,
                    timeZoneIdentifier: 'Asia/Tokyo',
                    members: const [
                      Caregiver(id: 'user-1', displayName: 'Alex'),
                    ],
                    strings: const AppStrings(AppLocale.english),
                    changes: const Text('Changes'),
                    changesUnread: false,
                    onUnreadChanged: (_) {},
                    onRouteOpened: () {},
                    onRouteRejected: () {},
                    onChangesSelected: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      inbox.emit('household-a', _page([_itemFor('a')], null));
      await tester.pump();
      await tester.tap(find.byKey(const Key('notificationUpdates.reminders')));
      await tester.pump();
      expect(
        find.byKey(Key('notificationInbox.item.${'a' * 64}')),
        findsOneWidget,
      );

      identity.value = 'household-b';
      await tester.pump();
      expect(
        find.byKey(Key('notificationInbox.item.${'a' * 64}')),
        findsNothing,
      );
      inbox.emit('household-a', _page([_itemFor('c')], null));
      device.complete('household-a', 'a' * 64);
      await tester.pump();
      expect(
        find.byKey(Key('notificationInbox.item.${'c' * 64}')),
        findsNothing,
      );
      expect(delivery.observedHouseholds, isNot(contains('household-a')));

      device.complete('household-b', 'b' * 64);
      inbox.emit('household-b', _page([_itemFor('b')], null));
      await tester.pumpAndSettle();
      expect(
        find.byKey(Key('notificationInbox.item.${'b' * 64}')),
        findsOneWidget,
      );
      expect(delivery.observedHouseholds, contains('household-b'));
      expect(device.configured, ['household-a', 'household-b']);
    },
  );
}

Widget _app({
  required NotificationInboxRepository inbox,
  required FakeNotificationInteractionRepository interaction,
  ValueChanged<bool>? onUnreadChanged,
  VoidCallback? onRouteOpened,
  VoidCallback? onRouteRejected,
  NotificationCenterPaneMode mode = NotificationCenterPaneMode.updates,
  FakeNotificationPreferencesRepository? preferences,
}) => ProviderScope(
  overrides: [
    notificationRepositoryProvider.overrideWithValue(
      const _NotificationRepository(),
    ),
    notificationDeviceRepositoryProvider.overrideWithValue(
      const LegacyNotificationDeviceRepository(_NotificationRepository()),
    ),
    notificationPreferencesRepositoryProvider.overrideWithValue(
      preferences ??
          FakeNotificationPreferencesRepository(
            const NotificationPreferencesSnapshot(
              preferences: null,
              authority: NotificationPreferenceAuthority.missingDefaults,
            ),
          ),
    ),
    notificationInboxRepositoryProvider.overrideWithValue(inbox),
    notificationDeliveryEvidenceRepositoryProvider.overrideWithValue(
      FakeNotificationDeliveryEvidenceRepository(
        const NotificationProviderEvidenceSnapshot(
          evidence:
              NotificationProviderEvidence.notVerifiedForCurrentInstallation,
          authority: NotificationObservationAuthority.serverConfirmed,
          updatedAt: null,
          attemptCount: 0,
        ),
      ),
    ),
    notificationInteractionRepositoryProvider.overrideWithValue(interaction),
  ],
  child: MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: NotificationCenterPane(
          mode: mode,
          householdId: 'household-1',
          memberId: 'user-1',
          memberJoinedAt: _joinedAt,
          timeZoneIdentifier: 'Asia/Tokyo',
          members: const [Caregiver(id: 'user-1', displayName: 'Alex')],
          strings: const AppStrings(AppLocale.english),
          changes: const Text('Changes content'),
          changesUnread: false,
          onUnreadChanged: onUnreadChanged ?? (_) {},
          onRouteOpened: onRouteOpened ?? () {},
          onRouteRejected: onRouteRejected ?? () {},
          onChangesSelected: () {},
        ),
      ),
    ),
  ),
);

NotificationInboxPage _page(
  List<NotificationInboxItem> items,
  NotificationInboxPageCursor? cursor,
) => NotificationInboxPage(
  items: items,
  droppedItemCount: 0,
  authority: NotificationObservationAuthority.serverConfirmed,
  hasPendingWrites: false,
  mayHaveMore: cursor != null,
  nextCursor: cursor,
);

final class _Cursor implements NotificationInboxPageCursor {
  const _Cursor(this.label);

  final String label;
}

extension on NotificationInboxPage {
  NotificationInboxPage copyWith({
    int? droppedItemCount,
    NotificationObservationAuthority? authority,
    bool? hasPendingWrites,
  }) => NotificationInboxPage(
    items: items,
    droppedItemCount: droppedItemCount ?? this.droppedItemCount,
    authority: authority ?? this.authority,
    hasPendingWrites: hasPendingWrites ?? this.hasPendingWrites,
    mayHaveMore: mayHaveMore,
    nextCursor: nextCursor,
    itemAuthorities: itemAuthorities,
  );
}

final class _CursorConvergenceInboxRepository
    implements NotificationInboxRepository {
  final _cursor = StreamController<NotificationReadCursorSnapshot>.broadcast();
  int markReadCalls = 0;

  void confirmCursor() => _cursor.add(
    const NotificationReadCursorSnapshot(
      cursor: null,
      authority: NotificationCursorAuthority.serverConfirmed,
    ),
  );

  @override
  Stream<NotificationInboxPage> observeRecent({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
  }) => Stream.value(_page([_item], null));

  @override
  Stream<NotificationReadCursorSnapshot> observeReadCursor({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
  }) => _cursor.stream;

  @override
  Future<void> markRead(
    String householdId,
    DateTime memberJoinedAt,
    NotificationReadCursor cursor,
  ) async => markReadCalls += 1;

  @override
  Future<NotificationInboxPage> loadRecent({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
    NotificationInboxPageCursor? after,
  }) async => _page(const [], null);

  @override
  Future<NotificationInboxItem> loadByIDFromServer({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
    required String inboxItemId,
  }) async => _item;
}

final class _MixedAuthorityInboxRepository
    implements NotificationInboxRepository {
  final _recent = StreamController<NotificationInboxPage>.broadcast();
  int markReadCalls = 0;

  void emitServerRecent() => _recent.add(
    _page([
      _item.copyWith(status: NotificationInboxStatus.cancelled),
    ], const _Cursor('recent')),
  );

  @override
  Stream<NotificationInboxPage> observeRecent({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
  }) {
    scheduleMicrotask(emitServerRecent);
    return _recent.stream;
  }

  @override
  Future<NotificationInboxPage> loadRecent({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
    NotificationInboxPageCursor? after,
  }) async => NotificationInboxPage(
    items: [_itemFor('b', householdId: 'household-1')],
    droppedItemCount: 0,
    authority: NotificationObservationAuthority.cached,
    hasPendingWrites: false,
    mayHaveMore: false,
    nextCursor: null,
  );

  @override
  Stream<NotificationReadCursorSnapshot> observeReadCursor({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
  }) => Stream.value(
    const NotificationReadCursorSnapshot(
      cursor: null,
      authority: NotificationCursorAuthority.serverConfirmed,
    ),
  );

  @override
  Future<void> markRead(
    String householdId,
    DateTime memberJoinedAt,
    NotificationReadCursor cursor,
  ) async => markReadCalls += 1;

  @override
  Future<NotificationInboxItem> loadByIDFromServer({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
    required String inboxItemId,
  }) async => _item;
}

final class _SinglePageInboxRepository implements NotificationInboxRepository {
  _SinglePageInboxRepository(this.page);

  final NotificationInboxPage page;
  int markReadCalls = 0;

  @override
  Stream<NotificationInboxPage> observeRecent({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
  }) => Stream.value(page);

  @override
  Future<NotificationInboxPage> loadRecent({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
    NotificationInboxPageCursor? after,
  }) async => page;

  @override
  Future<NotificationInboxItem> loadByIDFromServer({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
    required String inboxItemId,
  }) async => page.items.first;

  @override
  Stream<NotificationReadCursorSnapshot> observeReadCursor({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
  }) => Stream.value(
    const NotificationReadCursorSnapshot(
      cursor: null,
      authority: NotificationCursorAuthority.serverConfirmed,
    ),
  );

  @override
  Future<void> markRead(
    String householdId,
    DateTime memberJoinedAt,
    NotificationReadCursor cursor,
  ) async => markReadCalls += 1;
}

final class _LoadMoreMarkRepository implements NotificationInboxRepository {
  int markReadCalls = 0;
  NotificationReadCursor? marked;

  @override
  Stream<NotificationInboxPage> observeRecent({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
  }) => Stream.value(
    _page([
      _item.copyWith(status: NotificationInboxStatus.cancelled),
    ], const _Cursor('older')),
  );

  @override
  Future<NotificationInboxPage> loadRecent({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
    NotificationInboxPageCursor? after,
  }) async => _page([_item], null);

  @override
  Future<NotificationInboxItem> loadByIDFromServer({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
    required String inboxItemId,
  }) async => _item;

  @override
  Stream<NotificationReadCursorSnapshot> observeReadCursor({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
  }) => Stream.value(
    const NotificationReadCursorSnapshot(
      cursor: null,
      authority: NotificationCursorAuthority.serverConfirmed,
    ),
  );

  @override
  Future<void> markRead(
    String householdId,
    DateTime memberJoinedAt,
    NotificationReadCursor cursor,
  ) async {
    markReadCalls += 1;
    marked = cursor;
  }
}

final class _ExactLoadMoreRetryRepository
    implements NotificationInboxRepository {
  final _recent = StreamController<NotificationInboxPage>();
  final afterLabels = <String>[];
  int markReadCalls = 0;
  NotificationReadCursor? marked;

  void emitRecent(NotificationInboxPage page) => _recent.add(page);

  @override
  Stream<NotificationInboxPage> observeRecent({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
  }) => _recent.stream;

  @override
  Future<NotificationInboxPage> loadRecent({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
    NotificationInboxPageCursor? after,
  }) async {
    afterLabels.add((after! as _Cursor).label);
    if (afterLabels.length == 1) {
      throw const NotificationCenterException(
        NotificationCenterErrorCode.network,
      );
    }
    return _page([_item], null);
  }

  @override
  Future<NotificationInboxItem> loadByIDFromServer({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
    required String inboxItemId,
  }) async => _item;

  @override
  Stream<NotificationReadCursorSnapshot> observeReadCursor({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
  }) => Stream.value(
    const NotificationReadCursorSnapshot(
      cursor: null,
      authority: NotificationCursorAuthority.serverConfirmed,
    ),
  );

  @override
  Future<void> markRead(
    String householdId,
    DateTime memberJoinedAt,
    NotificationReadCursor cursor,
  ) async {
    markReadCalls += 1;
    marked = cursor;
  }
}

final class _PagedInboxRepository implements NotificationInboxRepository {
  final _recent = StreamController<NotificationInboxPage>();
  final afterLabels = <String>[];

  void emitRecent(NotificationInboxPage page) => _recent.add(page);

  @override
  Stream<NotificationInboxPage> observeRecent({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
  }) => _recent.stream;

  @override
  Future<NotificationInboxPage> loadRecent({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
    NotificationInboxPageCursor? after,
  }) async {
    final cursor = after! as _Cursor;
    afterLabels.add(cursor.label);
    final next = cursor.label == 'recent-1' ? 'older-2' : 'older-3';
    return _page(const [], _Cursor(next));
  }

  @override
  Future<NotificationInboxItem> loadByIDFromServer({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
    required String inboxItemId,
  }) async => _item;

  @override
  Stream<NotificationReadCursorSnapshot> observeReadCursor({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
  }) => const Stream.empty();

  @override
  Future<void> markRead(
    String householdId,
    DateTime memberJoinedAt,
    NotificationReadCursor cursor,
  ) async {}
}

final class _EpochInboxRepository implements NotificationInboxRepository {
  final _controllers = <String, StreamController<NotificationInboxPage>>{};

  void emit(String householdId, NotificationInboxPage page) =>
      _controllers[householdId]?.add(page);

  @override
  Stream<NotificationInboxPage> observeRecent({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
  }) => (_controllers[householdId] ??= StreamController.broadcast()).stream;

  @override
  Future<NotificationInboxPage> loadRecent({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
    NotificationInboxPageCursor? after,
  }) async => _page(const [], null);

  @override
  Future<NotificationInboxItem> loadByIDFromServer({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
    required String inboxItemId,
  }) async => _itemFor(inboxItemId[0], householdId: householdId);

  @override
  Stream<NotificationReadCursorSnapshot> observeReadCursor({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
  }) => Stream.value(
    const NotificationReadCursorSnapshot(
      cursor: null,
      authority: NotificationCursorAuthority.serverConfirmed,
    ),
  );

  @override
  Future<void> markRead(
    String householdId,
    DateTime memberJoinedAt,
    NotificationReadCursor cursor,
  ) async {}
}

final class _DelayedDeviceRepository implements NotificationDeviceRepository {
  final configured = <String>[];
  final _completers = <String, Completer<NotificationDeviceSnapshot>>{};

  @override
  Future<NotificationDeviceSnapshot> configureDevice(String householdId) {
    configured.add(householdId);
    return (_completers[householdId] ??= Completer()).future;
  }

  void complete(String householdId, String hash) =>
      _completers[householdId]!.complete(
        NotificationDeviceSnapshot(
          osPermission: NotificationOsPermission.authorized,
          installationReadiness: NotificationInstallationReadiness.ready,
          installationHash: hash,
        ),
      );

  @override
  Future<NotificationDeviceSnapshot> requestDevicePermission(
    String householdId,
  ) => configureDevice(householdId);
}

final class _TrackingDeliveryRepository
    implements NotificationDeliveryEvidenceRepository {
  final observedHouseholds = <String>[];

  @override
  Stream<NotificationProviderEvidenceSnapshot> observe({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
    required String installationHash,
  }) {
    observedHouseholds.add(householdId);
    return Stream.value(
      const NotificationProviderEvidenceSnapshot(
        evidence:
            NotificationProviderEvidence.notVerifiedForCurrentInstallation,
        authority: NotificationObservationAuthority.serverConfirmed,
        updatedAt: null,
        attemptCount: 0,
      ),
    );
  }
}

const _id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
final _joinedAt = DateTime.utc(2026, 8, 1);
final _item = NotificationInboxItem(
  id: _id,
  householdId: 'household-1',
  recipientId: 'user-1',
  recipientJoinedAt: _joinedAt,
  category: NotificationInboxCategory.assignment,
  level: NotificationInboxLevel.responsibilityProposal,
  routeReason: NotificationRouteReason.directTarget,
  sourceType: NotificationSourceType.taskResponsibilityTransfer,
  sourceId: 'transfer-1',
  sourcePath: 'taskResponsibilityTransfers/transfer-1',
  sourceRevision: 1,
  preferenceRevision: 1,
  status: NotificationInboxStatus.active,
  availableAt: DateTime.utc(2026, 8, 17),
  expiresAt: DateTime.utc(2026, 8, 18),
  createdAt: DateTime.utc(2026, 8, 17),
  updatedAt: DateTime.utc(2026, 8, 17),
);

NotificationInboxItem _itemFor(
  String seed, {
  String householdId = 'household-a',
}) => NotificationInboxItem(
  id: seed * 64,
  householdId: householdId,
  recipientId: 'user-1',
  recipientJoinedAt: _joinedAt,
  category: NotificationInboxCategory.assignment,
  level: NotificationInboxLevel.responsibilityProposal,
  routeReason: NotificationRouteReason.directTarget,
  sourceType: NotificationSourceType.taskResponsibilityTransfer,
  sourceId: 'transfer-$seed',
  sourcePath: 'taskResponsibilityTransfers/transfer-$seed',
  sourceRevision: 1,
  preferenceRevision: 1,
  status: NotificationInboxStatus.active,
  availableAt: DateTime.utc(2026, 8, 17),
  expiresAt: DateTime.utc(2026, 8, 18),
  createdAt: DateTime.utc(2026, 8, 17),
  updatedAt: DateTime.utc(2026, 8, 17),
);

final class _NotificationRepository implements NotificationRepository {
  const _NotificationRepository();

  @override
  Future<NotificationPermissionStatus> configure(String householdId) async =>
      NotificationPermissionStatus.authorized;

  @override
  Future<NotificationPermissionStatus> requestPermission(
    String householdId,
  ) async => NotificationPermissionStatus.authorized;

  @override
  Future<void> disable() async {}

  @override
  Future<void> openSettings() async {}

  @override
  Future<void> stop() async {}
}
