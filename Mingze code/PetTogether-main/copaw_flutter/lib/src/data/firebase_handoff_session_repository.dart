import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../domain/handoff_models.dart';
import '../domain/time_zone_identifier.dart';
import 'firebase_handoff_session_gateway.dart';
import 'handoff_session_gateway.dart';
import 'handoff_session_repository.dart';

final class FirebaseHandoffSessionRepository
    implements HandoffSessionRepository {
  FirebaseHandoffSessionRepository({HandoffSessionGateway? gateway})
    : _gateway = gateway ?? FirebaseHandoffSessionGateway();

  static const _pointerKeys = {
    'schemaVersion',
    'sessionID',
    'sessionStatus',
    'plannedEndAt',
    'updatedAt',
  };
  static const _sessionKeys = {
    'schemaVersion',
    'id',
    'versionID',
    'handoffRevisionSnapshot',
    'creatorID',
    'creatorName',
    'recipientID',
    'recipientName',
    'timeZoneIdentifierSnapshot',
    'plannedStartAt',
    'plannedEndAt',
    'status',
    'offeredAt',
    'acceptedByID',
    'acceptedByName',
    'acceptedAt',
    'declinedByID',
    'declinedByName',
    'declinedAt',
    'cancelledByID',
    'cancelledByName',
    'cancelledAt',
    'closedByID',
    'closedByName',
    'closedAt',
    'resolutionReason',
    'revision',
  };
  static const _versionKeys = {
    'schemaVersion',
    'id',
    'sourceHandoffRevision',
    'careInstructions',
    'emergencyContactName',
    'emergencyContactPhone',
    'veterinaryHospitalName',
    'veterinaryHospitalPhone',
    'updatedByID',
    'updatedByName',
    'updatedAt',
    'materializedAt',
  };
  static const _responseKeys = {
    'sessionID',
    'sessionRevision',
    'sessionStatus',
    'activeSessionID',
    'versionID',
    'existing',
  };

  final HandoffSessionGateway _gateway;
  StreamSubscription<StoredHandoffSessionAuthority>? _subscription;
  StreamController<HandoffSessionSnapshot>? _controller;

  @override
  Stream<HandoffSessionSnapshot> observeActiveSession(String householdId) {
    if (!_id(householdId)) {
      return Stream.error(
        const HandoffSessionException(HandoffSessionErrorCode.invalidInput),
      );
    }
    final controller = StreamController<HandoffSessionSnapshot>();
    unawaited(_replaceObservation(householdId, controller));
    return controller.stream;
  }

  Future<void> _replaceObservation(
    String householdId,
    StreamController<HandoffSessionSnapshot> controller,
  ) async {
    await stopObserving();
    _controller = controller;
    _subscription = _gateway.observeAuthority(householdId).listen((authority) {
      final sessions = <String, HandoffSession>{};
      var dropped = 0;
      for (final document in authority.sessions) {
        try {
          sessions[document.id] = _decodeSession(document);
        } on FormatException {
          dropped += 1;
        }
      }
      final versions = <String, HandoffVersion>{};
      var droppedVersions = 0;
      for (final document in authority.versions) {
        try {
          versions[document.id] = _decodeVersion(document);
        } on FormatException {
          droppedVersions += 1;
        }
      }
      var malformed = false;
      HandoffSession? active;
      HandoffVersion? pinnedVersion;
      if (authority.pointerExists) {
        try {
          final pointer = _decodePointer(authority.pointerData);
          active = sessions[pointer.sessionId];
          if (active == null ||
              active.status.name != pointer.sessionStatus ||
              !active.plannedEndAt.isAtSameMomentAs(pointer.plannedEndAt)) {
            malformed = true;
            active = null;
          }
        } on FormatException {
          malformed = true;
        }
      }
      final activeDocuments = sessions.values
          .where(
            (session) =>
                session.status == HandoffSessionStatus.offered ||
                session.status == HandoffSessionStatus.accepted,
          )
          .toList(growable: false);
      if ((!authority.pointerExists && activeDocuments.isNotEmpty) ||
          activeDocuments.length > 1 ||
          (active != null && !activeDocuments.contains(active))) {
        malformed = true;
        active = null;
      }
      if (active != null) {
        pinnedVersion = versions[active.versionId];
        if (pinnedVersion == null ||
            pinnedVersion.sourceHandoffRevision !=
                active.handoffRevisionSnapshot) {
          malformed = true;
          pinnedVersion = null;
        }
      }
      controller.add(
        HandoffSessionSnapshot(
          activeSession: active,
          pinnedVersion: pinnedVersion,
          isFromCache: authority.isFromCache,
          droppedSessionCount: dropped,
          droppedVersionCount: droppedVersions,
          authorityMalformed: malformed,
        ),
      );
    }, onError: (Object error) => controller.addError(_mapped(error)));
  }

  @override
  Future<HandoffSessionMutationResult> offer({
    required String householdId,
    required String recipientId,
    required int expectedHandoffRevision,
    required DateTime plannedStart,
    required DateTime plannedEnd,
    required String clientMutationId,
  }) async {
    final start = plannedStart.toUtc();
    final end = plannedEnd.toUtc();
    if (!_id(householdId) ||
        !_id(recipientId) ||
        expectedHandoffRevision < 1 ||
        !_mutationId(clientMutationId) ||
        !start.isBefore(end) ||
        end.difference(start) > const Duration(days: 30)) {
      return _invalidResult();
    }
    return _mutate({
      'householdID': householdId,
      'action': 'offer',
      'recipientID': recipientId,
      'expectedHandoffRevision': expectedHandoffRevision,
      'plannedStartMilliseconds': start.millisecondsSinceEpoch,
      'plannedEndMilliseconds': end.millisecondsSinceEpoch,
      'clientMutationID': clientMutationId,
    });
  }

  @override
  Future<HandoffSessionMutationResult> transition({
    required String householdId,
    required String action,
    required String sessionId,
    required int expectedSessionRevision,
    required String clientMutationId,
  }) {
    if (!_id(householdId) ||
        !const {'accept', 'decline', 'cancel', 'close'}.contains(action) ||
        !_id(sessionId) ||
        expectedSessionRevision < 1 ||
        !_mutationId(clientMutationId)) {
      return _invalidResult();
    }
    return _mutate({
      'householdID': householdId,
      'action': action,
      'sessionID': sessionId,
      'expectedSessionRevision': expectedSessionRevision,
      'clientMutationID': clientMutationId,
    });
  }

  Future<HandoffSessionMutationResult> _mutate(
    Map<String, Object?> payload,
  ) async {
    try {
      return _decodeResponse(await _gateway.mutate(payload));
    } on Object catch (error) {
      throw _mapped(error);
    }
  }

  static Future<HandoffSessionMutationResult> _invalidResult() => Future.error(
    const HandoffSessionException(HandoffSessionErrorCode.invalidInput),
  );

  @override
  Future<void> stopObserving() async {
    final subscription = _subscription;
    final controller = _controller;
    _subscription = null;
    _controller = null;
    await subscription?.cancel();
    await controller?.close();
  }

  static _ActiveHandoffPointer _decodePointer(Map<String, Object?> data) {
    final end = data['plannedEndAt'];
    final updatedAt = data['updatedAt'];
    if (data.length != _pointerKeys.length ||
        !data.keys.every(_pointerKeys.contains) ||
        data['schemaVersion'] != 1 ||
        !_id(data['sessionID']) ||
        !const {'offered', 'accepted'}.contains(data['sessionStatus']) ||
        end is! Timestamp ||
        updatedAt is! Timestamp) {
      throw const FormatException('Malformed handoff session pointer');
    }
    return _ActiveHandoffPointer(
      sessionId: data['sessionID']! as String,
      sessionStatus: data['sessionStatus']! as String,
      plannedEndAt: end.toDate(),
    );
  }

  static HandoffSession _decodeSession(StoredHandoffSessionDocument document) {
    final data = document.data;
    final status = _enumByName(HandoffSessionStatus.values, data['status']);
    final reason = data['resolutionReason'] == null
        ? null
        : _enumByName(HandoffResolutionReason.values, data['resolutionReason']);
    final start = data['plannedStartAt'];
    final end = data['plannedEndAt'];
    final offeredAt = data['offeredAt'];
    final acceptedAt = data['acceptedAt'];
    final declinedAt = data['declinedAt'];
    final cancelledAt = data['cancelledAt'];
    final closedAt = data['closedAt'];
    final accepted = _transition(
      data['acceptedByID'],
      data['acceptedByName'],
      acceptedAt,
    );
    final declined = _transition(
      data['declinedByID'],
      data['declinedByName'],
      declinedAt,
    );
    final cancelled = _transition(
      data['cancelledByID'],
      data['cancelledByName'],
      cancelledAt,
    );
    final closed = _transition(
      data['closedByID'],
      data['closedByName'],
      closedAt,
    );
    if (data.length != _sessionKeys.length ||
        !data.keys.every(_sessionKeys.contains) ||
        data['schemaVersion'] != 1 ||
        data['id'] != document.id ||
        !_id(document.id) ||
        !_versionId(data['versionID']) ||
        data['handoffRevisionSnapshot'] is! int ||
        (data['handoffRevisionSnapshot'] as int) < 1 ||
        !_memberPair(data['creatorID'], data['creatorName']) ||
        !_memberPair(data['recipientID'], data['recipientName']) ||
        data['creatorID'] == data['recipientID'] ||
        data['timeZoneIdentifierSnapshot'] is! String ||
        !isPlausibleTimeZoneIdentifier(
          data['timeZoneIdentifierSnapshot']! as String,
        ) ||
        start is! Timestamp ||
        end is! Timestamp ||
        !start.toDate().isBefore(end.toDate()) ||
        end.toDate().difference(start.toDate()) > const Duration(days: 30) ||
        status == null ||
        offeredAt is! Timestamp ||
        (reason == null && data['resolutionReason'] != null) ||
        !_validTransitions(
          status,
          accepted,
          declined,
          cancelled,
          closed,
          data['revision'],
        ) ||
        !_validTransitionAuthority(data, status, reason)) {
      throw const FormatException('Malformed handoff session');
    }
    return HandoffSession(
      id: document.id,
      versionId: data['versionID']! as String,
      handoffRevisionSnapshot: data['handoffRevisionSnapshot']! as int,
      creatorId: data['creatorID']! as String,
      creatorNameSnapshot: data['creatorName']! as String,
      recipientId: data['recipientID']! as String,
      recipientNameSnapshot: data['recipientName']! as String,
      timeZoneIdentifierSnapshot: data['timeZoneIdentifierSnapshot']! as String,
      plannedStartAt: start.toDate(),
      plannedEndAt: end.toDate(),
      status: status,
      offeredAt: offeredAt.toDate(),
      acceptedById: data['acceptedByID'] as String?,
      acceptedByNameSnapshot: data['acceptedByName'] as String?,
      acceptedAt: (acceptedAt as Timestamp?)?.toDate(),
      declinedById: data['declinedByID'] as String?,
      declinedByNameSnapshot: data['declinedByName'] as String?,
      declinedAt: (declinedAt as Timestamp?)?.toDate(),
      cancelledById: data['cancelledByID'] as String?,
      cancelledByNameSnapshot: data['cancelledByName'] as String?,
      cancelledAt: (cancelledAt as Timestamp?)?.toDate(),
      closedById: data['closedByID'] as String?,
      closedByNameSnapshot: data['closedByName'] as String?,
      closedAt: (closedAt as Timestamp?)?.toDate(),
      resolutionReason: reason,
      revision: data['revision']! as int,
    );
  }

  static HandoffVersion _decodeVersion(StoredHandoffVersionDocument document) {
    final data = document.data;
    final sourceRevision = data['sourceHandoffRevision'];
    final care = data['careInstructions'];
    final contactName = data['emergencyContactName'];
    final contactPhone = data['emergencyContactPhone'];
    final hospitalName = data['veterinaryHospitalName'];
    final hospitalPhone = data['veterinaryHospitalPhone'];
    final updatedAt = data['updatedAt'];
    final materializedAt = data['materializedAt'];
    if (data.length != _versionKeys.length ||
        !data.keys.every(_versionKeys.contains) ||
        data['schemaVersion'] != 1 ||
        data['id'] != document.id ||
        !_versionId(document.id) ||
        sourceRevision is! int ||
        sourceRevision < 1 ||
        sourceRevision > 999999 ||
        document.id != 'v${sourceRevision.toString().padLeft(6, '0')}' ||
        !_boundedText(care, 1000) ||
        !_boundedText(contactName, 80) ||
        !_boundedText(contactPhone, 40) ||
        !_boundedText(hospitalName, 100) ||
        !_boundedText(hospitalPhone, 40) ||
        !_memberPair(data['updatedByID'], data['updatedByName']) ||
        updatedAt is! Timestamp ||
        materializedAt is! Timestamp) {
      throw const FormatException('Malformed handoff version');
    }
    return HandoffVersion(
      id: document.id,
      sourceHandoffRevision: sourceRevision,
      careInstructions: care! as String,
      emergencyContactName: contactName! as String,
      emergencyContactPhone: contactPhone! as String,
      veterinaryHospitalName: hospitalName! as String,
      veterinaryHospitalPhone: hospitalPhone! as String,
      updatedById: data['updatedByID']! as String,
      updatedByNameSnapshot: data['updatedByName']! as String,
      updatedAt: updatedAt.toDate(),
      materializedAt: materializedAt.toDate(),
    );
  }

  static bool _validTransitions(
    HandoffSessionStatus status,
    bool accepted,
    bool declined,
    bool cancelled,
    bool closed,
    Object? revision,
  ) => switch (status) {
    HandoffSessionStatus.offered =>
      revision == 1 && !accepted && !declined && !cancelled && !closed,
    HandoffSessionStatus.accepted =>
      revision == 2 && accepted && !declined && !cancelled && !closed,
    HandoffSessionStatus.declined =>
      revision == 2 && !accepted && declined && !cancelled && !closed,
    HandoffSessionStatus.cancelled =>
      revision == 2 && !accepted && !declined && cancelled && !closed,
    HandoffSessionStatus.closed =>
      revision == 3 && accepted && !declined && !cancelled && closed,
  };

  static bool _validTransitionAuthority(
    Map<String, Object?> data,
    HandoffSessionStatus status,
    HandoffResolutionReason? reason,
  ) {
    final offeredAt = data['offeredAt']! as Timestamp;
    final acceptedAt = data['acceptedAt'] as Timestamp?;
    final declinedAt = data['declinedAt'] as Timestamp?;
    final cancelledAt = data['cancelledAt'] as Timestamp?;
    final closedAt = data['closedAt'] as Timestamp?;
    final acceptedByRecipient = _sameActor(
      data['acceptedByID'],
      data['acceptedByName'],
      data['recipientID'],
      data['recipientName'],
    );
    return switch (status) {
      HandoffSessionStatus.offered => reason == null,
      HandoffSessionStatus.accepted =>
        reason == null &&
            acceptedByRecipient &&
            _notBefore(acceptedAt, offeredAt),
      HandoffSessionStatus.declined =>
        reason == null &&
            _sameActor(
              data['declinedByID'],
              data['declinedByName'],
              data['recipientID'],
              data['recipientName'],
            ) &&
            _notBefore(declinedAt, offeredAt),
      HandoffSessionStatus.cancelled =>
        (reason == HandoffResolutionReason.ownerRecovery ||
                (reason == null &&
                    _sameActor(
                      data['cancelledByID'],
                      data['cancelledByName'],
                      data['creatorID'],
                      data['creatorName'],
                    ))) &&
            _notBefore(cancelledAt, offeredAt),
      HandoffSessionStatus.closed =>
        acceptedByRecipient &&
            _notBefore(acceptedAt, offeredAt) &&
            _notBefore(closedAt, acceptedAt!) &&
            (reason == HandoffResolutionReason.ownerRecovery ||
                (reason == null &&
                    (_sameActor(
                          data['closedByID'],
                          data['closedByName'],
                          data['creatorID'],
                          data['creatorName'],
                        ) ||
                        _sameActor(
                          data['closedByID'],
                          data['closedByName'],
                          data['recipientID'],
                          data['recipientName'],
                        )))),
    };
  }

  static bool _sameActor(
    Object? actorId,
    Object? actorName,
    Object? expectedId,
    Object? expectedName,
  ) => actorId == expectedId && actorName == expectedName;

  static bool _notBefore(Timestamp? value, Timestamp boundary) =>
      value != null && !value.toDate().isBefore(boundary.toDate());

  static bool _transition(Object? id, Object? name, Object? at) {
    if (id == null && name == null && at == null) return false;
    if (_memberPair(id, name) && at is Timestamp) return true;
    throw const FormatException('Malformed handoff transition');
  }

  static HandoffSessionMutationResult _decodeResponse(
    Map<String, Object?> data,
  ) {
    final status = _enumByName(
      HandoffSessionStatus.values,
      data['sessionStatus'],
    );
    if (data.length != _responseKeys.length ||
        !data.keys.every(_responseKeys.contains) ||
        !_id(data['sessionID']) ||
        data['sessionRevision'] is! int ||
        (data['sessionRevision'] as int) < 1 ||
        status == null ||
        (data['activeSessionID'] != null && !_id(data['activeSessionID'])) ||
        !_versionId(data['versionID']) ||
        data['existing'] is! bool) {
      throw const HandoffSessionException(
        HandoffSessionErrorCode.malformedData,
      );
    }
    final active =
        status == HandoffSessionStatus.offered ||
        status == HandoffSessionStatus.accepted;
    if (active
        ? data['activeSessionID'] != data['sessionID']
        : data['activeSessionID'] != null) {
      throw const HandoffSessionException(
        HandoffSessionErrorCode.malformedData,
      );
    }
    return HandoffSessionMutationResult(
      sessionId: data['sessionID']! as String,
      sessionRevision: data['sessionRevision']! as int,
      sessionStatus: status,
      activeSessionId: data['activeSessionID'] as String?,
      versionId: data['versionID']! as String,
      existing: data['existing']! as bool,
    );
  }

  static T? _enumByName<T extends Enum>(Iterable<T> values, Object? value) =>
      value is String
      ? values.where((item) => item.name == value).firstOrNull
      : null;

  static bool _id(Object? value) =>
      value is String &&
      value.isNotEmpty &&
      value.length <= 128 &&
      !value.contains('/');

  static bool _versionId(Object? value) =>
      value is String && RegExp(r'^v[0-9]{6}$').hasMatch(value);

  static bool _memberPair(Object? id, Object? name) =>
      _id(id) && name is String && name.trim().isNotEmpty && name.length <= 50;

  static bool _boundedText(Object? value, int maximum) =>
      value is String && value.length <= maximum;

  static bool _mutationId(String value) =>
      value.isNotEmpty && value.length <= 128 && !value.contains('/');

  static HandoffSessionException _mapped(Object error) {
    if (error is HandoffSessionException) return error;
    final code = switch (error) {
      FirebaseFunctionsException() => error.code,
      FirebaseException() => error.code,
      _ => 'unknown',
    };
    final details = error is FirebaseFunctionsException ? error.details : null;
    final diagnosticValue = details is Map
        ? details['code'] ?? details['reason']
        : null;
    final diagnostic = diagnosticValue is String ? diagnosticValue : null;
    return HandoffSessionException(switch (code) {
      'invalid-argument' => HandoffSessionErrorCode.invalidInput,
      'permission-denied' ||
      'unauthenticated' => HandoffSessionErrorCode.permission,
      'aborted' => HandoffSessionErrorCode.stale,
      'not-found' => HandoffSessionErrorCode.notFound,
      'failed-precondition' => HandoffSessionErrorCode.blocked,
      'unavailable' ||
      'deadline-exceeded' ||
      'network-request-failed' => HandoffSessionErrorCode.network,
      'data-loss' => HandoffSessionErrorCode.malformedData,
      _ => HandoffSessionErrorCode.backendUnavailable,
    }, diagnosticCode: diagnostic);
  }
}

final class _ActiveHandoffPointer {
  const _ActiveHandoffPointer({
    required this.sessionId,
    required this.sessionStatus,
    required this.plannedEndAt,
  });

  final String sessionId;
  final String sessionStatus;
  final DateTime plannedEndAt;
}
