import 'package:copaw_flutter/src/domain/notification_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final active = NotificationInboxItem(
    id: 'a' * 64,
    householdId: 'household-1',
    recipientId: 'member-1',
    recipientJoinedAt: DateTime.utc(2026, 8, 17),
    category: NotificationInboxCategory.medication,
    level: NotificationInboxLevel.due,
    routeReason: NotificationRouteReason.responsible,
    sourceType: NotificationSourceType.medicationOccurrence,
    sourceId: 'occurrence-1',
    sourcePath: 'medicationOccurrences/occurrence-1',
    sourceRevision: 1,
    preferenceRevision: 2,
    status: NotificationInboxStatus.active,
    availableAt: DateTime.utc(2026, 8, 17, 9),
    expiresAt: DateTime.utc(2026, 8, 17, 9, 15),
    createdAt: DateTime.utc(2026, 8, 17, 8, 59),
    updatedAt: DateTime.utc(2026, 8, 17, 8, 59),
  );

  test(
    'unread truth table never invents a dot without active or dropped evidence',
    () {
      expect(
        NotificationUnreadPolicy.hasUnread(
          items: const [],
          droppedItemCount: 0,
          cursor: null,
          cursorAuthority: NotificationCursorAuthority.unknown,
          pageAuthority: NotificationObservationAuthority.loading,
          previousValue: false,
        ),
        isFalse,
      );
      expect(
        NotificationUnreadPolicy.hasUnread(
          items: [active.copyWith(status: NotificationInboxStatus.cancelled)],
          droppedItemCount: 0,
          cursor: null,
          cursorAuthority: NotificationCursorAuthority.serverConfirmed,
          pageAuthority: NotificationObservationAuthority.serverConfirmed,
          previousValue: true,
        ),
        isFalse,
      );
      expect(
        NotificationUnreadPolicy.hasUnread(
          items: [active],
          droppedItemCount: 0,
          cursor: null,
          cursorAuthority: NotificationCursorAuthority.unknown,
          pageAuthority: NotificationObservationAuthority.cached,
          previousValue: false,
        ),
        isTrue,
      );
      expect(
        NotificationUnreadPolicy.hasUnread(
          items: const [],
          droppedItemCount: 1,
          cursor: null,
          cursorAuthority: NotificationCursorAuthority.serverConfirmed,
          pageAuthority: NotificationObservationAuthority.serverConfirmed,
          previousValue: false,
        ),
        isTrue,
      );
    },
  );

  test('server cursor uses createdAt then intent ID tie-break', () {
    final earlier = NotificationReadCursor(
      createdAt: active.createdAt,
      intentId: 'a' * 64,
    );
    final later = NotificationReadCursor(
      createdAt: active.createdAt,
      intentId: 'b' * 64,
    );
    expect(NotificationReadCursor.compare(later, earlier), greaterThan(0));
    expect(
      NotificationUnreadPolicy.hasUnread(
        items: [active.copyWith(id: 'b' * 64)],
        droppedItemCount: 0,
        cursor: earlier,
        cursorAuthority: NotificationCursorAuthority.serverConfirmed,
        pageAuthority: NotificationObservationAuthority.serverConfirmed,
        previousValue: false,
      ),
      isTrue,
    );
  });

  test('provider evidence and observation authority stay independent', () {
    const capability = NotificationCapability(
      osPermission: NotificationOsPermission.authorized,
      preferenceAuthority: NotificationPreferenceAuthority.cached,
      installationReadiness: NotificationInstallationReadiness.registering,
      providerEvidence: NotificationProviderEvidence.providerAccepted,
      providerAuthority: NotificationObservationAuthority.cached,
    );
    expect(capability.osPermission, NotificationOsPermission.authorized);
    expect(
      capability.installationReadiness,
      NotificationInstallationReadiness.registering,
    );
    expect(
      capability.providerEvidence,
      NotificationProviderEvidence.providerAccepted,
    );
    expect(
      capability.providerAuthority,
      NotificationObservationAuthority.cached,
    );
    expect(capability.hasCurrentProviderEvidence, isFalse);
  });

  test('pending route relaunch turns resolving into retryable', () {
    final route = NotificationPendingRoute(
      payload: const NotificationRoutePayload(
        householdId: 'household-1',
        inboxItemId:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ),
      state: NotificationPendingRouteState.resolving,
      generation: 7,
    );
    expect(
      route.normalizedForLaunch().state,
      NotificationPendingRouteState.retryable,
    );
    expect(route.normalizedForLaunch().generation, 7);
  });
}
