import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/notification_models.dart';
import 'notification_center_gateway.dart';

final class NotificationPreferencesSnapshot {
  const NotificationPreferencesSnapshot({
    required this.preferences,
    required this.authority,
  });

  final HouseholdNotificationPreferences? preferences;
  final NotificationPreferenceAuthority authority;
}

final class NotificationPreferenceMutationResult {
  const NotificationPreferenceMutationResult({
    required this.householdId,
    required this.revision,
    required this.existing,
  });

  final String householdId;
  final int revision;
  final bool existing;
}

abstract interface class NotificationPreferencesRepository {
  Stream<NotificationPreferencesSnapshot> observe({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
    required String timeZoneIdentifier,
  });

  Future<NotificationPreferenceMutationResult> save(
    HouseholdNotificationPreferences preferences, {
    required String clientMutationId,
  });

  Future<NotificationPreferenceMutationResult> resetMalformed({
    required String householdId,
    required String clientMutationId,
  });

  Future<void> stop();
}

final class NotificationInboxPage {
  const NotificationInboxPage({
    required this.items,
    required this.droppedItemCount,
    required this.authority,
    required this.hasPendingWrites,
    required this.mayHaveMore,
    required this.nextCursor,
    this.itemAuthorities = const {},
  });

  final List<NotificationInboxItem> items;
  final int droppedItemCount;
  final NotificationObservationAuthority authority;
  final bool hasPendingWrites;
  final bool mayHaveMore;
  final NotificationInboxPageCursor? nextCursor;
  final Map<String, NotificationObservationAuthority> itemAuthorities;

  NotificationObservationAuthority authorityFor(NotificationInboxItem item) =>
      itemAuthorities[item.id] ?? authority;
}

final class NotificationReadCursorSnapshot {
  const NotificationReadCursorSnapshot({
    required this.cursor,
    required this.authority,
  });

  final NotificationReadCursor? cursor;
  final NotificationCursorAuthority authority;
}

abstract interface class NotificationInboxRepository {
  Stream<NotificationInboxPage> observeRecent({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
  });

  Future<NotificationInboxPage> loadRecent({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
    NotificationInboxPageCursor? after,
  });

  Future<NotificationInboxItem> loadByIDFromServer({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
    required String inboxItemId,
  });

  Stream<NotificationReadCursorSnapshot> observeReadCursor({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
  });

  Future<void> markRead(
    String householdId,
    DateTime memberJoinedAt,
    NotificationReadCursor cursor,
  );
}

final class NotificationProviderEvidenceSnapshot {
  const NotificationProviderEvidenceSnapshot({
    required this.evidence,
    required this.authority,
    required this.updatedAt,
    required this.attemptCount,
  });

  final NotificationProviderEvidence evidence;
  final NotificationObservationAuthority authority;
  final DateTime? updatedAt;
  final int attemptCount;
}

abstract interface class NotificationDeliveryEvidenceRepository {
  Stream<NotificationProviderEvidenceSnapshot> observe({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
    required String installationHash,
  });
}

abstract interface class NotificationInteractionRepository {
  Future<NotificationPendingRoute?> readPendingRoute();
  Future<NotificationPendingRoute> persistClick(Map<String, String> payload);
  Future<bool> compareAndSetPendingRoute({
    required NotificationPendingRoute expected,
    required NotificationPendingRoute next,
  });
  Future<void> clearPendingRoute();
  Future<bool> clearPendingRouteIfGeneration(int generation);
  Future<NotificationRouteResolution> resolve(NotificationRoutePayload payload);
}

enum NotificationCenterErrorCode {
  invalidInput,
  permission,
  stale,
  malformed,
  network,
  backendUnavailable,
}

final class NotificationCenterException implements Exception {
  const NotificationCenterException(this.code, {this.diagnosticCode});

  final NotificationCenterErrorCode code;
  final String? diagnosticCode;
}

final notificationPreferencesRepositoryProvider =
    Provider<NotificationPreferencesRepository>((ref) {
      throw StateError('NotificationPreferencesRepository must be provided.');
    });

final notificationInboxRepositoryProvider =
    Provider<NotificationInboxRepository>(
      (ref) =>
          throw StateError('NotificationInboxRepository must be provided.'),
    );

final notificationDeliveryEvidenceRepositoryProvider =
    Provider<NotificationDeliveryEvidenceRepository>(
      (ref) => throw StateError(
        'NotificationDeliveryEvidenceRepository must be provided.',
      ),
    );

final notificationInteractionRepositoryProvider =
    Provider<NotificationInteractionRepository>(
      (ref) => throw StateError(
        'NotificationInteractionRepository must be provided.',
      ),
    );

final class FakeNotificationPreferencesRepository
    implements NotificationPreferencesRepository {
  FakeNotificationPreferencesRepository(this.snapshot);

  NotificationPreferencesSnapshot snapshot;
  final _controllers = <StreamController<NotificationPreferencesSnapshot>>[];
  final savedPreferences = <HouseholdNotificationPreferences>[];
  final clientMutationIds = <String>[];
  final resetMutationIds = <String>[];
  Object? nextError;
  Object? nextResetError;

  void emitError(Object error) {
    for (final controller in _controllers) {
      controller.addError(error);
    }
  }

  @override
  Stream<NotificationPreferencesSnapshot> observe({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
    required String timeZoneIdentifier,
  }) {
    late final StreamController<NotificationPreferencesSnapshot> controller;
    controller = StreamController(
      onListen: () => controller.add(snapshot),
      onCancel: () => _controllers.remove(controller),
    );
    _controllers.add(controller);
    return controller.stream;
  }

  @override
  Future<NotificationPreferenceMutationResult> save(
    HouseholdNotificationPreferences preferences, {
    required String clientMutationId,
  }) async {
    savedPreferences.add(preferences);
    clientMutationIds.add(clientMutationId);
    if (nextError case final error?) {
      nextError = null;
      throw error;
    }
    final revision = preferences.revision + 1;
    snapshot = NotificationPreferencesSnapshot(
      preferences: HouseholdNotificationPreferences(
        uid: preferences.uid,
        householdId: preferences.householdId,
        memberJoinedAt: preferences.memberJoinedAt,
        medicationRemindersEnabled: preferences.medicationRemindersEnabled,
        assignmentAlertsEnabled: preferences.assignmentAlertsEnabled,
        urgentAlertsEnabled: preferences.urgentAlertsEnabled,
        pushEnabled: preferences.pushEnabled,
        backupForMemberIds: preferences.backupForMemberIds,
        quietHoursEnabled: preferences.quietHoursEnabled,
        quietStartMinute: preferences.quietStartMinute,
        quietEndMinute: preferences.quietEndMinute,
        summaryEnabled: preferences.summaryEnabled,
        summaryMinute: preferences.summaryMinute,
        timeZoneIdentifier: preferences.timeZoneIdentifier,
        revision: revision,
        createdAt: preferences.createdAt,
        updatedAt: preferences.updatedAt,
      ),
      authority: NotificationPreferenceAuthority.serverConfirmed,
    );
    for (final controller in _controllers) {
      controller.add(snapshot);
    }
    return NotificationPreferenceMutationResult(
      householdId: preferences.householdId,
      revision: revision,
      existing: false,
    );
  }

  @override
  Future<NotificationPreferenceMutationResult> resetMalformed({
    required String householdId,
    required String clientMutationId,
  }) async {
    resetMutationIds.add(clientMutationId);
    if (nextResetError case final error?) {
      nextResetError = null;
      throw error;
    }
    return NotificationPreferenceMutationResult(
      householdId: householdId,
      revision: 1,
      existing: false,
    );
  }

  @override
  Future<void> stop() async {
    for (final controller in List.of(_controllers)) {
      await controller.close();
    }
    _controllers.clear();
  }
}

final class FakeNotificationInboxRepository
    implements NotificationInboxRepository {
  FakeNotificationInboxRepository({this.items = const []});

  List<NotificationInboxItem> items;
  NotificationReadCursor? cursor;
  int directLoadCalls = 0;
  int markReadCalls = 0;
  final attemptedReadCursors = <NotificationReadCursor>[];
  Object? nextMarkReadError;

  @override
  Stream<NotificationInboxPage> observeRecent({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
  }) => Stream.fromFuture(
    loadRecent(
      householdId: householdId,
      memberId: memberId,
      memberJoinedAt: memberJoinedAt,
    ),
  );

  @override
  Future<NotificationInboxPage> loadRecent({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
    NotificationInboxPageCursor? after,
  }) async => NotificationInboxPage(
    items: List.unmodifiable(items.take(20)),
    droppedItemCount: 0,
    authority: NotificationObservationAuthority.serverConfirmed,
    hasPendingWrites: false,
    mayHaveMore: items.length > 20,
    nextCursor: items.length > 20
        ? const StoredNotificationPageCursor('fake-page')
        : null,
  );

  @override
  Future<NotificationInboxItem> loadByIDFromServer({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
    required String inboxItemId,
  }) async {
    directLoadCalls += 1;
    return items.firstWhere((item) => item.id == inboxItemId);
  }

  @override
  Stream<NotificationReadCursorSnapshot> observeReadCursor({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
  }) => Stream.value(
    NotificationReadCursorSnapshot(
      cursor: cursor,
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
    attemptedReadCursors.add(cursor);
    if (nextMarkReadError case final error?) {
      nextMarkReadError = null;
      throw error;
    }
    this.cursor = cursor;
  }
}

final class FakeNotificationDeliveryEvidenceRepository
    implements NotificationDeliveryEvidenceRepository {
  FakeNotificationDeliveryEvidenceRepository(this.snapshot);

  NotificationProviderEvidenceSnapshot snapshot;

  @override
  Stream<NotificationProviderEvidenceSnapshot> observe({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
    required String installationHash,
  }) => Stream.value(snapshot);
}

final class FakeNotificationInteractionRepository
    implements NotificationInteractionRepository {
  NotificationPendingRoute? pendingRoute;
  NotificationRouteResolution? nextResolution;
  Object? nextError;
  Future<void> Function()? beforeConditionalClear;

  @override
  Future<void> clearPendingRoute() async => pendingRoute = null;

  @override
  Future<bool> clearPendingRouteIfGeneration(int generation) async {
    await beforeConditionalClear?.call();
    if (pendingRoute?.generation != generation) return false;
    pendingRoute = null;
    return true;
  }

  @override
  Future<NotificationPendingRoute?> readPendingRoute() async => pendingRoute;

  @override
  Future<NotificationPendingRoute> persistClick(
    Map<String, String> payload,
  ) async {
    final currentGeneration = pendingRoute?.generation ?? 0;
    pendingRoute = NotificationPendingRoute(
      payload: NotificationRoutePayload(
        householdId: payload['householdID']!,
        inboxItemId: payload['inboxItemID']!,
      ),
      state: NotificationPendingRouteState.waitingForSession,
      generation: currentGeneration + 1,
    );
    return pendingRoute!;
  }

  @override
  Future<NotificationRouteResolution> resolve(
    NotificationRoutePayload payload,
  ) async {
    if (nextError case final error?) throw error;
    return nextResolution ??
        NotificationRouteResolution(
          disposition: NotificationRouteDisposition.open,
          householdId: payload.householdId,
          inboxItemId: payload.inboxItemId,
          serverCheckedAt: DateTime.now().toUtc(),
          category: NotificationInboxCategory.assignment,
          level: NotificationInboxLevel.directAssignment,
        );
  }

  @override
  Future<bool> compareAndSetPendingRoute({
    required NotificationPendingRoute expected,
    required NotificationPendingRoute next,
  }) async {
    if (!_samePendingRoute(pendingRoute, expected)) return false;
    pendingRoute = next;
    return true;
  }
}

bool _samePendingRoute(
  NotificationPendingRoute? left,
  NotificationPendingRoute right,
) =>
    left?.generation == right.generation &&
    left?.state == right.state &&
    left?.payload.householdId == right.payload.householdId &&
    left?.payload.inboxItemId == right.payload.inboxItemId;
