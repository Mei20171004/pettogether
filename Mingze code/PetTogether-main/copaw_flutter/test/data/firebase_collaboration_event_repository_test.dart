import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:copaw_flutter/src/data/collaboration_event_gateway.dart';
import 'package:copaw_flutter/src/data/collaboration_event_repository.dart';
import 'package:copaw_flutter/src/data/firebase_collaboration_event_repository.dart';
import 'package:copaw_flutter/src/domain/collaboration_event_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'decodes bounded recent events and exposes incomplete/cache state',
    () async {
      final gateway = _Gateway();
      final repository = FirebaseCollaborationEventRepository(gateway: gateway);
      final result = repository.observeRecent('home-1', limit: 20).first;
      await Future<void>.delayed(Duration.zero);
      gateway.add(
        StoredCollaborationEventSnapshot(
          documents: [_document()],
          isFromCache: true,
        ),
      );

      final snapshot = await result;
      expect(gateway.observed, [('home-1', 20)]);
      expect(
        snapshot.events.single.action,
        CollaborationEventAction.taskAccepted,
      );
      expect(snapshot.events.single.actorNameSnapshot, 'Alex');
      expect(snapshot.events.single.targetMemberNameSnapshot, 'Mingze');
      expect(snapshot.isFromCache, true);
      expect(snapshot.isPotentiallyIncomplete, true);
      expect(snapshot.droppedEventCount, 0);
    },
  );

  test(
    'isolates malformed events without presenting an empty authoritative feed',
    () async {
      final gateway = _Gateway();
      final repository = FirebaseCollaborationEventRepository(gateway: gateway);
      final result = repository.observeRecent('home-1').first;
      await Future<void>.delayed(Duration.zero);
      gateway.add(
        StoredCollaborationEventSnapshot(
          documents: [
            _document(),
            _document(overrides: {'actorID': 'actor/invalid'}),
          ],
          isFromCache: false,
        ),
      );

      final snapshot = await result;
      expect(snapshot.events, hasLength(1));
      expect(snapshot.droppedEventCount, 1);
      expect(snapshot.isPotentiallyIncomplete, true);
    },
  );

  test('dual-decodes exact v2 responsibility and handoff events', () async {
    final gateway = _Gateway();
    final repository = FirebaseCollaborationEventRepository(gateway: gateway);
    final result = repository.observeRecent('home-1').first;
    await Future<void>.delayed(Duration.zero);
    gateway.add(
      StoredCollaborationEventSnapshot(
        documents: [_v2TaskDocument(), _v2HandoffDocument()],
        isFromCache: false,
      ),
    );

    final snapshot = await result;
    expect(snapshot.droppedEventCount, 0);
    expect(
      snapshot.events.map((event) => event.action),
      containsAll([
        CollaborationEventAction.taskReassignRequested,
        CollaborationEventAction.handoffOffered,
      ]),
    );
    final handoff = snapshot.events.singleWhere((event) => event.isHandoff);
    expect(handoff.taskTitleSnapshot, isNull);
    expect(handoff.handoffRecipientNameSnapshot, 'Blair');
    expect(handoff.handoffStatus, 'offered');
  });

  test('v2 transfer request identity and medication title are exact', () async {
    final gateway = _Gateway();
    final repository = FirebaseCollaborationEventRepository(gateway: gateway);
    final result = repository.observeRecent('home-1').first;
    await Future<void>.delayed(Duration.zero);
    gateway.add(
      StoredCollaborationEventSnapshot(
        documents: [
          _v2TaskDocument(overrides: {'requestID': 'different-transfer'}),
          _v2TaskDocument(
            id: _eventId('d'),
            overrides: {
              'taskCategory': 'medication',
              'taskTitle': 'Secret dose title',
            },
          ),
        ],
        isFromCache: false,
      ),
    );

    final snapshot = await result;
    expect(snapshot.events, isEmpty);
    expect(snapshot.droppedEventCount, 2);
  });

  test(
    'page passes through an opaque continuation and cache metadata',
    () async {
      final next = _PageCursor('next-page');
      final gateway = _Gateway(
        page: StoredCollaborationEventSnapshot(
          documents: [_document()],
          isFromCache: true,
          continuation: next,
        ),
      );
      final repository = FirebaseCollaborationEventRepository(gateway: gateway);
      final after = _PageCursor('current-page');

      final page = await repository.loadPage('home-1', limit: 1, after: after);
      expect(gateway.pages.single.$3, same(after));
      expect(page.nextCursor, same(next));
      expect(page.hasMore, true);
      expect(page.isFromCache, true);
      expect(page.isPotentiallyIncomplete, true);
    },
  );

  test('older pages continue after a malformed raw final document', () async {
    final start = _PageCursor('start');
    final next = _PageCursor('next');
    final malformed = _document(
      id: _eventId('b'),
      overrides: {'occurredAt': 'invalid-timestamp'},
    );
    final gateway = _Gateway(
      pageQueue: [
        StoredCollaborationEventSnapshot(
          documents: [_document(), malformed],
          isFromCache: false,
          continuation: next,
        ),
        StoredCollaborationEventSnapshot(
          documents: [_document(id: _eventId('c'))],
          isFromCache: false,
        ),
      ],
    );
    final repository = FirebaseCollaborationEventRepository(gateway: gateway);

    final first = await repository.loadPage('home-1', limit: 2, after: start);
    expect(first.events, hasLength(1));
    expect(first.droppedEventCount, 1);
    expect(first.nextCursor, same(next));
    expect(first.hasMore, true);

    final second = await repository.loadPage(
      'home-1',
      limit: 2,
      after: first.nextCursor,
    );
    expect(second.events.single.id, _eventId('c'));
    expect(second.nextCursor, isNull);
    expect(second.hasMore, false);
    expect(gateway.pages, hasLength(2));
    expect(gateway.pages[0].$3, same(start));
    expect(gateway.pages[1].$3, same(next));
  });

  test(
    'recent continuation uses the final raw document after decode drops',
    () async {
      final gateway = _Gateway();
      final repository = FirebaseCollaborationEventRepository(gateway: gateway);
      final result = repository.observeRecent('home-1', limit: 2).first;
      await Future<void>.delayed(Duration.zero);
      final continuation = _PageCursor('raw-invalid-final');
      gateway.add(
        StoredCollaborationEventSnapshot(
          documents: [
            _document(),
            _document(
              id: _eventId('b'),
              overrides: {'occurredAt': 'invalid-timestamp'},
            ),
          ],
          isFromCache: false,
          continuation: continuation,
        ),
      );

      final snapshot = await result;
      expect(snapshot.events, hasLength(1));
      expect(snapshot.droppedEventCount, 1);
      expect(snapshot.nextCursor, same(continuation));
      expect(snapshot.hasMore, true);
    },
  );

  test('rejects documents with unknown keys', () async {
    final gateway = _Gateway();
    final repository = FirebaseCollaborationEventRepository(gateway: gateway);
    final result = repository.observeRecent('home-1').first;
    await Future<void>.delayed(Duration.zero);
    gateway.add(
      StoredCollaborationEventSnapshot(
        documents: [
          _document(overrides: {'unexpected': true}),
        ],
        isFromCache: false,
      ),
    );

    final snapshot = await result;
    expect(snapshot.events, isEmpty);
    expect(snapshot.droppedEventCount, 1);
  });

  test('observes and writes a private collaboration read cursor', () async {
    final gateway = _Gateway();
    final repository = FirebaseCollaborationEventRepository(gateway: gateway);
    final result = repository.observeReadCursor('home-1', 'member-a').first;
    await Future<void>.delayed(Duration.zero);
    final occurredAt = DateTime.utc(2026, 8, 17, 1);
    gateway.addCursor(
      StoredCollaborationReadCursorSnapshot(
        data: {
          'schemaVersion': 1,
          'occurredAt': Timestamp.fromDate(occurredAt),
          'eventID': _eventId('a'),
          'updatedAt': Timestamp.fromDate(occurredAt),
        },
        isFromCache: true,
        hasPendingWrites: false,
      ),
    );

    final snapshot = await result;
    expect(gateway.observedCursors, [('home-1', 'member-a')]);
    expect(snapshot.cursor?.eventId, _eventId('a'));
    expect(snapshot.isFromCache, true);
    expect(snapshot.hasPendingWrites, false);

    final cursor = CollaborationReadCursor(
      occurredAt: occurredAt,
      eventId: _eventId('a'),
    );
    await repository.markRead('home-1', 'member-a', cursor);
    expect(gateway.cursorWrites.single, ('home-1', 'member-a', cursor));
  });

  test(
    'deterministic fake keeps member cursors independent and monotonic',
    () async {
      final occurredAt = DateTime.utc(2026, 8, 17, 1);
      final first = _event(id: _eventId('a'), occurredAt: occurredAt);
      final second = _event(id: _eventId('b'), occurredAt: occurredAt);
      final repository = FakeCollaborationEventRepository(
        events: [first, second],
      );
      final firstCursor = CollaborationReadCursor(
        occurredAt: occurredAt,
        eventId: first.id,
      );
      final secondCursor = CollaborationReadCursor(
        occurredAt: occurredAt,
        eventId: second.id,
      );

      await repository.markRead('home-1', 'member-a', secondCursor);
      await repository.markRead('home-1', 'member-b', firstCursor);
      expect(
        (await repository.observeReadCursor('home-1', 'member-a').first)
            .cursor
            ?.eventId,
        second.id,
      );
      expect(
        (await repository.observeReadCursor('home-1', 'member-b').first)
            .cursor
            ?.eventId,
        first.id,
      );
      await expectLater(
        repository.markRead('home-1', 'member-a', firstCursor),
        throwsA(isA<CollaborationEventRepositoryException>()),
      );
      await expectLater(
        repository.markRead(
          'home-1',
          'member-a',
          CollaborationReadCursor(
            occurredAt: occurredAt,
            eventId: _eventId('c'),
          ),
        ),
        throwsA(isA<CollaborationEventRepositoryException>()),
      );
    },
  );

  test(
    'deterministic fake orders equal timestamps by descending event ID',
    () async {
      final at = DateTime.utc(2026, 8, 17, 1);
      final repository = FakeCollaborationEventRepository(
        events: [
          _event(id: _eventId('a'), occurredAt: at),
          _event(id: _eventId('f'), occurredAt: at),
        ],
      );

      final snapshot = await repository.observeRecent('home-1').first;
      expect(snapshot.events.map((event) => event.id), [
        _eventId('f'),
        _eventId('a'),
      ]);
      expect(snapshot.isPotentiallyIncomplete, true);
    },
  );

  test('deterministic fake continues with an opaque page token', () async {
    final at = DateTime.utc(2026, 8, 17, 1);
    final repository = FakeCollaborationEventRepository(
      events: [
        _event(id: _eventId('a'), occurredAt: at),
        _event(id: _eventId('b'), occurredAt: at),
        _event(id: _eventId('c'), occurredAt: at),
      ],
    );

    final recent = await repository.observeRecent('home-1', limit: 2).first;
    expect(recent.events.map((event) => event.id), [
      _eventId('c'),
      _eventId('b'),
    ]);
    expect(recent.hasMore, true);
    expect(recent.nextCursor, isNotNull);

    final older = await repository.loadPage(
      'home-1',
      limit: 2,
      after: recent.nextCursor,
    );
    expect(older.events.single.id, _eventId('a'));
    expect(older.hasMore, false);
    expect(older.nextCursor, isNull);
  });
}

final class _Gateway implements CollaborationEventGateway {
  _Gateway({
    StoredCollaborationEventSnapshot? page,
    List<StoredCollaborationEventSnapshot>? pageQueue,
  }) : _pages = pageQueue ?? [?page];

  final List<StoredCollaborationEventSnapshot> _pages;
  StreamController<StoredCollaborationEventSnapshot>? controller;
  StreamController<StoredCollaborationReadCursorSnapshot>? cursorController;
  final observed = <(String, int)>[];
  final pages = <(String, int, CollaborationPageCursor?)>[];
  final observedCursors = <(String, String)>[];
  final cursorWrites = <(String, String, CollaborationReadCursor)>[];

  void add(StoredCollaborationEventSnapshot snapshot) =>
      controller!.add(snapshot);

  void addCursor(StoredCollaborationReadCursorSnapshot snapshot) =>
      cursorController!.add(snapshot);

  @override
  Stream<StoredCollaborationEventSnapshot> observeRecent(
    String householdId, {
    required int limit,
  }) {
    observed.add((householdId, limit));
    controller = StreamController<StoredCollaborationEventSnapshot>();
    return controller!.stream;
  }

  @override
  Future<StoredCollaborationEventSnapshot> readPage(
    String householdId, {
    required int limit,
    CollaborationPageCursor? after,
  }) async {
    pages.add((householdId, limit, after));
    return _pages.removeAt(0);
  }

  @override
  Stream<StoredCollaborationReadCursorSnapshot> observeReadCursor(
    String householdId,
    String memberId,
  ) {
    observedCursors.add((householdId, memberId));
    cursorController =
        StreamController<StoredCollaborationReadCursorSnapshot>();
    return cursorController!.stream;
  }

  @override
  Future<void> writeReadCursor(
    String householdId,
    String memberId,
    CollaborationReadCursor cursor,
  ) async {
    cursorWrites.add((householdId, memberId, cursor));
  }
}

final class _PageCursor implements CollaborationPageCursor {
  const _PageCursor(this.label);

  final String label;
}

StoredCollaborationEventDocument _document({
  String? id,
  Map<String, Object?> overrides = const {},
}) => StoredCollaborationEventDocument(
  id: id ?? _eventId('a'),
  data: {
    'schemaVersion': 1,
    'sourceType': 'task',
    'sourceID': 'task-1',
    'sourceRevision': 2,
    'action': 'taskAccepted',
    'actorID': 'user-b',
    'actorName': 'Alex',
    'targetMemberID': 'user-a',
    'targetMemberName': 'Mingze',
    'requestID': 'request-1',
    'assignmentMode': null,
    'petID': 'pet-1',
    'petName': 'Mochi',
    'taskTitle': 'Evening meal',
    'taskCategory': 'feeding',
    'taskPriority': 'normal',
    'taskDueTime': Timestamp.fromDate(DateTime.utc(2026, 8, 17, 1)),
    'stateAfter': 'claimed',
    'occurredAt': Timestamp.fromDate(DateTime.utc(2026, 8, 17, 1)),
    'recordedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 17, 1, 0, 1)),
    ...overrides,
  },
);

StoredCollaborationEventDocument _v2TaskDocument({
  String? id,
  Map<String, Object?> overrides = const {},
}) => StoredCollaborationEventDocument(
  id: id ?? _eventId('b'),
  data: {
    'schemaVersion': 2,
    'sourceType': 'taskResponsibilityTransfer',
    'sourceID': 'transfer-a',
    'sourceRevision': 1,
    'action': 'taskReassignRequested',
    'actorID': 'user-a',
    'actorName': 'Alex',
    'responsibilityFromID': 'user-a',
    'responsibilityFromName': 'Alex',
    'responsibilityToID': 'user-b',
    'responsibilityToName': 'Blair',
    'handoffCreatorID': null,
    'handoffCreatorName': null,
    'handoffRecipientID': null,
    'handoffRecipientName': null,
    'requestID': 'transfer-a',
    'petID': 'pet-1',
    'petName': 'Mochi',
    'taskTitle': 'Evening meal',
    'taskCategory': 'feeding',
    'taskPriority': 'normal',
    'taskDueTime': Timestamp.fromDate(DateTime.utc(2026, 8, 17, 1)),
    'stateAfter': 'claimed',
    'handoffStatus': null,
    'occurredAt': Timestamp.fromDate(DateTime.utc(2026, 8, 17, 1)),
    'recordedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 17, 1, 0, 1)),
    ...overrides,
  },
);

StoredCollaborationEventDocument _v2HandoffDocument() =>
    StoredCollaborationEventDocument(
      id: _eventId('c'),
      data: {
        'schemaVersion': 2,
        'sourceType': 'handoffSession',
        'sourceID': 'session-a',
        'sourceRevision': 1,
        'action': 'handoffOffered',
        'actorID': 'user-a',
        'actorName': 'Alex',
        'responsibilityFromID': null,
        'responsibilityFromName': null,
        'responsibilityToID': null,
        'responsibilityToName': null,
        'handoffCreatorID': 'user-a',
        'handoffCreatorName': 'Alex',
        'handoffRecipientID': 'user-b',
        'handoffRecipientName': 'Blair',
        'requestID': null,
        'petID': null,
        'petName': null,
        'taskTitle': null,
        'taskCategory': null,
        'taskPriority': null,
        'taskDueTime': null,
        'stateAfter': null,
        'handoffStatus': 'offered',
        'occurredAt': Timestamp.fromDate(DateTime.utc(2026, 8, 17, 1)),
        'recordedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 17, 1, 0, 1)),
      },
    );

CollaborationEvent _event({required String id, required DateTime occurredAt}) =>
    CollaborationEvent(
      id: id,
      sourceId: 'task-1',
      sourceRevision: 1,
      action: CollaborationEventAction.taskClaimed,
      actorId: 'user-a',
      actorNameSnapshot: 'Mingze',
      targetMemberId: null,
      targetMemberNameSnapshot: null,
      requestId: null,
      assignmentMode: null,
      petId: 'pet-1',
      petNameSnapshot: 'Mochi',
      taskTitleSnapshot: 'Evening meal',
      taskCategorySnapshot: 'feeding',
      taskPrioritySnapshot: 'normal',
      taskDueTime: occurredAt,
      stateAfter: CollaborationTaskState.claimed,
      occurredAt: occurredAt,
      recordedAt: occurredAt,
    );

String _eventId(String character) => List.filled(64, character).join();
