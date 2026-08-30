import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/collaboration_event_models.dart';

final class CollaborationEventSnapshot {
  const CollaborationEventSnapshot({
    required this.events,
    required this.isFromCache,
    required this.droppedEventCount,
    this.nextCursor,
    this.hasMore = false,
    this.isPotentiallyIncomplete = true,
  });

  final List<CollaborationEvent> events;
  final bool isFromCache;
  final int droppedEventCount;
  final CollaborationPageCursor? nextCursor;
  final bool hasMore;

  /// True until retained marker-free task writers have been retired with evidence.
  final bool isPotentiallyIncomplete;
}

final class CollaborationEventPage {
  const CollaborationEventPage({
    required this.events,
    required this.nextCursor,
    required this.droppedEventCount,
    this.hasMore = false,
    this.isFromCache = false,
    this.isPotentiallyIncomplete = true,
  });

  final List<CollaborationEvent> events;
  final CollaborationPageCursor? nextCursor;
  final int droppedEventCount;
  final bool hasMore;
  final bool isFromCache;
  final bool isPotentiallyIncomplete;
}

final class CollaborationReadCursorSnapshot {
  const CollaborationReadCursorSnapshot({
    required this.cursor,
    required this.isFromCache,
    required this.hasPendingWrites,
  });

  final CollaborationReadCursor? cursor;
  final bool isFromCache;
  final bool hasPendingWrites;
}

enum CollaborationEventRepositoryErrorCode {
  invalidInput,
  network,
  permission,
  backendUnavailable,
}

final class CollaborationEventRepositoryException implements Exception {
  const CollaborationEventRepositoryException(this.code);

  final CollaborationEventRepositoryErrorCode code;
}

abstract interface class CollaborationEventRepository {
  Stream<CollaborationEventSnapshot> observeRecent(
    String householdId, {
    int limit = 50,
  });

  Future<CollaborationEventPage> loadPage(
    String householdId, {
    int limit = 50,
    CollaborationPageCursor? after,
  });

  Stream<CollaborationReadCursorSnapshot> observeReadCursor(
    String householdId,
    String memberId,
  );

  Future<void> markRead(
    String householdId,
    String memberId,
    CollaborationReadCursor cursor,
  );

  Future<void> stopObserving();
}

final collaborationEventRepositoryProvider =
    Provider<CollaborationEventRepository>((ref) {
      throw StateError(
        'CollaborationEventRepository must be provided at the app boundary.',
      );
    });

/// Deterministic fake for later Updates application and widget tests.
final class FakeCollaborationEventRepository
    implements CollaborationEventRepository {
  FakeCollaborationEventRepository({List<CollaborationEvent> events = const []})
    : _events = List.of(events);

  List<CollaborationEvent> _events;
  final _controllers = <(StreamController<CollaborationEventSnapshot>, int)>[];
  final _readCursors = <(String, String), CollaborationReadCursor>{};
  final _cursorControllers =
      <
        (String, String),
        List<StreamController<CollaborationReadCursorSnapshot>>
      >{};

  void replace(List<CollaborationEvent> events) {
    _events = List.of(events);
    for (final item in List.of(_controllers)) {
      if (!item.$1.isClosed) item.$1.add(_snapshot(limit: item.$2));
    }
  }

  @override
  Stream<CollaborationEventSnapshot> observeRecent(
    String householdId, {
    int limit = 50,
  }) {
    _validate(householdId, limit);
    late final StreamController<CollaborationEventSnapshot> controller;
    controller = StreamController<CollaborationEventSnapshot>(
      onListen: () => controller.add(_snapshot(limit: limit)),
      onCancel: () => _controllers.remove((controller, limit)),
    );
    _controllers.add((controller, limit));
    return controller.stream;
  }

  @override
  Future<CollaborationEventPage> loadPage(
    String householdId, {
    int limit = 50,
    CollaborationPageCursor? after,
  }) async {
    _validate(householdId, limit);
    final sorted = _sorted();
    if (after != null && after is! _FakeCollaborationPageCursor) {
      throw const CollaborationEventRepositoryException(
        CollaborationEventRepositoryErrorCode.invalidInput,
      );
    }
    final start = after is _FakeCollaborationPageCursor ? after.offset : 0;
    final page = sorted.skip(start).take(limit).toList(growable: false);
    return CollaborationEventPage(
      events: page,
      nextCursor: page.length < limit
          ? null
          : _FakeCollaborationPageCursor(start + page.length),
      droppedEventCount: 0,
      hasMore: page.length == limit,
    );
  }

  @override
  Stream<CollaborationReadCursorSnapshot> observeReadCursor(
    String householdId,
    String memberId,
  ) {
    _validateIdentity(householdId, memberId);
    final key = (householdId, memberId);
    late final StreamController<CollaborationReadCursorSnapshot> controller;
    controller = StreamController<CollaborationReadCursorSnapshot>(
      onListen: () => controller.add(_cursorSnapshot(key)),
      onCancel: () => _cursorControllers[key]?.remove(controller),
    );
    _cursorControllers.putIfAbsent(key, () => []).add(controller);
    return controller.stream;
  }

  @override
  Future<void> markRead(
    String householdId,
    String memberId,
    CollaborationReadCursor cursor,
  ) async {
    _validateIdentity(householdId, memberId);
    final matching = _events
        .where((event) => event.id == cursor.eventId)
        .firstOrNull;
    final key = (householdId, memberId);
    final current = _readCursors[key];
    if (matching == null ||
        !matching.occurredAt.isAtSameMomentAs(cursor.occurredAt) ||
        (current != null && _compareCursors(cursor, current) < 0)) {
      throw const CollaborationEventRepositoryException(
        CollaborationEventRepositoryErrorCode.invalidInput,
      );
    }
    _readCursors[key] = cursor;
    final snapshot = _cursorSnapshot(key);
    for (final controller in List.of(
      _cursorControllers[key] ??
          const <StreamController<CollaborationReadCursorSnapshot>>[],
    )) {
      if (!controller.isClosed) controller.add(snapshot);
    }
  }

  @override
  Future<void> stopObserving() async {
    final controllers = _controllers.map((item) => item.$1).toList();
    _controllers.clear();
    for (final controller in controllers) {
      await controller.close();
    }
    final cursorControllers = _cursorControllers.values
        .expand((items) => items)
        .toList(growable: false);
    _cursorControllers.clear();
    for (final controller in cursorControllers) {
      await controller.close();
    }
  }

  CollaborationEventSnapshot _snapshot({required int limit}) =>
      CollaborationEventSnapshot(
        events: _sorted().take(limit).toList(growable: false),
        isFromCache: false,
        droppedEventCount: 0,
        nextCursor: _events.length < limit || _events.isEmpty
            ? null
            : _FakeCollaborationPageCursor(limit),
        hasMore: _events.length >= limit,
      );

  CollaborationReadCursorSnapshot _cursorSnapshot((String, String) key) =>
      CollaborationReadCursorSnapshot(
        cursor: _readCursors[key],
        isFromCache: false,
        hasPendingWrites: false,
      );

  static int _compareCursors(
    CollaborationReadCursor left,
    CollaborationReadCursor right,
  ) {
    final byTime = left.occurredAt.compareTo(right.occurredAt);
    return byTime != 0 ? byTime : left.eventId.compareTo(right.eventId);
  }

  List<CollaborationEvent> _sorted() => List.of(_events)
    ..sort((left, right) {
      final byTime = right.occurredAt.compareTo(left.occurredAt);
      return byTime != 0 ? byTime : right.id.compareTo(left.id);
    });

  static void _validate(String householdId, int limit) {
    if (householdId.isEmpty || limit < 1 || limit > 50) {
      throw const CollaborationEventRepositoryException(
        CollaborationEventRepositoryErrorCode.invalidInput,
      );
    }
  }

  static void _validateIdentity(String householdId, String memberId) {
    if (householdId.isEmpty || memberId.isEmpty) {
      throw const CollaborationEventRepositoryException(
        CollaborationEventRepositoryErrorCode.invalidInput,
      );
    }
  }
}

final class _FakeCollaborationPageCursor implements CollaborationPageCursor {
  const _FakeCollaborationPageCursor(this.offset);

  final int offset;
}
