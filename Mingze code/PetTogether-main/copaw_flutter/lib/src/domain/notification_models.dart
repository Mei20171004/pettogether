enum NotificationOsPermission {
  notDetermined,
  denied,
  authorized,
  provisional,
  unsupported,
  error,
}

enum NotificationPreferenceAuthority {
  missingDefaults,
  serverConfirmed,
  cached,
  pendingWrite,
  malformed,
  error,
}

enum NotificationInstallationReadiness {
  disabled,
  registering,
  ready,
  unavailable,
  unsupported,
  error,
}

enum NotificationProviderEvidence {
  notVerifiedForCurrentInstallation,
  providerAccepted,
  providerUnknown,
  definiteFailure,
}

enum NotificationObservationAuthority {
  loading,
  serverConfirmed,
  cached,
  error,
}

enum NotificationCursorAuthority {
  unknown,
  serverConfirmed,
  cached,
  pending,
  malformed,
  error,
}

final class NotificationCapability {
  const NotificationCapability({
    required this.osPermission,
    required this.preferenceAuthority,
    required this.installationReadiness,
    required this.providerEvidence,
    required this.providerAuthority,
  });

  final NotificationOsPermission osPermission;
  final NotificationPreferenceAuthority preferenceAuthority;
  final NotificationInstallationReadiness installationReadiness;
  final NotificationProviderEvidence providerEvidence;
  final NotificationObservationAuthority providerAuthority;

  bool get hasCurrentProviderEvidence =>
      providerAuthority == NotificationObservationAuthority.serverConfirmed &&
      providerEvidence !=
          NotificationProviderEvidence.notVerifiedForCurrentInstallation;
}

final class HouseholdNotificationPreferences {
  const HouseholdNotificationPreferences({
    required this.uid,
    required this.householdId,
    required this.memberJoinedAt,
    required this.medicationRemindersEnabled,
    required this.assignmentAlertsEnabled,
    required this.urgentAlertsEnabled,
    required this.pushEnabled,
    required this.backupForMemberIds,
    required this.quietHoursEnabled,
    required this.quietStartMinute,
    required this.quietEndMinute,
    required this.summaryEnabled,
    required this.summaryMinute,
    required this.timeZoneIdentifier,
    required this.revision,
    required this.createdAt,
    required this.updatedAt,
  });

  factory HouseholdNotificationPreferences.conservative({
    required String uid,
    required String householdId,
    required DateTime memberJoinedAt,
    required String timeZoneIdentifier,
  }) => HouseholdNotificationPreferences(
    uid: uid,
    householdId: householdId,
    memberJoinedAt: memberJoinedAt,
    medicationRemindersEnabled: false,
    assignmentAlertsEnabled: false,
    urgentAlertsEnabled: false,
    pushEnabled: false,
    backupForMemberIds: const [],
    quietHoursEnabled: false,
    quietStartMinute: 1320,
    quietEndMinute: 420,
    summaryEnabled: false,
    summaryMinute: 1080,
    timeZoneIdentifier: timeZoneIdentifier,
    revision: 0,
    createdAt: memberJoinedAt,
    updatedAt: memberJoinedAt,
  );

  final String uid;
  final String householdId;
  final DateTime memberJoinedAt;
  final bool medicationRemindersEnabled;
  final bool assignmentAlertsEnabled;
  final bool urgentAlertsEnabled;
  final bool pushEnabled;
  final List<String> backupForMemberIds;
  final bool quietHoursEnabled;
  final int quietStartMinute;
  final int quietEndMinute;
  final bool summaryEnabled;
  final int summaryMinute;
  final String timeZoneIdentifier;
  final int revision;
  final DateTime createdAt;
  final DateTime updatedAt;

  HouseholdNotificationPreferences copyWith({
    bool? medicationRemindersEnabled,
    bool? assignmentAlertsEnabled,
    bool? urgentAlertsEnabled,
    bool? pushEnabled,
    List<String>? backupForMemberIds,
    bool? quietHoursEnabled,
    int? quietStartMinute,
    int? quietEndMinute,
    bool? summaryEnabled,
    int? summaryMinute,
  }) => HouseholdNotificationPreferences(
    uid: uid,
    householdId: householdId,
    memberJoinedAt: memberJoinedAt,
    medicationRemindersEnabled:
        medicationRemindersEnabled ?? this.medicationRemindersEnabled,
    assignmentAlertsEnabled:
        assignmentAlertsEnabled ?? this.assignmentAlertsEnabled,
    urgentAlertsEnabled: urgentAlertsEnabled ?? this.urgentAlertsEnabled,
    pushEnabled: pushEnabled ?? this.pushEnabled,
    backupForMemberIds: List.unmodifiable(
      backupForMemberIds ?? this.backupForMemberIds,
    ),
    quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
    quietStartMinute: quietStartMinute ?? this.quietStartMinute,
    quietEndMinute: quietEndMinute ?? this.quietEndMinute,
    summaryEnabled: summaryEnabled ?? this.summaryEnabled,
    summaryMinute: summaryMinute ?? this.summaryMinute,
    timeZoneIdentifier: timeZoneIdentifier,
    revision: revision,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

enum NotificationInboxCategory { medication, assignment, urgent, summary }

enum NotificationInboxLevel {
  due,
  overdue15,
  overdue30,
  directAssignment,
  responsibilityProposal,
  handoffOffer,
  urgentUnclaimed,
  burstSummary,
  dailySummary,
}

enum NotificationRouteReason {
  responsible,
  backup,
  medicationOptIn,
  directTarget,
  handoffRecipient,
  urgentOptIn,
  summary,
}

enum NotificationSourceType {
  medicationOccurrence,
  task,
  taskResponsibilityTransfer,
  handoffSession,
  notificationDigest,
}

enum NotificationInboxStatus { active, cancelled }

enum NotificationCancelReason {
  sourceTerminal,
  sourceChanged,
  membershipEnded,
  policyChanged,
  expired,
}

final class NotificationInboxItem {
  const NotificationInboxItem({
    required this.id,
    required this.householdId,
    required this.recipientId,
    required this.recipientJoinedAt,
    required this.category,
    required this.level,
    required this.routeReason,
    required this.sourceType,
    required this.sourceId,
    required this.sourcePath,
    required this.sourceRevision,
    required this.preferenceRevision,
    required this.status,
    required this.availableAt,
    required this.expiresAt,
    required this.createdAt,
    required this.updatedAt,
    this.nextDispatchAt,
    this.coalescingKey,
    this.cancelReason,
    this.cancelledAt,
  });

  final String id;
  final String householdId;
  final String recipientId;
  final DateTime recipientJoinedAt;
  final NotificationInboxCategory category;
  final NotificationInboxLevel level;
  final NotificationRouteReason routeReason;
  final NotificationSourceType sourceType;
  final String sourceId;
  final String sourcePath;
  final int sourceRevision;
  final int? preferenceRevision;
  final NotificationInboxStatus status;
  final DateTime availableAt;
  final DateTime expiresAt;
  final DateTime? nextDispatchAt;
  final String? coalescingKey;
  final NotificationCancelReason? cancelReason;
  final DateTime? cancelledAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  NotificationInboxItem copyWith({
    String? id,
    NotificationInboxStatus? status,
  }) => NotificationInboxItem(
    id: id ?? this.id,
    householdId: householdId,
    recipientId: recipientId,
    recipientJoinedAt: recipientJoinedAt,
    category: category,
    level: level,
    routeReason: routeReason,
    sourceType: sourceType,
    sourceId: sourceId,
    sourcePath: sourcePath,
    sourceRevision: sourceRevision,
    preferenceRevision: preferenceRevision,
    status: status ?? this.status,
    availableAt: availableAt,
    expiresAt: expiresAt,
    nextDispatchAt: nextDispatchAt,
    coalescingKey: coalescingKey,
    cancelReason: cancelReason,
    cancelledAt: cancelledAt,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

final class NotificationReadCursor {
  const NotificationReadCursor({
    required this.createdAt,
    required this.intentId,
  });

  final DateTime createdAt;
  final String intentId;

  static int compare(
    NotificationReadCursor left,
    NotificationReadCursor right,
  ) {
    final time = left.createdAt.compareTo(right.createdAt);
    return time != 0 ? time : left.intentId.compareTo(right.intentId);
  }
}

abstract final class NotificationUnreadPolicy {
  static bool hasUnread({
    required List<NotificationInboxItem> items,
    required int droppedItemCount,
    required NotificationReadCursor? cursor,
    required NotificationCursorAuthority cursorAuthority,
    required NotificationObservationAuthority pageAuthority,
    required bool previousValue,
  }) {
    if (pageAuthority == NotificationObservationAuthority.loading ||
        pageAuthority == NotificationObservationAuthority.error) {
      if (items.isEmpty && droppedItemCount == 0) return previousValue;
    }
    if (droppedItemCount > 0) return true;
    final active = items.where(
      (item) => item.status == NotificationInboxStatus.active,
    );
    if (active.isEmpty) return false;
    if (cursorAuthority != NotificationCursorAuthority.serverConfirmed ||
        cursor == null) {
      return true;
    }
    return active.any(
      (item) =>
          NotificationReadCursor.compare(
            NotificationReadCursor(
              createdAt: item.createdAt,
              intentId: item.id,
            ),
            cursor,
          ) >
          0,
    );
  }
}

enum NotificationPendingRouteState { waitingForSession, resolving, retryable }

final class NotificationRoutePayload {
  const NotificationRoutePayload({
    required this.householdId,
    required this.inboxItemId,
  });

  final String householdId;
  final String inboxItemId;

  Map<String, String> toJson() => {
    'schemaVersion': '1',
    'destination': 'notificationInbox',
    'householdID': householdId,
    'inboxItemID': inboxItemId,
  };
}

final class NotificationPendingRoute {
  const NotificationPendingRoute({
    required this.payload,
    required this.state,
    required this.generation,
  });

  final NotificationRoutePayload payload;
  final NotificationPendingRouteState state;
  final int generation;

  NotificationPendingRoute copyWith({NotificationPendingRouteState? state}) =>
      NotificationPendingRoute(
        payload: payload,
        state: state ?? this.state,
        generation: generation,
      );

  NotificationPendingRoute normalizedForLaunch() => NotificationPendingRoute(
    payload: payload,
    state: state == NotificationPendingRouteState.resolving
        ? NotificationPendingRouteState.retryable
        : state,
    generation: generation,
  );
}

enum NotificationRouteDisposition { open, reject }

enum NotificationRouteRejectReason {
  missing,
  malformed,
  expired,
  cancelled,
  membershipEnded,
  sourceChanged,
  sourceUnavailable,
}

final class NotificationRouteResolution {
  const NotificationRouteResolution({
    required this.disposition,
    required this.householdId,
    required this.inboxItemId,
    required this.serverCheckedAt,
    this.category,
    this.level,
    this.rejectReason,
  });

  final NotificationRouteDisposition disposition;
  final String householdId;
  final String inboxItemId;
  final DateTime serverCheckedAt;
  final NotificationInboxCategory? category;
  final NotificationInboxLevel? level;
  final NotificationRouteRejectReason? rejectReason;
}
