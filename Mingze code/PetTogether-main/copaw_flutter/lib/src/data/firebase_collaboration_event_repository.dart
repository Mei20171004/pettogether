import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/collaboration_event_models.dart';
import 'collaboration_event_gateway.dart';
import 'collaboration_event_repository.dart';
import 'firebase_collaboration_event_gateway.dart';

final class FirebaseCollaborationEventRepository
    implements CollaborationEventRepository {
  FirebaseCollaborationEventRepository({CollaborationEventGateway? gateway})
    : _gateway = gateway ?? FirebaseCollaborationEventGateway();

  final CollaborationEventGateway _gateway;
  StreamSubscription<StoredCollaborationEventSnapshot>? _subscription;
  StreamController<CollaborationEventSnapshot>? _controller;
  StreamSubscription<StoredCollaborationReadCursorSnapshot>?
  _cursorSubscription;
  StreamController<CollaborationReadCursorSnapshot>? _cursorController;

  @override
  Stream<CollaborationEventSnapshot> observeRecent(
    String householdId, {
    int limit = 50,
  }) {
    _validate(householdId, limit);
    final controller = StreamController<CollaborationEventSnapshot>();
    unawaited(_replace(householdId, limit, controller));
    return controller.stream;
  }

  Future<void> _replace(
    String householdId,
    int limit,
    StreamController<CollaborationEventSnapshot> controller,
  ) async {
    await _stopEventObservation();
    _controller = controller;
    _subscription = _gateway.observeRecent(householdId, limit: limit).listen((
      snapshot,
    ) {
      final decoded = _decodeAll(snapshot.documents);
      final hasMore =
          snapshot.documents.length == limit && snapshot.continuation != null;
      controller.add(
        CollaborationEventSnapshot(
          events: decoded.events,
          isFromCache: snapshot.isFromCache,
          droppedEventCount: decoded.dropped,
          nextCursor: hasMore ? snapshot.continuation : null,
          hasMore: hasMore,
        ),
      );
    }, onError: (Object error) => controller.addError(_mapped(error)));
  }

  @override
  Future<CollaborationEventPage> loadPage(
    String householdId, {
    int limit = 50,
    CollaborationPageCursor? after,
  }) async {
    _validate(householdId, limit);
    try {
      final snapshot = await _gateway.readPage(
        householdId,
        limit: limit,
        after: after,
      );
      final decoded = _decodeAll(snapshot.documents);
      final hasMore =
          snapshot.documents.length == limit && snapshot.continuation != null;
      return CollaborationEventPage(
        events: decoded.events,
        nextCursor: hasMore ? snapshot.continuation : null,
        droppedEventCount: decoded.dropped,
        hasMore: hasMore,
        isFromCache: snapshot.isFromCache,
      );
    } on Object catch (error) {
      throw _mapped(error);
    }
  }

  @override
  Stream<CollaborationReadCursorSnapshot> observeReadCursor(
    String householdId,
    String memberId,
  ) {
    _validateIdentity(householdId, memberId);
    final controller = StreamController<CollaborationReadCursorSnapshot>();
    unawaited(_replaceCursor(householdId, memberId, controller));
    return controller.stream;
  }

  Future<void> _replaceCursor(
    String householdId,
    String memberId,
    StreamController<CollaborationReadCursorSnapshot> controller,
  ) async {
    await _stopCursorObservation();
    _cursorController = controller;
    _cursorSubscription = _gateway
        .observeReadCursor(householdId, memberId)
        .listen((snapshot) {
          try {
            controller.add(_decodeCursor(snapshot));
          } on FormatException catch (error) {
            controller.addError(_mapped(error));
          }
        }, onError: (Object error) => controller.addError(_mapped(error)));
  }

  @override
  Future<void> markRead(
    String householdId,
    String memberId,
    CollaborationReadCursor cursor,
  ) async {
    _validateIdentity(householdId, memberId);
    if (!_eventId(cursor.eventId)) {
      throw const CollaborationEventRepositoryException(
        CollaborationEventRepositoryErrorCode.invalidInput,
      );
    }
    try {
      await _gateway.writeReadCursor(householdId, memberId, cursor);
    } on Object catch (error) {
      throw _mapped(error);
    }
  }

  @override
  Future<void> stopObserving() async {
    await _stopEventObservation();
    await _stopCursorObservation();
  }

  Future<void> _stopEventObservation() async {
    final subscription = _subscription;
    final controller = _controller;
    _subscription = null;
    _controller = null;
    await subscription?.cancel();
    await controller?.close();
  }

  Future<void> _stopCursorObservation() async {
    final subscription = _cursorSubscription;
    final controller = _cursorController;
    _cursorSubscription = null;
    _cursorController = null;
    await subscription?.cancel();
    await controller?.close();
  }

  static CollaborationReadCursorSnapshot _decodeCursor(
    StoredCollaborationReadCursorSnapshot snapshot,
  ) {
    final data = snapshot.data;
    if (data == null) {
      return CollaborationReadCursorSnapshot(
        cursor: null,
        isFromCache: snapshot.isFromCache,
        hasPendingWrites: snapshot.hasPendingWrites,
      );
    }
    const expectedKeys = {
      'schemaVersion',
      'occurredAt',
      'eventID',
      'updatedAt',
    };
    final occurredAt = data['occurredAt'];
    final eventId = data['eventID'];
    final updatedAt = data['updatedAt'];
    if (data.length != expectedKeys.length ||
        !data.keys.every(expectedKeys.contains) ||
        data['schemaVersion'] != 1 ||
        occurredAt is! Timestamp ||
        !_eventId(eventId) ||
        (updatedAt is! Timestamp &&
            !(snapshot.hasPendingWrites && updatedAt == null))) {
      throw const FormatException('Malformed collaboration read cursor');
    }
    return CollaborationReadCursorSnapshot(
      cursor: CollaborationReadCursor(
        occurredAt: occurredAt.toDate(),
        eventId: eventId as String,
      ),
      isFromCache: snapshot.isFromCache,
      hasPendingWrites: snapshot.hasPendingWrites,
    );
  }

  static _DecodedEvents _decodeAll(
    List<StoredCollaborationEventDocument> documents,
  ) {
    final events = <CollaborationEvent>[];
    var dropped = 0;
    for (final document in documents) {
      try {
        events.add(_decode(document));
      } on FormatException {
        dropped += 1;
      }
    }
    return _DecodedEvents(List.unmodifiable(events), dropped);
  }

  static CollaborationEvent _decode(StoredCollaborationEventDocument document) {
    final data = document.data;
    return switch (data['schemaVersion']) {
      1 => _decodeV1(document),
      2 => _decodeV2(document),
      _ => throw const FormatException('Unknown collaboration event version'),
    };
  }

  static CollaborationEvent _decodeV1(
    StoredCollaborationEventDocument document,
  ) {
    final data = document.data;
    const expectedKeys = {
      'schemaVersion',
      'sourceType',
      'sourceID',
      'sourceRevision',
      'action',
      'actorID',
      'actorName',
      'targetMemberID',
      'targetMemberName',
      'requestID',
      'assignmentMode',
      'petID',
      'petName',
      'taskTitle',
      'taskCategory',
      'taskPriority',
      'taskDueTime',
      'stateAfter',
      'occurredAt',
      'recordedAt',
    };
    final action = _enumByName(CollaborationEventAction.values, data['action']);
    final state = _enumByName(
      CollaborationTaskState.values,
      data['stateAfter'],
    );
    final occurredAt = data['occurredAt'];
    final recordedAt = data['recordedAt'];
    final taskDueTime = data['taskDueTime'];
    final targetId = data['targetMemberID'];
    final targetName = data['targetMemberName'];
    if (data.length != expectedKeys.length ||
        !data.keys.every(expectedKeys.contains) ||
        !_eventId(document.id) ||
        data['schemaVersion'] != 1 ||
        data['sourceType'] != 'task' ||
        !_id(data['sourceID']) ||
        data['sourceRevision'] is! int ||
        (data['sourceRevision'] as int) < 0 ||
        action == null ||
        !_id(data['actorID']) ||
        !_text(data['actorName'], 50) ||
        ((targetId == null) != (targetName == null)) ||
        (targetId != null && !_id(targetId)) ||
        (targetName != null && !_text(targetName, 50)) ||
        (data['requestID'] != null && !_id(data['requestID'])) ||
        (data['assignmentMode'] != null &&
            data['assignmentMode'] != 'direct' &&
            data['assignmentMode'] != 'open') ||
        !_id(data['petID']) ||
        !_text(data['petName'], 60) ||
        !_text(data['taskTitle'], 120) ||
        !const {
          'feeding',
          'walking',
          'medication',
          'grooming',
          'other',
        }.contains(data['taskCategory']) ||
        !const {'normal', 'urgent'}.contains(data['taskPriority']) ||
        taskDueTime is! Timestamp ||
        state == null ||
        occurredAt is! Timestamp ||
        recordedAt is! Timestamp) {
      throw const FormatException('Malformed collaboration event');
    }
    return CollaborationEvent(
      id: document.id,
      sourceId: data['sourceID'] as String,
      sourceRevision: data['sourceRevision'] as int,
      action: action,
      actorId: data['actorID'] as String,
      actorNameSnapshot: data['actorName'] as String,
      targetMemberId: targetId as String?,
      targetMemberNameSnapshot: targetName as String?,
      requestId: data['requestID'] as String?,
      assignmentMode: data['assignmentMode'] as String?,
      petId: data['petID'] as String,
      petNameSnapshot: data['petName'] as String,
      taskTitleSnapshot: data['taskTitle'] as String,
      taskCategorySnapshot: data['taskCategory'] as String,
      taskPrioritySnapshot: data['taskPriority'] as String,
      taskDueTime: taskDueTime.toDate(),
      stateAfter: state,
      occurredAt: occurredAt.toDate(),
      recordedAt: recordedAt.toDate(),
    );
  }

  static CollaborationEvent _decodeV2(
    StoredCollaborationEventDocument document,
  ) {
    final data = document.data;
    const expectedKeys = {
      'schemaVersion',
      'sourceType',
      'sourceID',
      'sourceRevision',
      'action',
      'actorID',
      'actorName',
      'responsibilityFromID',
      'responsibilityFromName',
      'responsibilityToID',
      'responsibilityToName',
      'handoffCreatorID',
      'handoffCreatorName',
      'handoffRecipientID',
      'handoffRecipientName',
      'requestID',
      'petID',
      'petName',
      'taskTitle',
      'taskCategory',
      'taskPriority',
      'taskDueTime',
      'stateAfter',
      'handoffStatus',
      'occurredAt',
      'recordedAt',
    };
    final sourceType = _enumByName(
      CollaborationEventSourceType.values,
      data['sourceType'],
    );
    final action = _enumByName(CollaborationEventAction.values, data['action']);
    final occurredAt = data['occurredAt'];
    final recordedAt = data['recordedAt'];
    final handoff = sourceType == CollaborationEventSourceType.handoffSession;
    final taskState = data['stateAfter'] == null
        ? null
        : _enumByName(CollaborationTaskState.values, data['stateAfter']);
    if (data.length != expectedKeys.length ||
        !data.keys.every(expectedKeys.contains) ||
        data['schemaVersion'] != 2 ||
        !_eventId(document.id) ||
        sourceType == null ||
        !_id(data['sourceID']) ||
        data['sourceRevision'] is! int ||
        (data['sourceRevision'] as int) < 1 ||
        action == null ||
        !_v2Action(action) ||
        !_id(data['actorID']) ||
        !_text(data['actorName'], 50) ||
        !_nullablePair(
          data['responsibilityFromID'],
          data['responsibilityFromName'],
        ) ||
        !_nullablePair(
          data['responsibilityToID'],
          data['responsibilityToName'],
        ) ||
        !_nullablePair(data['handoffCreatorID'], data['handoffCreatorName']) ||
        !_nullablePair(
          data['handoffRecipientID'],
          data['handoffRecipientName'],
        ) ||
        (data['requestID'] != null && !_id(data['requestID'])) ||
        occurredAt is! Timestamp ||
        recordedAt is! Timestamp ||
        (handoff
            ? !_validV2Handoff(data, action)
            : !_validV2Task(data, action, sourceType, taskState))) {
      throw const FormatException('Malformed collaboration v2 event');
    }
    return CollaborationEvent(
      id: document.id,
      sourceId: data['sourceID']! as String,
      sourceRevision: data['sourceRevision']! as int,
      action: action,
      actorId: data['actorID']! as String,
      actorNameSnapshot: data['actorName']! as String,
      targetMemberId: null,
      targetMemberNameSnapshot: null,
      requestId: data['requestID'] as String?,
      assignmentMode: null,
      petId: data['petID'] as String?,
      petNameSnapshot: data['petName'] as String?,
      taskTitleSnapshot: data['taskTitle'] as String?,
      taskCategorySnapshot: data['taskCategory'] as String?,
      taskPrioritySnapshot: data['taskPriority'] as String?,
      taskDueTime: (data['taskDueTime'] as Timestamp?)?.toDate(),
      stateAfter: taskState,
      occurredAt: occurredAt.toDate(),
      recordedAt: recordedAt.toDate(),
      sourceType: sourceType,
      responsibilityFromId: data['responsibilityFromID'] as String?,
      responsibilityFromNameSnapshot: data['responsibilityFromName'] as String?,
      responsibilityToId: data['responsibilityToID'] as String?,
      responsibilityToNameSnapshot: data['responsibilityToName'] as String?,
      handoffCreatorId: data['handoffCreatorID'] as String?,
      handoffCreatorNameSnapshot: data['handoffCreatorName'] as String?,
      handoffRecipientId: data['handoffRecipientID'] as String?,
      handoffRecipientNameSnapshot: data['handoffRecipientName'] as String?,
      handoffStatus: data['handoffStatus'] as String?,
    );
  }

  static bool _validV2Task(
    Map<String, Object?> data,
    CollaborationEventAction action,
    CollaborationEventSourceType sourceType,
    CollaborationTaskState? state,
  ) {
    final release = action == CollaborationEventAction.taskReleased;
    if (_handoffAction(action)) return false;
    final expectedSource = release
        ? CollaborationEventSourceType.task
        : CollaborationEventSourceType.taskResponsibilityTransfer;
    return sourceType == expectedSource &&
        data['handoffCreatorID'] == null &&
        data['handoffCreatorName'] == null &&
        data['handoffRecipientID'] == null &&
        data['handoffRecipientName'] == null &&
        data['handoffStatus'] == null &&
        _id(data['petID']) &&
        _text(data['petName'], 60) &&
        _text(data['taskTitle'], 120) &&
        const {
          'feeding',
          'walking',
          'medication',
          'grooming',
          'other',
        }.contains(data['taskCategory']) &&
        const {'normal', 'urgent'}.contains(data['taskPriority']) &&
        data['taskDueTime'] is Timestamp &&
        state == _expectedTaskState(action) &&
        _id(data['responsibilityFromID']) &&
        (data['taskCategory'] != 'medication' ||
            data['taskTitle'] == 'Medication care') &&
        (release
            ? data['responsibilityToID'] == null && data['requestID'] == null
            : _id(data['responsibilityToID']) &&
                  data['requestID'] == data['sourceID']);
  }

  static bool _validV2Handoff(
    Map<String, Object?> data,
    CollaborationEventAction action,
  ) =>
      _handoffAction(action) &&
      data['responsibilityFromID'] == null &&
      data['responsibilityFromName'] == null &&
      data['responsibilityToID'] == null &&
      data['responsibilityToName'] == null &&
      _id(data['handoffCreatorID']) &&
      _id(data['handoffRecipientID']) &&
      data['requestID'] == null &&
      data['petID'] == null &&
      data['petName'] == null &&
      data['taskTitle'] == null &&
      data['taskCategory'] == null &&
      data['taskPriority'] == null &&
      data['taskDueTime'] == null &&
      data['stateAfter'] == null &&
      data['handoffStatus'] == _expectedHandoffStatus(action);

  static CollaborationTaskState? _expectedTaskState(
    CollaborationEventAction action,
  ) => switch (action) {
    CollaborationEventAction.taskReleased => CollaborationTaskState.unclaimed,
    CollaborationEventAction.taskReassignRequested ||
    CollaborationEventAction.taskTakeoverRequested ||
    CollaborationEventAction.taskReassigned ||
    CollaborationEventAction.taskTakenOver ||
    CollaborationEventAction.taskTransferDeclined ||
    CollaborationEventAction.taskTransferCancelled =>
      CollaborationTaskState.claimed,
    CollaborationEventAction.taskTransferSuperseded =>
      CollaborationTaskState.completed,
    _ => null,
  };

  static String? _expectedHandoffStatus(CollaborationEventAction action) =>
      switch (action) {
        CollaborationEventAction.handoffOffered => 'offered',
        CollaborationEventAction.handoffAccepted => 'accepted',
        CollaborationEventAction.handoffDeclined => 'declined',
        CollaborationEventAction.handoffCancelled => 'cancelled',
        CollaborationEventAction.handoffClosed => 'closed',
        _ => null,
      };

  static bool _v2Action(CollaborationEventAction action) =>
      action.index >= CollaborationEventAction.taskReleased.index;

  static bool _handoffAction(CollaborationEventAction action) =>
      switch (action) {
        CollaborationEventAction.handoffOffered ||
        CollaborationEventAction.handoffAccepted ||
        CollaborationEventAction.handoffDeclined ||
        CollaborationEventAction.handoffCancelled ||
        CollaborationEventAction.handoffClosed => true,
        _ => false,
      };

  static bool _nullablePair(Object? id, Object? name) =>
      (id == null && name == null) || (_id(id) && _text(name, 50));

  static T? _enumByName<T extends Enum>(Iterable<T> values, Object? name) =>
      name is String
      ? values.where((item) => item.name == name).firstOrNull
      : null;

  static bool _id(Object? value) =>
      value is String &&
      value.isNotEmpty &&
      value.length <= 128 &&
      !value.contains('/');

  static bool _text(Object? value, int maximum) =>
      value is String && value.trim().isNotEmpty && value.length <= maximum;

  static bool _eventId(Object? value) =>
      value is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(value);

  static void _validate(String householdId, int limit) {
    if (!_id(householdId) || limit < 1 || limit > 50) {
      throw const CollaborationEventRepositoryException(
        CollaborationEventRepositoryErrorCode.invalidInput,
      );
    }
  }

  static void _validateIdentity(String householdId, String memberId) {
    if (!_id(householdId) || !_id(memberId)) {
      throw const CollaborationEventRepositoryException(
        CollaborationEventRepositoryErrorCode.invalidInput,
      );
    }
  }

  static CollaborationEventRepositoryException _mapped(Object error) {
    if (error is CollaborationEventRepositoryException) return error;
    if (error is FirebaseException) {
      return CollaborationEventRepositoryException(switch (error.code) {
        'network-request-failed' ||
        'unavailable' => CollaborationEventRepositoryErrorCode.network,
        'permission-denied' => CollaborationEventRepositoryErrorCode.permission,
        _ => CollaborationEventRepositoryErrorCode.backendUnavailable,
      });
    }
    return const CollaborationEventRepositoryException(
      CollaborationEventRepositoryErrorCode.backendUnavailable,
    );
  }
}

final class _DecodedEvents {
  const _DecodedEvents(this.events, this.dropped);

  final List<CollaborationEvent> events;
  final int dropped;
}
