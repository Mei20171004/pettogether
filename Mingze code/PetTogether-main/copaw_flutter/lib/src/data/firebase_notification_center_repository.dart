// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/notification_models.dart';
import 'notification_center_gateway.dart';
import 'notification_center_repository.dart';

final class FirebaseNotificationPreferencesRepository
    implements NotificationPreferencesRepository {
  FirebaseNotificationPreferencesRepository({
    required NotificationCenterGateway gateway,
  }) : _gateway = gateway;

  final NotificationCenterGateway _gateway;

  @override
  Stream<NotificationPreferencesSnapshot> observe({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
    required String timeZoneIdentifier,
  }) {
    _identity(householdId, memberId);
    return _gateway.observePreferences(householdId).map((document) {
      if (document == null || !document.exists) {
        return NotificationPreferencesSnapshot(
          preferences: null,
          authority: document?.hasPendingWrites == true
              ? NotificationPreferenceAuthority.pendingWrite
              : document?.isFromCache == true
              ? NotificationPreferenceAuthority.cached
              : NotificationPreferenceAuthority.missingDefaults,
        );
      }
      try {
        final preferences = _decodePreferences(
          document,
          memberId,
          memberJoinedAt,
          timeZoneIdentifier,
        );
        final authority = document.hasPendingWrites
            ? NotificationPreferenceAuthority.pendingWrite
            : document.isFromCache
            ? NotificationPreferenceAuthority.cached
            : NotificationPreferenceAuthority.serverConfirmed;
        return NotificationPreferencesSnapshot(
          preferences: preferences,
          authority: authority,
        );
      } on FormatException {
        return const NotificationPreferencesSnapshot(
          preferences: null,
          authority: NotificationPreferenceAuthority.malformed,
        );
      }
    });
  }

  @override
  Future<NotificationPreferenceMutationResult> save(
    HouseholdNotificationPreferences preferences, {
    required String clientMutationId,
  }) async {
    _identity(preferences.householdId, preferences.uid);
    _mutationId(clientMutationId);
    final backup = [...preferences.backupForMemberIds]..sort();
    if (backup.toSet().length != backup.length ||
        backup.length > 20 ||
        backup.contains(preferences.uid)) {
      throw const NotificationCenterException(
        NotificationCenterErrorCode.invalidInput,
      );
    }
    final data = await _gateway.call('setHouseholdNotificationPreferences', {
      'householdID': preferences.householdId,
      'expectedRevision': preferences.revision,
      'clientMutationID': clientMutationId,
      'medicationRemindersEnabled': preferences.medicationRemindersEnabled,
      'assignmentAlertsEnabled': preferences.assignmentAlertsEnabled,
      'urgentAlertsEnabled': preferences.urgentAlertsEnabled,
      'pushEnabled': preferences.pushEnabled,
      'backupForMemberIDs': backup,
      'quietHoursEnabled': preferences.quietHoursEnabled,
      'quietStartMinute': preferences.quietStartMinute,
      'quietEndMinute': preferences.quietEndMinute,
      'summaryEnabled': preferences.summaryEnabled,
      'summaryMinute': preferences.summaryMinute,
    });
    return _decodeMutationResult(data, preferences.householdId);
  }

  @override
  Future<NotificationPreferenceMutationResult> resetMalformed({
    required String householdId,
    required String clientMutationId,
  }) async {
    _id(householdId);
    _mutationId(clientMutationId);
    return _decodeMutationResult(
      await _gateway.call('resetMalformedNotificationPreferences', {
        'householdID': householdId,
        'clientMutationID': clientMutationId,
      }),
      householdId,
    );
  }

  @override
  Future<void> stop() async {}
}

final class FirebaseNotificationInboxRepository
    implements NotificationInboxRepository {
  FirebaseNotificationInboxRepository({
    required NotificationCenterGateway gateway,
  }) : _gateway = gateway;

  final NotificationCenterGateway _gateway;

  @override
  Stream<NotificationInboxPage> observeRecent({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
  }) {
    _identity(householdId, memberId);
    return _gateway
        .observeInboxRecent(
          householdId: householdId,
          memberJoinedAt: memberJoinedAt,
          rawLimit: 21,
        )
        .map(
          (query) => _decodeInboxPage(
            query.documents,
            householdId: householdId,
            memberId: memberId,
            memberJoinedAt: memberJoinedAt,
            isFromCache: query.isFromCache,
            hasPendingWrites: query.hasPendingWrites,
          ),
        );
  }

  @override
  Future<NotificationInboxPage> loadRecent({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
    NotificationInboxPageCursor? after,
  }) async {
    _identity(householdId, memberId);
    final raw = await _gateway.loadInbox(
      householdId: householdId,
      memberJoinedAt: memberJoinedAt,
      rawLimit: 21,
      after: after,
    );
    return _decodeInboxPage(
      raw,
      householdId: householdId,
      memberId: memberId,
      memberJoinedAt: memberJoinedAt,
      isFromCache: raw.any((document) => document.isFromCache),
      hasPendingWrites: raw.any((document) => document.hasPendingWrites),
    );
  }

  NotificationInboxPage _decodeInboxPage(
    List<StoredNotificationDocument> raw, {
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
    required bool isFromCache,
    required bool hasPendingWrites,
  }) {
    final exposed = raw.take(20).toList(growable: false);
    final items = <NotificationInboxItem>[];
    var dropped = 0;
    for (final document in exposed) {
      try {
        items.add(
          _decodeInbox(
            document,
            householdId: householdId,
            memberId: memberId,
            memberJoinedAt: memberJoinedAt,
          ),
        );
      } on FormatException {
        dropped += 1;
      }
    }
    return NotificationInboxPage(
      items: List.unmodifiable(items),
      droppedItemCount: dropped,
      authority: isFromCache
          ? NotificationObservationAuthority.cached
          : NotificationObservationAuthority.serverConfirmed,
      hasPendingWrites: hasPendingWrites,
      mayHaveMore: raw.length == 21,
      nextCursor: raw.length == 21 && exposed.isNotEmpty
          ? exposed.last.cursor ?? StoredNotificationPageCursor(exposed.last.id)
          : null,
    );
  }

  @override
  Future<NotificationInboxItem> loadByIDFromServer({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
    required String inboxItemId,
  }) async {
    _identity(householdId, memberId);
    _intentId(inboxItemId);
    final document = await _gateway.loadInboxByIdFromServer(inboxItemId);
    if (document == null) {
      throw const NotificationCenterException(
        NotificationCenterErrorCode.invalidInput,
        diagnosticCode: 'missing',
      );
    }
    if (document.isFromCache) {
      throw const NotificationCenterException(
        NotificationCenterErrorCode.network,
      );
    }
    try {
      return _decodeInbox(
        document,
        householdId: householdId,
        memberId: memberId,
        memberJoinedAt: memberJoinedAt,
      );
    } on FormatException {
      throw const NotificationCenterException(
        NotificationCenterErrorCode.malformed,
      );
    }
  }

  @override
  Stream<NotificationReadCursorSnapshot> observeReadCursor({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
  }) {
    _identity(householdId, memberId);
    return _gateway.observeReadCursor(householdId).map((document) {
      if (document == null || !document.exists) {
        return NotificationReadCursorSnapshot(
          cursor: null,
          authority: document?.hasPendingWrites == true
              ? NotificationCursorAuthority.pending
              : document?.isFromCache == true
              ? NotificationCursorAuthority.cached
              : NotificationCursorAuthority.serverConfirmed,
        );
      }
      try {
        final data = document.data;
        const keys = {
          'schemaVersion',
          'householdID',
          'recipientJoinedAtSnapshot',
          'createdAt',
          'intentID',
          'updatedAt',
        };
        final createdAt = _date(data['createdAt']);
        final joinedAt = _date(data['recipientJoinedAtSnapshot']);
        if (!_exactKeys(data, keys) ||
            data['schemaVersion'] != 1 ||
            data['householdID'] != householdId ||
            joinedAt == null ||
            !joinedAt.isAtSameMomentAs(memberJoinedAt) ||
            createdAt == null ||
            !_isIntentId(data['intentID']) ||
            (_date(data['updatedAt']) == null && !document.hasPendingWrites)) {
          throw const FormatException();
        }
        return NotificationReadCursorSnapshot(
          cursor: NotificationReadCursor(
            createdAt: createdAt,
            intentId: data['intentID']! as String,
          ),
          authority: document.hasPendingWrites
              ? NotificationCursorAuthority.pending
              : document.isFromCache
              ? NotificationCursorAuthority.cached
              : NotificationCursorAuthority.serverConfirmed,
        );
      } on FormatException {
        return const NotificationReadCursorSnapshot(
          cursor: null,
          authority: NotificationCursorAuthority.malformed,
        );
      }
    });
  }

  @override
  Future<void> markRead(
    String householdId,
    DateTime memberJoinedAt,
    NotificationReadCursor cursor,
  ) async {
    _id(householdId);
    _intentId(cursor.intentId);
    await _gateway.writeReadCursor(householdId, memberJoinedAt, cursor);
  }
}

final class FirebaseNotificationDeliveryEvidenceRepository
    implements NotificationDeliveryEvidenceRepository {
  FirebaseNotificationDeliveryEvidenceRepository({
    required NotificationCenterGateway gateway,
  }) : _gateway = gateway;

  final NotificationCenterGateway _gateway;

  @override
  Stream<NotificationProviderEvidenceSnapshot> observe({
    required String householdId,
    required String memberId,
    required DateTime memberJoinedAt,
    required String installationHash,
  }) {
    _id(householdId);
    _intentId(installationHash);
    return _gateway
        .observeDeliveryEvidence(
          householdId: householdId,
          memberJoinedAt: memberJoinedAt,
          installationHash: installationHash,
        )
        .map((query) {
          final authority = query.isFromCache
              ? NotificationObservationAuthority.cached
              : NotificationObservationAuthority.serverConfirmed;
          if (query.documents.isEmpty) {
            return NotificationProviderEvidenceSnapshot(
              evidence: NotificationProviderEvidence
                  .notVerifiedForCurrentInstallation,
              authority: authority,
              updatedAt: null,
              attemptCount: 0,
            );
          }
          if (query.documents.length != 1) {
            throw const NotificationCenterException(
              NotificationCenterErrorCode.malformed,
            );
          }
          final decoded = _decodeDelivery(
            query.documents.single,
            householdId: householdId,
            memberId: memberId,
            memberJoinedAt: memberJoinedAt,
            installationHash: installationHash,
          );
          return NotificationProviderEvidenceSnapshot(
            evidence: decoded.evidence,
            authority: authority,
            updatedAt: decoded.updatedAt,
            attemptCount: decoded.attemptCount,
          );
        });
  }
}

HouseholdNotificationPreferences _decodePreferences(
  StoredNotificationDocument document,
  String memberId,
  DateTime memberJoinedAt,
  String timeZoneIdentifier,
) {
  final data = document.data;
  const keys = {
    'schemaVersion',
    'uid',
    'householdID',
    'memberJoinedAtSnapshot',
    'medicationRemindersEnabled',
    'assignmentAlertsEnabled',
    'urgentAlertsEnabled',
    'pushEnabled',
    'backupForMemberIDs',
    'quietHoursEnabled',
    'quietStartMinute',
    'quietEndMinute',
    'summaryEnabled',
    'summaryMinute',
    'timeZoneIdentifierSnapshot',
    'revision',
    'createdAt',
    'updatedAt',
  };
  final backup = data['backupForMemberIDs'];
  final joinedAt = _date(data['memberJoinedAtSnapshot']);
  final createdAt = _date(data['createdAt']);
  final updatedAt = _date(data['updatedAt']);
  if (!_exactKeys(data, keys) ||
      data['schemaVersion'] != 1 ||
      data['uid'] != memberId ||
      document.id != data['householdID'] ||
      !_isId(data['householdID']) ||
      joinedAt == null ||
      !joinedAt.isAtSameMomentAs(memberJoinedAt) ||
      data['medicationRemindersEnabled'] is! bool ||
      data['assignmentAlertsEnabled'] is! bool ||
      data['urgentAlertsEnabled'] is! bool ||
      data['pushEnabled'] is! bool ||
      backup is! List ||
      backup.any((value) => !_isId(value) || value == memberId) ||
      backup.cast<Object?>().toSet().length != backup.length ||
      !_sortedStrings(backup) ||
      backup.length > 20 ||
      data['quietHoursEnabled'] is! bool ||
      !_minute(data['quietStartMinute']) ||
      !_minute(data['quietEndMinute']) ||
      (data['quietHoursEnabled'] == true &&
          data['quietStartMinute'] == data['quietEndMinute']) ||
      data['summaryEnabled'] is! bool ||
      !_minute(data['summaryMinute']) ||
      !_isText(data['timeZoneIdentifierSnapshot'], 100) ||
      data['timeZoneIdentifierSnapshot'] != timeZoneIdentifier ||
      data['revision'] is! int ||
      (data['revision']! as int) <= 0 ||
      createdAt == null ||
      updatedAt == null ||
      updatedAt.isBefore(createdAt)) {
    throw const FormatException('Malformed notification preferences');
  }
  return HouseholdNotificationPreferences(
    uid: memberId,
    householdId: data['householdID']! as String,
    memberJoinedAt: joinedAt,
    medicationRemindersEnabled: data['medicationRemindersEnabled']! as bool,
    assignmentAlertsEnabled: data['assignmentAlertsEnabled']! as bool,
    urgentAlertsEnabled: data['urgentAlertsEnabled']! as bool,
    pushEnabled: data['pushEnabled']! as bool,
    backupForMemberIds: List.unmodifiable(backup.cast<String>()),
    quietHoursEnabled: data['quietHoursEnabled']! as bool,
    quietStartMinute: data['quietStartMinute']! as int,
    quietEndMinute: data['quietEndMinute']! as int,
    summaryEnabled: data['summaryEnabled']! as bool,
    summaryMinute: data['summaryMinute']! as int,
    timeZoneIdentifier: data['timeZoneIdentifierSnapshot']! as String,
    revision: data['revision']! as int,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

NotificationInboxItem _decodeInbox(
  StoredNotificationDocument document, {
  required String householdId,
  required String memberId,
  required DateTime memberJoinedAt,
}) {
  final data = document.data;
  const keys = {
    'schemaVersion',
    'id',
    'householdID',
    'recipientID',
    'recipientJoinedAtSnapshot',
    'category',
    'level',
    'routeReason',
    'sourceType',
    'sourceID',
    'sourcePath',
    'sourceRevision',
    'preferenceRevision',
    'status',
    'availableAt',
    'expiresAt',
    'nextDispatchAt',
    'coalescingKey',
    'cancelReason',
    'cancelledAt',
    'createdAt',
    'updatedAt',
  };
  final joinedAt = _date(data['recipientJoinedAtSnapshot']);
  final category = _enum(NotificationInboxCategory.values, data['category']);
  final level = _enum(NotificationInboxLevel.values, data['level']);
  final reason = _enum(NotificationRouteReason.values, data['routeReason']);
  final source = _enum(NotificationSourceType.values, data['sourceType']);
  final status = _enum(NotificationInboxStatus.values, data['status']);
  final cancelReason = data['cancelReason'] == null
      ? null
      : _enum(NotificationCancelReason.values, data['cancelReason']);
  final availableAt = _date(data['availableAt']);
  final expiresAt = _date(data['expiresAt']);
  final nextDispatchAt = _nullableDate(data['nextDispatchAt']);
  final cancelledAt = _nullableDate(data['cancelledAt']);
  final createdAt = _date(data['createdAt']);
  final updatedAt = _date(data['updatedAt']);
  if (!_exactKeys(data, keys) ||
      data['schemaVersion'] != 1 ||
      !_isIntentId(document.id) ||
      data['id'] != document.id ||
      data['householdID'] != householdId ||
      data['recipientID'] != memberId ||
      joinedAt == null ||
      !joinedAt.isAtSameMomentAs(memberJoinedAt) ||
      category == null ||
      level == null ||
      reason == null ||
      source == null ||
      !_validInboxUnion(
        category: category,
        level: level,
        reason: reason,
        source: source,
      ) ||
      !_isId(data['sourceID']) ||
      data['sourcePath'] !=
          '${_sourceCollection(source)}/${data['sourceID']}' ||
      data['sourceRevision'] is! int ||
      (data['sourceRevision']! as int) < 0 ||
      (data['preferenceRevision'] != null &&
          (data['preferenceRevision'] is! int ||
              (data['preferenceRevision']! as int) <= 0)) ||
      status == null ||
      availableAt == null ||
      expiresAt == null ||
      !availableAt.isBefore(expiresAt) ||
      (data['nextDispatchAt'] != null && nextDispatchAt == null) ||
      (data['coalescingKey'] != null && !_isIntentId(data['coalescingKey'])) ||
      !_validInboxDispatchUnion(
        source: source,
        category: category,
        reason: reason,
        sourceId: data['sourceID'],
        sourceRevision: data['sourceRevision'],
        preferenceRevision: data['preferenceRevision'],
        status: status,
        availableAt: availableAt,
        nextDispatchAt: nextDispatchAt,
        coalescingKey: data['coalescingKey'],
      ) ||
      (data['cancelReason'] != null && cancelReason == null) ||
      (data['cancelledAt'] != null && cancelledAt == null) ||
      (status == NotificationInboxStatus.active &&
          (cancelReason != null || cancelledAt != null)) ||
      (status == NotificationInboxStatus.cancelled &&
          (cancelReason == null || cancelledAt == null)) ||
      createdAt == null ||
      updatedAt == null ||
      updatedAt.isBefore(createdAt)) {
    throw const FormatException('Malformed notification inbox item');
  }
  return NotificationInboxItem(
    id: document.id,
    householdId: householdId,
    recipientId: memberId,
    recipientJoinedAt: joinedAt,
    category: category,
    level: level,
    routeReason: reason,
    sourceType: source,
    sourceId: data['sourceID']! as String,
    sourcePath: data['sourcePath']! as String,
    sourceRevision: data['sourceRevision']! as int,
    preferenceRevision: data['preferenceRevision'] as int?,
    status: status,
    availableAt: availableAt,
    expiresAt: expiresAt,
    nextDispatchAt: nextDispatchAt,
    coalescingKey: data['coalescingKey'] as String?,
    cancelReason: cancelReason,
    cancelledAt: cancelledAt,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

bool _validInboxUnion({
  required NotificationInboxCategory category,
  required NotificationInboxLevel level,
  required NotificationRouteReason reason,
  required NotificationSourceType source,
}) => switch (source) {
  NotificationSourceType.medicationOccurrence =>
    category == NotificationInboxCategory.medication &&
        const {
          NotificationInboxLevel.due,
          NotificationInboxLevel.overdue15,
          NotificationInboxLevel.overdue30,
        }.contains(level) &&
        const {
          NotificationRouteReason.responsible,
          NotificationRouteReason.backup,
          NotificationRouteReason.medicationOptIn,
        }.contains(reason) &&
        !(level == NotificationInboxLevel.due &&
            reason == NotificationRouteReason.backup),
  NotificationSourceType.task =>
    (category == NotificationInboxCategory.assignment &&
            level == NotificationInboxLevel.directAssignment &&
            reason == NotificationRouteReason.directTarget) ||
        (category == NotificationInboxCategory.urgent &&
            level == NotificationInboxLevel.urgentUnclaimed &&
            reason == NotificationRouteReason.urgentOptIn),
  NotificationSourceType.taskResponsibilityTransfer =>
    category == NotificationInboxCategory.assignment &&
        level == NotificationInboxLevel.responsibilityProposal &&
        reason == NotificationRouteReason.directTarget,
  NotificationSourceType.handoffSession =>
    category == NotificationInboxCategory.assignment &&
        level == NotificationInboxLevel.handoffOffer &&
        reason == NotificationRouteReason.handoffRecipient,
  NotificationSourceType.notificationDigest =>
    category == NotificationInboxCategory.summary &&
        const {
          NotificationInboxLevel.burstSummary,
          NotificationInboxLevel.dailySummary,
        }.contains(level) &&
        reason == NotificationRouteReason.summary,
};

bool _validInboxDispatchUnion({
  required NotificationSourceType source,
  required NotificationInboxCategory category,
  required NotificationRouteReason reason,
  required Object? sourceId,
  required Object? sourceRevision,
  required Object? preferenceRevision,
  required NotificationInboxStatus? status,
  required DateTime availableAt,
  required DateTime? nextDispatchAt,
  required Object? coalescingKey,
}) {
  final hasPreference = preferenceRevision is int && preferenceRevision > 0;
  final needsPreference = const {
    NotificationRouteReason.backup,
    NotificationRouteReason.medicationOptIn,
    NotificationRouteReason.urgentOptIn,
    NotificationRouteReason.summary,
  }.contains(reason);
  if (needsPreference && !hasPreference) return false;
  if (status == NotificationInboxStatus.cancelled && nextDispatchAt != null) {
    return false;
  }
  if (source == NotificationSourceType.notificationDigest) {
    return hasPreference &&
        sourceRevision == 1 &&
        coalescingKey == sourceId &&
        (status == NotificationInboxStatus.cancelled ||
            (nextDispatchAt != null &&
                nextDispatchAt.isAtSameMomentAs(availableAt)));
  }
  if (category == NotificationInboxCategory.assignment) {
    return nextDispatchAt == null &&
        (hasPreference ? _isIntentId(coalescingKey) : coalescingKey == null);
  }
  if (coalescingKey != null) return false;
  if (!hasPreference) return nextDispatchAt == null;
  return status == NotificationInboxStatus.cancelled ||
      (nextDispatchAt != null && nextDispatchAt.isAtSameMomentAs(availableAt));
}

NotificationPreferenceMutationResult _decodeMutationResult(
  Map<String, Object?> data,
  String householdId,
) {
  const keys = {'householdID', 'revision', 'existing'};
  if (!_exactKeys(data, keys) ||
      data['householdID'] != householdId ||
      data['revision'] is! int ||
      (data['revision']! as int) <= 0 ||
      data['existing'] is! bool) {
    throw const NotificationCenterException(
      NotificationCenterErrorCode.malformed,
    );
  }
  return NotificationPreferenceMutationResult(
    householdId: householdId,
    revision: data['revision']! as int,
    existing: data['existing']! as bool,
  );
}

_DecodedDelivery _decodeDelivery(
  StoredNotificationDocument document, {
  required String householdId,
  required String memberId,
  required DateTime memberJoinedAt,
  required String installationHash,
}) {
  final data = document.data;
  const keys = {
    'schemaVersion',
    'id',
    'intentID',
    'householdID',
    'recipientID',
    'recipientJoinedAtSnapshot',
    'installationHash',
    'status',
    'attemptCount',
    'nextAttemptAt',
    'leaseID',
    'leaseExpiresAt',
    'providerRequestStartedAt',
    'providerAcceptedAt',
    'providerUnknownAt',
    'terminalAt',
    'safeErrorCode',
    'createdAt',
    'updatedAt',
  };
  final joinedAt = _date(data['recipientJoinedAtSnapshot']);
  final createdAt = _date(data['createdAt']);
  final updatedAt = _date(data['updatedAt']);
  final acceptedAt = _nullableDate(data['providerAcceptedAt']);
  final unknownAt = _nullableDate(data['providerUnknownAt']);
  final terminalAt = _nullableDate(data['terminalAt']);
  final nextAttemptAt = _nullableDate(data['nextAttemptAt']);
  final leaseExpiresAt = _nullableDate(data['leaseExpiresAt']);
  final requestStartedAt = _nullableDate(data['providerRequestStartedAt']);
  final status = data['status'];
  final attempts = data['attemptCount'];
  if (!_exactKeys(data, keys) ||
      data['schemaVersion'] != 2 ||
      !_isIntentId(document.id) ||
      data['id'] != document.id ||
      !_isIntentId(data['intentID']) ||
      data['householdID'] != householdId ||
      data['recipientID'] != memberId ||
      joinedAt == null ||
      !joinedAt.isAtSameMomentAs(memberJoinedAt) ||
      data['installationHash'] != installationHash ||
      attempts is! int ||
      attempts < 0 ||
      attempts > 3 ||
      status is! String ||
      !const {
        'queued',
        'attempting',
        'providerAccepted',
        'providerUnknown',
        'retryableFailure',
        'permanentFailure',
        'cancelled',
        'expired',
      }.contains(status) ||
      createdAt == null ||
      updatedAt == null ||
      updatedAt.isBefore(createdAt) ||
      (data['nextAttemptAt'] != null && nextAttemptAt == null) ||
      (data['leaseID'] != null && !_isId(data['leaseID'])) ||
      (data['leaseExpiresAt'] != null && leaseExpiresAt == null) ||
      (data['providerRequestStartedAt'] != null && requestStartedAt == null) ||
      (data['providerAcceptedAt'] != null && acceptedAt == null) ||
      (data['providerUnknownAt'] != null && unknownAt == null) ||
      (data['terminalAt'] != null && terminalAt == null) ||
      (data['safeErrorCode'] != null && data['safeErrorCode'] is! String) ||
      !_validDeliveryState(
        status: status,
        attempts: attempts,
        nextAttemptAt: nextAttemptAt,
        leaseId: data['leaseID'] as String?,
        leaseExpiresAt: leaseExpiresAt,
        requestStartedAt: requestStartedAt,
        acceptedAt: acceptedAt,
        unknownAt: unknownAt,
        terminalAt: terminalAt,
        safeErrorCode: data['safeErrorCode'] as String?,
      )) {
    throw const NotificationCenterException(
      NotificationCenterErrorCode.malformed,
    );
  }
  final evidence = switch (status) {
    'providerAccepted'
        when acceptedAt != null &&
            terminalAt != null &&
            acceptedAt.isAtSameMomentAs(terminalAt) =>
      NotificationProviderEvidence.providerAccepted,
    'providerUnknown' when unknownAt != null && terminalAt != null =>
      NotificationProviderEvidence.providerUnknown,
    'retryableFailure' || 'permanentFailure'
        when terminalAt != null || status == 'retryableFailure' =>
      NotificationProviderEvidence.definiteFailure,
    'queued' ||
    'attempting' ||
    'cancelled' ||
    'expired' => NotificationProviderEvidence.notVerifiedForCurrentInstallation,
    _ => throw const NotificationCenterException(
      NotificationCenterErrorCode.malformed,
    ),
  };
  return _DecodedDelivery(evidence, updatedAt, attempts);
}

bool _validDeliveryState({
  required String status,
  required int attempts,
  required DateTime? nextAttemptAt,
  required String? leaseId,
  required DateTime? leaseExpiresAt,
  required DateTime? requestStartedAt,
  required DateTime? acceptedAt,
  required DateTime? unknownAt,
  required DateTime? terminalAt,
  required String? safeErrorCode,
}) {
  final noLease = leaseId == null && leaseExpiresAt == null;
  final noResult = acceptedAt == null && unknownAt == null;
  return switch (status) {
    'queued' =>
      attempts <= 2 &&
          nextAttemptAt != null &&
          noLease &&
          requestStartedAt == null &&
          noResult &&
          terminalAt == null &&
          safeErrorCode == null,
    'attempting' =>
      attempts >= 1 &&
          leaseId != null &&
          leaseExpiresAt != null &&
          nextAttemptAt == null &&
          noResult &&
          terminalAt == null &&
          safeErrorCode == null,
    'retryableFailure' =>
      attempts >= 1 &&
          attempts <= 2 &&
          nextAttemptAt != null &&
          noLease &&
          requestStartedAt == null &&
          noResult &&
          terminalAt == null &&
          const {'providerRejected', 'leaseExpired'}.contains(safeErrorCode),
    'providerAccepted' =>
      attempts >= 1 &&
          nextAttemptAt == null &&
          noLease &&
          requestStartedAt == null &&
          acceptedAt != null &&
          unknownAt == null &&
          terminalAt != null &&
          acceptedAt.isAtSameMomentAs(terminalAt) &&
          safeErrorCode == null,
    'providerUnknown' =>
      attempts >= 1 &&
          nextAttemptAt == null &&
          noLease &&
          requestStartedAt == null &&
          acceptedAt == null &&
          unknownAt != null &&
          terminalAt != null &&
          unknownAt.isAtSameMomentAs(terminalAt) &&
          safeErrorCode == 'providerAmbiguous',
    'permanentFailure' =>
      attempts >= 1 &&
          nextAttemptAt == null &&
          noLease &&
          requestStartedAt == null &&
          noResult &&
          terminalAt != null &&
          const {'tokenInvalid', 'providerRejected'}.contains(safeErrorCode),
    'cancelled' =>
      nextAttemptAt == null &&
          noLease &&
          requestStartedAt == null &&
          noResult &&
          terminalAt != null &&
          const {
            'sourceTerminal',
            'policyChanged',
            'membershipEnded',
            'installationDisabled',
            'installationDuplicate',
          }.contains(safeErrorCode),
    'expired' =>
      nextAttemptAt == null &&
          noLease &&
          requestStartedAt == null &&
          noResult &&
          terminalAt != null &&
          safeErrorCode == null,
    _ => false,
  };
}

final class _DecodedDelivery {
  const _DecodedDelivery(this.evidence, this.updatedAt, this.attemptCount);

  final NotificationProviderEvidence evidence;
  final DateTime updatedAt;
  final int attemptCount;
}

T? _enum<T extends Enum>(List<T> values, Object? value) {
  if (value is! String) return null;
  for (final candidate in values) {
    if (candidate.name == value) return candidate;
  }
  return null;
}

String _sourceCollection(NotificationSourceType type) => switch (type) {
  NotificationSourceType.medicationOccurrence => 'medicationOccurrences',
  NotificationSourceType.task => 'tasks',
  NotificationSourceType.taskResponsibilityTransfer =>
    'taskResponsibilityTransfers',
  NotificationSourceType.handoffSession => 'handoffSessions',
  NotificationSourceType.notificationDigest => 'notificationDigests',
};

DateTime? _date(Object? value) => switch (value) {
  DateTime date => date.toUtc(),
  Timestamp timestamp => timestamp.toDate().toUtc(),
  _ => null,
};

DateTime? _nullableDate(Object? value) => value == null ? null : _date(value);

bool _exactKeys(Map<String, Object?> data, Set<String> keys) =>
    data.length == keys.length && data.keys.every(keys.contains);

bool _isId(Object? value) =>
    value is String &&
    value.isNotEmpty &&
    value.length <= 128 &&
    !value.contains('/');

bool _isText(Object? value, int max) =>
    value is String && value.isNotEmpty && value.length <= max;

bool _isIntentId(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

bool _minute(Object? value) => value is int && value >= 0 && value <= 1439;

bool _sortedStrings(List<Object?> values) {
  final strings = values.whereType<String>().toList(growable: false);
  if (strings.length != values.length) return false;
  for (var index = 1; index < strings.length; index += 1) {
    if (strings[index - 1].compareTo(strings[index]) >= 0) return false;
  }
  return true;
}

void _id(String value) {
  if (!_isId(value)) {
    throw const NotificationCenterException(
      NotificationCenterErrorCode.invalidInput,
    );
  }
}

void _identity(String householdId, String memberId) {
  _id(householdId);
  _id(memberId);
}

void _intentId(String value) {
  if (!_isIntentId(value)) {
    throw const NotificationCenterException(
      NotificationCenterErrorCode.invalidInput,
    );
  }
}

void _mutationId(String value) {
  if (!_isId(value)) {
    throw const NotificationCenterException(
      NotificationCenterErrorCode.invalidInput,
    );
  }
}
