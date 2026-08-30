import 'dart:ui' as ui;

import 'package:copaw_flutter/src/data/notification_center_repository.dart';
import 'package:copaw_flutter/src/data/notification_center_gateway.dart';
import 'package:copaw_flutter/src/domain/notification_models.dart';
import 'package:copaw_flutter/src/localization/app_locale.dart';
import 'package:copaw_flutter/src/views/notification_center_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in const [Size(320, 568), Size(390, 844)]) {
    for (final locale in AppLocale.values) {
      for (final scale in const [1.0, 2.0, 3.0]) {
        testWidgets(
          'compact reminders ${size.width} ${locale.name} ${scale}x',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            final strings = AppStrings(locale);
            await tester.pumpWidget(
              MaterialApp(
                locale: locale.locale,
                home: MediaQuery(
                  data: MediaQueryData(
                    size: size,
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: Scaffold(
                    body: SingleChildScrollView(
                      child: Column(
                        children: [
                          NotificationUpdatesSwitcher(
                            strings: strings,
                            selection: NotificationUpdatesSection.reminders,
                            changesUnread: true,
                            remindersUnread: true,
                            onChanged: (_) {},
                          ),
                          NotificationInboxCard(
                            strings: strings,
                            page: _page,
                            loading: false,
                            errorMessage: strings.notificationInboxLongError,
                            onRetry: () {},
                            onLoadMore: () {},
                            onOpenItem: (_) {},
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pump();

            expect(tester.takeException(), isNull);
            expect(
              find.byKey(const Key('notificationUpdates.reminders')),
              findsOneWidget,
            );
            expect(
              find.byKey(const Key('notificationInbox.retry')),
              findsOneWidget,
            );
            expect(
              find.byKey(const Key('notificationInbox.item.$_intentId')),
              findsOneWidget,
            );
            expect(
              tester
                  .getSemantics(
                    find.byKey(const Key('notificationInbox.item.$_intentId')),
                  )
                  .label,
              contains(
                strings.notificationRouteReason(
                  NotificationRouteReason.directTarget,
                ),
              ),
            );
            expect(
              tester
                  .getSize(
                    find.byKey(const Key('notificationUpdates.reminders')),
                  )
                  .height,
              greaterThanOrEqualTo(44),
            );
            final selected = tester.getSemantics(
              find.byKey(const Key('notificationUpdates.reminders')),
            );
            expect(selected.flagsCollection.isSelected, ui.Tristate.isTrue);
            expect(
              selected.getSemanticsData().hasAction(ui.SemanticsAction.tap),
              isTrue,
            );
            expect(
              tester
                  .getSemantics(
                    find.byKey(const Key('notificationInbox.item.$_intentId')),
                  )
                  .getSemanticsData()
                  .hasAction(ui.SemanticsAction.tap),
              isTrue,
            );
          },
        );
      }
    }
  }

  testWidgets('profile exposes independent layers and repair action', (
    tester,
  ) async {
    final strings = AppStrings(AppLocale.english);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: NotificationProfileCard(
              strings: strings,
              capability: const NotificationCapability(
                osPermission: NotificationOsPermission.authorized,
                preferenceAuthority: NotificationPreferenceAuthority.malformed,
                installationReadiness:
                    NotificationInstallationReadiness.registering,
                providerEvidence: NotificationProviderEvidence.providerUnknown,
                providerAuthority: NotificationObservationAuthority.cached,
              ),
              providerSnapshot: NotificationProviderEvidenceSnapshot(
                evidence: NotificationProviderEvidence.providerUnknown,
                authority: NotificationObservationAuthority.cached,
                updatedAt: DateTime.utc(2026, 8, 17, 3),
                attemptCount: 2,
              ),
              preferences: null,
              memberNamesById: const {},
              saving: false,
              mutationError: null,
              onEnablePermission: () {},
              onOpenSettings: () {},
              onRetryDevice: () {},
              onRetryPreferences: () {},
              onRetryPreferenceSave: () {},
              onRepairPreferences: () {},
              onPreferenceChanged: (_, _) {},
              onBackupChanged: (_) {},
              onMinuteChanged: (_, _) {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('notifications.preferences.repair')),
      findsOneWidget,
    );
    expect(find.text(strings.notificationOsAuthorized), findsOneWidget);
    expect(
      find.text(strings.notificationInstallationRegistering),
      findsOneWidget,
    );
    expect(
      find.text(strings.notificationProviderCachedUnknown),
      findsOneWidget,
    );
    expect(find.text(strings.notificationProviderScope), findsOneWidget);
    expect(find.text(strings.notificationProviderAttemptTime), findsOneWidget);
  });

  testWidgets(
    'provider disabled is terminal and preferences error only retries',
    (tester) async {
      final strings = AppStrings(AppLocale.english);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: NotificationProfileCard(
                strings: strings,
                capability: const NotificationCapability(
                  osPermission: NotificationOsPermission.unsupported,
                  preferenceAuthority: NotificationPreferenceAuthority.error,
                  installationReadiness:
                      NotificationInstallationReadiness.unsupported,
                  providerEvidence: NotificationProviderEvidence
                      .notVerifiedForCurrentInstallation,
                  providerAuthority: NotificationObservationAuthority.error,
                ),
                providerSnapshot: null,
                preferences: null,
                memberNamesById: const {},
                saving: false,
                mutationError: null,
                onEnablePermission: () {},
                onOpenSettings: () {},
                onRetryDevice: () {},
                onRetryPreferences: () {},
                onRetryPreferenceSave: () {},
                onRepairPreferences: () {},
                onPreferenceChanged: (_, _) {},
                onBackupChanged: (_) {},
                onMinuteChanged: (_, _) {},
              ),
            ),
          ),
        ),
      );

      expect(
        find.text(strings.notificationProviderNotConfigured),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('notifications.preferences.retry')),
        findsOneWidget,
      );
      expect(find.byType(SwitchListTile), findsNothing);
    },
  );

  testWidgets('profile time controls remain readable at 320pt Japanese 3x', (
    tester,
  ) async {
    const size = Size(320, 568);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final strings = AppStrings(AppLocale.japanese);
    final preferences = HouseholdNotificationPreferences.conservative(
      uid: 'user-1',
      householdId: 'household-1',
      memberJoinedAt: _joinedAt,
      timeZoneIdentifier: 'Asia/Tokyo',
    ).copyWith(quietHoursEnabled: true, summaryEnabled: true);
    await tester.pumpWidget(
      MaterialApp(
        locale: AppLocale.japanese.locale,
        home: MediaQuery(
          data: const MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(3),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: NotificationProfileCard(
                strings: strings,
                capability: const NotificationCapability(
                  osPermission: NotificationOsPermission.authorized,
                  preferenceAuthority:
                      NotificationPreferenceAuthority.serverConfirmed,
                  installationReadiness:
                      NotificationInstallationReadiness.ready,
                  providerEvidence:
                      NotificationProviderEvidence.providerAccepted,
                  providerAuthority:
                      NotificationObservationAuthority.serverConfirmed,
                ),
                providerSnapshot: NotificationProviderEvidenceSnapshot(
                  evidence: NotificationProviderEvidence.providerAccepted,
                  authority: NotificationObservationAuthority.serverConfirmed,
                  updatedAt: DateTime.utc(2026, 8, 17, 3),
                  attemptCount: 1,
                ),
                preferences: preferences,
                memberNamesById: const {'user-2': '長い名前の代理ケア担当者'},
                saving: false,
                mutationError: null,
                onEnablePermission: () {},
                onOpenSettings: () {},
                onRetryDevice: () {},
                onRetryPreferences: () {},
                onRetryPreferenceSave: () {},
                onRepairPreferences: () {},
                onPreferenceChanged: (_, _) {},
                onBackupChanged: (_) {},
                onMinuteChanged: (_, _) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    for (final key in const [
      Key('notifications.preferences.quietStart'),
      Key('notifications.preferences.quietEnd'),
      Key('notifications.preferences.summaryMinute'),
    ]) {
      expect(find.byKey(key), findsOneWidget);
      expect(tester.getSize(find.byKey(key)).height, greaterThanOrEqualTo(44));
    }
  });

  testWidgets('disabled reminder and time controls expose no tap action', (
    tester,
  ) async {
    final strings = AppStrings(AppLocale.english);
    final disabledItem = _page.items.single.copyWith(
      status: NotificationInboxStatus.cancelled,
    );
    final preferences = HouseholdNotificationPreferences.conservative(
      uid: 'user-1',
      householdId: 'household-1',
      memberJoinedAt: _joinedAt,
      timeZoneIdentifier: 'Asia/Tokyo',
    ).copyWith(quietHoursEnabled: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                NotificationInboxCard(
                  strings: strings,
                  page: NotificationInboxPage(
                    items: [disabledItem],
                    droppedItemCount: 0,
                    authority: NotificationObservationAuthority.serverConfirmed,
                    hasPendingWrites: false,
                    mayHaveMore: false,
                    nextCursor: null,
                  ),
                  loading: false,
                  errorMessage: strings.notificationInboxLongError,
                  onRetry: () {},
                  onLoadMore: () {},
                  onOpenItem: (_) {},
                ),
                NotificationProfileCard(
                  strings: strings,
                  capability: const NotificationCapability(
                    osPermission: NotificationOsPermission.authorized,
                    preferenceAuthority:
                        NotificationPreferenceAuthority.serverConfirmed,
                    installationReadiness:
                        NotificationInstallationReadiness.ready,
                    providerEvidence:
                        NotificationProviderEvidence.providerAccepted,
                    providerAuthority:
                        NotificationObservationAuthority.serverConfirmed,
                  ),
                  providerSnapshot: null,
                  preferences: preferences,
                  memberNamesById: const {},
                  saving: true,
                  mutationError: null,
                  onEnablePermission: () {},
                  onOpenSettings: () {},
                  onRetryDevice: () {},
                  onRetryPreferences: () {},
                  onRetryPreferenceSave: () {},
                  onRepairPreferences: () {},
                  onPreferenceChanged: (_, _) {},
                  onBackupChanged: (_) {},
                  onMinuteChanged: (_, _) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final unavailableLabel = strings.notificationInboxUnavailable;
    expect(find.bySemanticsLabel(unavailableLabel), findsOneWidget);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel(unavailableLabel))
          .getSemanticsData()
          .hasAction(ui.SemanticsAction.tap),
      isFalse,
    );
    final time = tester.getSemantics(
      find.byKey(const Key('notifications.preferences.quietStart')),
    );
    expect(time.getSemanticsData().hasAction(ui.SemanticsAction.tap), isFalse);
  });

  testWidgets('inbox loading empty and pending states stay distinct', (
    tester,
  ) async {
    final strings = AppStrings(AppLocale.english);

    Future<void> pump({
      required NotificationInboxPage? page,
      required bool loading,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationInboxCard(
            strings: strings,
            page: page,
            loading: loading,
            errorMessage: null,
            onRetry: () {},
            onLoadMore: () {},
          ),
        ),
      ),
    );

    await pump(page: null, loading: true);
    expect(find.byKey(const Key('notificationInbox.loading')), findsOneWidget);
    expect(find.byKey(const Key('notificationInbox.empty')), findsNothing);

    await pump(
      page: const NotificationInboxPage(
        items: [],
        droppedItemCount: 0,
        authority: NotificationObservationAuthority.serverConfirmed,
        hasPendingWrites: false,
        mayHaveMore: false,
        nextCursor: null,
      ),
      loading: false,
    );
    expect(find.byKey(const Key('notificationInbox.empty')), findsOneWidget);

    await pump(
      page: const NotificationInboxPage(
        items: [],
        droppedItemCount: 0,
        authority: NotificationObservationAuthority.serverConfirmed,
        hasPendingWrites: true,
        mayHaveMore: false,
        nextCursor: null,
      ),
      loading: false,
    );
    expect(find.byKey(const Key('notificationInbox.pending')), findsOneWidget);
    expect(find.byKey(const Key('notificationInbox.empty')), findsNothing);
  });

  for (final entry in const [
    (
      NotificationObservationAuthority.loading,
      'Refreshing. The last recorded attempt is retained but is not current.',
    ),
    (
      NotificationObservationAuthority.error,
      'Refresh failed. The last recorded attempt is retained; current provider status is unknown.',
    ),
  ]) {
    testWidgets('provider ${entry.$1.name} retains stale evidence honestly', (
      tester,
    ) async {
      final strings = AppStrings(AppLocale.english);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: NotificationProfileCard(
                strings: strings,
                capability: NotificationCapability(
                  osPermission: NotificationOsPermission.authorized,
                  preferenceAuthority:
                      NotificationPreferenceAuthority.serverConfirmed,
                  installationReadiness:
                      NotificationInstallationReadiness.ready,
                  providerEvidence:
                      NotificationProviderEvidence.providerAccepted,
                  providerAuthority: entry.$1,
                ),
                providerSnapshot: NotificationProviderEvidenceSnapshot(
                  evidence: NotificationProviderEvidence.providerAccepted,
                  authority: entry.$1,
                  updatedAt: DateTime.utc(2026, 8, 17, 3),
                  attemptCount: 2,
                ),
                preferences: null,
                memberNamesById: const {},
                saving: false,
                mutationError: null,
                onEnablePermission: () {},
                onOpenSettings: () {},
                onRetryDevice: () {},
                onRetryPreferences: () {},
                onRetryPreferenceSave: () {},
                onRepairPreferences: () {},
                onPreferenceChanged: (_, _) {},
                onBackupChanged: (_) {},
                onMinuteChanged: (_, _) {},
              ),
            ),
          ),
        ),
      );

      expect(find.textContaining(entry.$2), findsOneWidget);
      expect(find.text(strings.notificationProviderScope), findsOneWidget);
    });
  }

  testWidgets(
    'provider transition matrix preserves stale evidence then accepts fresh',
    (tester) async {
      final strings = AppStrings(AppLocale.english);

      Future<void> pump(NotificationProviderEvidenceSnapshot snapshot) =>
          tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: NotificationProfileCard(
                    strings: strings,
                    capability: NotificationCapability(
                      osPermission: NotificationOsPermission.authorized,
                      preferenceAuthority:
                          NotificationPreferenceAuthority.serverConfirmed,
                      installationReadiness:
                          NotificationInstallationReadiness.ready,
                      providerEvidence: snapshot.evidence,
                      providerAuthority: snapshot.authority,
                    ),
                    providerSnapshot: snapshot,
                    preferences: null,
                    memberNamesById: const {},
                    saving: false,
                    mutationError: null,
                    onEnablePermission: () {},
                    onOpenSettings: () {},
                    onRetryDevice: () {},
                    onRetryPreferences: () {},
                    onRetryPreferenceSave: () {},
                    onRepairPreferences: () {},
                    onPreferenceChanged: (_, _) {},
                    onBackupChanged: (_) {},
                    onMinuteChanged: (_, _) {},
                  ),
                ),
              ),
            ),
          );

      final time = DateTime.utc(2026, 8, 17, 3);
      await pump(
        NotificationProviderEvidenceSnapshot(
          evidence: NotificationProviderEvidence.providerAccepted,
          authority: NotificationObservationAuthority.serverConfirmed,
          updatedAt: time,
          attemptCount: 1,
        ),
      );
      expect(find.text(strings.notificationProviderAccepted), findsOneWidget);

      await pump(
        NotificationProviderEvidenceSnapshot(
          evidence: NotificationProviderEvidence.providerAccepted,
          authority: NotificationObservationAuthority.error,
          updatedAt: time,
          attemptCount: 1,
        ),
      );
      expect(
        find.textContaining(strings.notificationProviderRefreshErrorStale),
        findsOneWidget,
      );
      expect(
        find.textContaining(strings.notificationProviderAccepted),
        findsOneWidget,
      );

      await pump(
        NotificationProviderEvidenceSnapshot(
          evidence: NotificationProviderEvidence.definiteFailure,
          authority: NotificationObservationAuthority.loading,
          updatedAt: time,
          attemptCount: 2,
        ),
      );
      expect(
        find.textContaining(strings.notificationProviderRefreshingStale),
        findsOneWidget,
      );
      expect(
        find.textContaining(strings.notificationProviderFailure),
        findsOneWidget,
      );

      await pump(
        NotificationProviderEvidenceSnapshot(
          evidence: NotificationProviderEvidence.definiteFailure,
          authority: NotificationObservationAuthority.cached,
          updatedAt: time,
          attemptCount: 2,
        ),
      );
      expect(
        find.text(strings.notificationProviderCachedUnknown),
        findsOneWidget,
      );

      await pump(
        NotificationProviderEvidenceSnapshot(
          evidence: NotificationProviderEvidence.providerAccepted,
          authority: NotificationObservationAuthority.serverConfirmed,
          updatedAt: time.add(const Duration(minutes: 1)),
          attemptCount: 3,
        ),
      );
      expect(find.text(strings.notificationProviderAccepted), findsOneWidget);
    },
  );
}

const _intentId =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
final _joinedAt = DateTime.utc(2026, 8, 1);
final _page = NotificationInboxPage(
  items: [
    NotificationInboxItem(
      id: _intentId,
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
      preferenceRevision: 2,
      status: NotificationInboxStatus.active,
      availableAt: DateTime.utc(2026, 8, 17, 1),
      expiresAt: DateTime.utc(2026, 8, 18, 1),
      createdAt: DateTime.utc(2026, 8, 17, 1),
      updatedAt: DateTime.utc(2026, 8, 17, 1),
    ),
  ],
  droppedItemCount: 1,
  authority: NotificationObservationAuthority.cached,
  hasPendingWrites: false,
  mayHaveMore: true,
  nextCursor: StoredNotificationPageCursor('cursor'),
);
