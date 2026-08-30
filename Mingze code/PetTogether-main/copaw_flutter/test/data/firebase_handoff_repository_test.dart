import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:copaw_flutter/src/data/firebase_handoff_repository.dart';
import 'package:copaw_flutter/src/data/handoff_gateway.dart';
import 'package:copaw_flutter/src/data/handoff_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes current handoff and preserves cache metadata', () async {
    final gateway = _Gateway();
    final repository = FirebaseHandoffRepository(gateway: gateway);
    final snapshotFuture = repository.observeHandoff('home-1').first;
    await Future<void>.delayed(Duration.zero);

    gateway.add(_document(isFromCache: true, hasPendingWrites: true));
    final snapshot = await snapshotFuture;

    expect(snapshot.handoff?.revision, 2);
    expect(snapshot.handoff?.emergencyContactName, 'Sam');
    expect(snapshot.isFromCache, true);
    expect(snapshot.hasPendingWrites, true);
    expect(gateway.cancelledListeners, 1);
  });

  test(
    'listener replacement cancels old source and missing is empty',
    () async {
      final gateway = _Gateway();
      final repository = FirebaseHandoffRepository(gateway: gateway);
      final first = repository.observeHandoff('home-1').listen((_) {});
      await Future<void>.delayed(Duration.zero);
      final emptyFuture = repository.observeHandoff('home-2').first;
      await Future<void>.delayed(Duration.zero);
      gateway.add(
        const StoredHandoffDocument(
          exists: false,
          data: {},
          isFromCache: false,
          hasPendingWrites: false,
        ),
      );

      expect((await emptyFuture).handoff, isNull);
      expect(gateway.observedHouseholds, ['home-1', 'home-2']);
      expect(gateway.cancelledListeners, 2);
      await first.cancel();
    },
  );

  test('malformed handoff surfaces safe data error', () async {
    final gateway = _Gateway();
    final repository = FirebaseHandoffRepository(gateway: gateway);
    final error = repository
        .observeHandoff('home-1')
        .first
        .then<Object?>((_) => null, onError: (Object value) => value);
    await Future<void>.delayed(Duration.zero);
    gateway.add(_document(overrides: {'revision': 0}));

    expect(
      await error,
      isA<HandoffRepositoryException>().having(
        (value) => value.code,
        'code',
        HandoffRepositoryErrorCode.malformedData,
      ),
    );
  });

  test('save validates limits and sends normalized command', () async {
    final gateway = _Gateway();
    final repository = FirebaseHandoffRepository(gateway: gateway);

    await repository.saveHandoff(
      householdId: 'home-1',
      expectedRevision: 2,
      careInstructions: ' Dinner at 18:00 ',
      emergencyContactName: ' Sam ',
      emergencyContactPhone: ' 090-0000-0000 ',
      veterinaryHospitalName: ' Central Animal Hospital ',
      veterinaryHospitalPhone: ' 03-0000-0000 ',
      updatedById: 'user-1',
      updatedByName: ' Alex ',
    );

    expect(gateway.saved.single.careInstructions, 'Dinner at 18:00');
    expect(gateway.saved.single.expectedRevision, 2);
    expect(gateway.saved.single.updatedByName, 'Alex');
    await expectLater(
      repository.saveHandoff(
        householdId: 'home-1',
        expectedRevision: null,
        careInstructions: List.filled(1001, 'x').join(),
        emergencyContactName: '',
        emergencyContactPhone: '',
        veterinaryHospitalName: '',
        veterinaryHospitalPhone: '',
        updatedById: 'user-1',
        updatedByName: 'Alex',
      ),
      throwsA(
        isA<HandoffRepositoryException>().having(
          (value) => value.code,
          'code',
          HandoffRepositoryErrorCode.invalidInput,
        ),
      ),
    );
  });

  test('stale expected revision surfaces a conflict', () async {
    final repository = FirebaseHandoffRepository(
      gateway: _Gateway(saveError: const HandoffRevisionConflict()),
    );

    await expectLater(
      repository.saveHandoff(
        householdId: 'home-1',
        expectedRevision: 1,
        careInstructions: 'Dinner at 18:00',
        emergencyContactName: '',
        emergencyContactPhone: '',
        veterinaryHospitalName: '',
        veterinaryHospitalPhone: '',
        updatedById: 'user-1',
        updatedByName: 'Alex',
      ),
      throwsA(
        isA<HandoffRepositoryException>().having(
          (value) => value.code,
          'code',
          HandoffRepositoryErrorCode.conflict,
        ),
      ),
    );
  });
}

final class _Gateway implements HandoffGateway {
  _Gateway({this.saveError});

  final Object? saveError;
  StreamController<StoredHandoffDocument>? controller;
  final observedHouseholds = <String>[];
  final saved = <SaveHandoffCommand>[];
  int cancelledListeners = 0;

  void add(StoredHandoffDocument document) => controller!.add(document);

  @override
  Stream<StoredHandoffDocument> observeHandoff(String householdId) {
    observedHouseholds.add(householdId);
    controller = StreamController<StoredHandoffDocument>(
      onCancel: () => cancelledListeners += 1,
    );
    return controller!.stream;
  }

  @override
  Future<void> saveHandoff(SaveHandoffCommand command) async {
    if (saveError case final error?) throw error;
    saved.add(command);
  }
}

StoredHandoffDocument _document({
  bool isFromCache = false,
  bool hasPendingWrites = false,
  Map<String, Object?> overrides = const {},
}) => StoredHandoffDocument(
  exists: true,
  isFromCache: isFromCache,
  hasPendingWrites: hasPendingWrites,
  data: {
    'schemaVersion': 1,
    'careInstructions': 'Dinner at 18:00',
    'emergencyContactName': 'Sam',
    'emergencyContactPhone': '090-0000-0000',
    'veterinaryHospitalName': 'Central Animal Hospital',
    'veterinaryHospitalPhone': '03-0000-0000',
    'revision': 2,
    'updatedByID': 'user-2',
    'updatedByName': 'Sam',
    'updatedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 13, 8)),
    ...overrides,
  },
);
