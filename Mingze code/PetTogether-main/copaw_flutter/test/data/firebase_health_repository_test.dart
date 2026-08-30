import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:copaw_flutter/src/data/firebase_health_repository.dart';
import 'package:copaw_flutter/src/data/health_gateway.dart';
import 'package:copaw_flutter/src/data/health_mutation_store.dart';
import 'package:copaw_flutter/src/data/health_repository.dart';
import 'package:copaw_flutter/src/domain/health_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'pending record stays hidden until acknowledged metadata arrives',
    () async {
      final gateway = _Gateway();
      final repository = FirebaseHealthRepository(
        gateway: gateway,
        mutationStore: _Store(),
      );
      final snapshots = <HealthSnapshot>[];
      final subscription = repository
          .observeHealth('home-1')
          .listen(snapshots.add);
      await Future<void>.delayed(Duration.zero);

      gateway.add([_document(pending: true)], isFromCache: true);
      gateway.add([
        _document(
          overrides: {
            'recordedAt': Timestamp.fromDate(
              DateTime.utc(2026, 8, 13, 8, 0, 1),
            ),
          },
        ),
      ], isFromCache: false);
      await Future<void>.delayed(Duration.zero);

      expect(snapshots, hasLength(2));
      expect(snapshots.first.records, isEmpty);
      expect(snapshots.first.isFromCache, true);
      expect(snapshots.last.records.single.id, 'health-1');
      expect(snapshots.last.isFromCache, false);
      await subscription.cancel();
      expect(gateway.cancelledListeners, 1);
    },
  );

  test('listener replacement cancels the previous source', () async {
    final gateway = _Gateway();
    final repository = FirebaseHealthRepository(
      gateway: gateway,
      mutationStore: _Store(),
    );
    final first = repository.observeHealth('home-1').listen((_) {});
    await Future<void>.delayed(Duration.zero);
    final second = repository.observeHealth('home-2').listen((_) {});
    await Future<void>.delayed(Duration.zero);

    expect(gateway.observedHouseholds, ['home-1', 'home-2']);
    expect(gateway.cancelledListeners, 1);
    await first.cancel();
    await second.cancel();
    expect(gateway.cancelledListeners, 2);
  });

  test(
    'malformed facts are isolated and counted without hiding valid facts',
    () async {
      final gateway = _Gateway();
      final repository = FirebaseHealthRepository(
        gateway: gateway,
        mutationStore: _Store(),
      );
      final result = repository.observeHealth('home-1').first;
      await Future<void>.delayed(Duration.zero);

      gateway.add([
        _document(),
        _document(overrides: {'schemaVersion': 99}),
      ]);

      final snapshot = await result;
      expect(snapshot.records, hasLength(1));
      expect(snapshot.droppedRecordCount, 1);
    },
  );

  test(
    'create validates structured fields and sends a canonical command',
    () async {
      final gateway = _Gateway();
      final repository = FirebaseHealthRepository(
        gateway: gateway,
        mutationStore: _Store(),
      );
      final recordedAt = DateTime.now().subtract(const Duration(minutes: 1));

      await repository.createRecord(
        householdId: 'home-1',
        petId: 'pet-1',
        petName: ' Mochi ',
        type: HealthRecordType.weight,
        recordedAt: recordedAt,
        timeZoneIdentifier: 'Asia/Tokyo',
        detail: ' routine ',
        weightKilograms: 4.2,
        createdById: 'user-1',
        createdByName: ' Alex ',
      );

      final command = gateway.created.single;
      expect(command.recordId, 'health-new');
      expect(command.detail, 'routine');
      expect(command.petId, 'pet-1');

      await expectLater(
        repository.createRecord(
          householdId: 'home-1',
          petId: 'pet-1',
          petName: 'Mochi',
          type: HealthRecordType.symptom,
          recordedAt: recordedAt,
          timeZoneIdentifier: 'Asia/Tokyo',
          detail: '',
          weightKilograms: null,
          createdById: 'user-1',
          createdByName: 'Alex',
        ),
        throwsA(isA<HealthRepositoryException>()),
      );
    },
  );

  test(
    'ambiguous retry reuses the same record ID across repository restart',
    () async {
      final store = _Store();
      final firstGateway = _Gateway(failCreate: true);
      final first = FirebaseHealthRepository(
        gateway: firstGateway,
        mutationStore: store,
      );
      final recordedAt = DateTime.now().subtract(const Duration(minutes: 1));

      await expectLater(
        _createNote(first, recordedAt),
        throwsA(isA<HealthRepositoryException>()),
      );
      final secondGateway = _Gateway();
      final second = FirebaseHealthRepository(
        gateway: secondGateway,
        mutationStore: store,
      );
      await _createNote(second, recordedAt);

      expect(firstGateway.created.single.recordId, 'health-new');
      expect(secondGateway.created.single.recordId, 'health-new');
      expect(store.values, isEmpty);
    },
  );

  test('water intake is numeric and remains distinct from notes', () async {
    final gateway = _Gateway();
    final repository = FirebaseHealthRepository(
      gateway: gateway,
      mutationStore: _Store(),
    );

    await repository.createRecord(
      householdId: 'home-1',
      petId: 'pet-1',
      petName: 'Mochi',
      type: HealthRecordType.waterIntake,
      recordedAt: DateTime.now().subtract(const Duration(minutes: 1)),
      timeZoneIdentifier: 'Asia/Tokyo',
      detail: '一日の合計',
      weightKilograms: null,
      waterMilliliters: 420,
      createdById: 'user-1',
      createdByName: 'Alex',
    );

    expect(gateway.created.single.waterMilliliters, 420);
    expect(gateway.created.single.weightKilograms, isNull);
  });

  test('decodes server-authored v2 local date and water basis', () async {
    final gateway = _Gateway();
    final repository = FirebaseHealthRepository(
      gateway: gateway,
      mutationStore: _Store(),
    );
    final result = repository.observeHealth('home-1').first;
    await Future<void>.delayed(Duration.zero);
    gateway.add([
      _document(
        overrides: {
          'schemaVersion': 2,
          'type': 'waterIntake',
          'weightKilograms': null,
          'waterMilliliters': 120,
          'waterMeasurementBasis': 'singleIntake',
          'recordedLocalDate': '2026-08-13',
          'recordedTimeZoneIdentifier': 'Asia/Tokyo',
        },
      ),
    ]);

    final record = (await result).records.single;
    expect(record.recordedLocalDate, '2026-08-13');
    expect(record.recordedTimeZoneIdentifier, 'Asia/Tokyo');
    expect(record.waterMeasurementBasis, WaterMeasurementBasis.singleIntake);
  });

  test('decodes the reserved reviewed full-day water basis', () async {
    final gateway = _Gateway();
    final repository = FirebaseHealthRepository(
      gateway: gateway,
      mutationStore: _Store(),
    );
    final result = repository.observeHealth('home-1').first;
    await Future<void>.delayed(Duration.zero);
    gateway.add([
      _document(
        overrides: {
          'schemaVersion': 2,
          'type': 'waterIntake',
          'weightKilograms': null,
          'waterMilliliters': 500,
          'waterMeasurementBasis': 'fullLocalDay',
          'recordedLocalDate': '2026-08-13',
          'recordedTimeZoneIdentifier': 'Asia/Tokyo',
        },
      ),
    ]);

    expect(
      (await result).records.single.waterMeasurementBasis,
      WaterMeasurementBasis.fullLocalDay,
    );
  });

  test(
    'daily check-in keeps qualitative levels and optional measured water',
    () async {
      final gateway = _Gateway();
      final repository = FirebaseHealthRepository(
        gateway: gateway,
        mutationStore: _Store(),
      );
      const checkIn = DailyHealthCheckIn(
        water: DailyHealthLevel.usual,
        appetite: DailyHealthLevel.lessThanUsual,
        urination: DailyHealthLevel.usual,
        stool: DailyHealthStatus.changed,
        energy: DailyHealthLevel.lessThanUsual,
        mood: DailyHealthStatus.usual,
      );

      await repository.createRecord(
        householdId: 'home-1',
        petId: 'pet-1',
        petName: 'Mochi',
        type: HealthRecordType.dailyCheckIn,
        recordedAt: DateTime.now().subtract(const Duration(minutes: 1)),
        timeZoneIdentifier: 'Asia/Tokyo',
        detail: 'Quieter after the walk',
        weightKilograms: null,
        waterMilliliters: 510,
        dailyCheckIn: checkIn,
        createdById: 'user-1',
        createdByName: 'Alex',
      );

      final payload = gateway.dailyCalls.single;
      expect(payload['waterLevel'], 'usual');
      expect(payload['appetiteLevel'], 'lessThanUsual');
      expect(payload['stoolStatus'], 'changed');
      expect(payload['waterMilliliters'], 510);

      final decoded = repository.observeHealth('home-1').first;
      await Future<void>.delayed(Duration.zero);
      gateway.add([
        _document(
          overrides: {
            'type': 'dailyCheckIn',
            'detail': 'Quieter after the walk',
            'weightKilograms': null,
            'waterMilliliters': 510,
            'waterLevel': 'usual',
            'appetiteLevel': 'lessThanUsual',
            'urinationLevel': 'usual',
            'stoolStatus': 'changed',
            'energyLevel': 'lessThanUsual',
            'moodStatus': 'usual',
          },
        ),
      ]);
      final record = (await decoded).records.single;
      expect(record.dailyCheckIn?.appetite, DailyHealthLevel.lessThanUsual);
      expect(record.dailyCheckIn?.stool, DailyHealthStatus.changed);
    },
  );
}

final class _Gateway implements HealthGateway {
  _Gateway({this.failCreate = false});

  final bool failCreate;
  final _controller = StreamController<StoredHealthSnapshot>.broadcast(
    onCancel: null,
  );
  final observedHouseholds = <String>[];
  final created = <CreateHealthRecordCommand>[];
  final dailyCalls = <Map<String, Object?>>[];
  int cancelledListeners = 0;

  @override
  Stream<StoredHealthSnapshot> observeHealth(String householdId) {
    observedHouseholds.add(householdId);
    return _controller.stream.doOnCancel(() => cancelledListeners += 1);
  }

  void add(List<StoredHealthDocument> documents, {bool isFromCache = false}) {
    _controller.add(
      StoredHealthSnapshot(documents: documents, isFromCache: isFromCache),
    );
  }

  @override
  String newRecordId(String householdId) => 'health-new';

  @override
  Future<void> createRecord(CreateHealthRecordCommand command) async {
    created.add(command);
    if (failCreate) throw StateError('ambiguous');
  }

  @override
  Future<Map<String, Object?>> createDailyCheckIn(
    Map<String, Object?> payload,
  ) async {
    dailyCalls.add(payload);
    return {'recordID': 'daily-record', 'created': true};
  }
}

final class _Store implements HealthMutationStore {
  final values = <String, String>{};

  @override
  Future<String> readOrCreate(
    String requestHash,
    String Function() createRecordId,
  ) async => values.putIfAbsent(requestHash, createRecordId);

  @override
  Future<void> clear(String requestHash) async {
    values.remove(requestHash);
  }
}

Future<void> _createNote(
  FirebaseHealthRepository repository,
  DateTime recordedAt,
) => repository.createRecord(
  householdId: 'home-1',
  petId: 'pet-1',
  petName: 'Mochi',
  type: HealthRecordType.note,
  recordedAt: recordedAt,
  timeZoneIdentifier: 'Asia/Tokyo',
  detail: 'Observation',
  weightKilograms: null,
  createdById: 'user-1',
  createdByName: 'Alex',
);

extension<T> on Stream<T> {
  Stream<T> doOnCancel(void Function() action) {
    late final StreamController<T> controller;
    StreamSubscription<T>? subscription;
    controller = StreamController<T>(
      onListen: () {
        subscription = listen(controller.add, onError: controller.addError);
      },
      onCancel: () async {
        action();
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }
}

StoredHealthDocument _document({
  bool pending = false,
  Map<String, Object?> overrides = const {},
}) {
  final created = DateTime.utc(2026, 8, 13, 8);
  return StoredHealthDocument(
    id: 'health-1',
    hasPendingWrites: pending,
    data: {
      'schemaVersion': 1,
      'petID': 'pet-1',
      'petName': 'Mochi',
      'type': 'weight',
      'recordedAt': Timestamp.fromDate(created),
      'detail': null,
      'weightKilograms': 4.2,
      'createdByID': 'user-1',
      'createdByName': 'Alex',
      'createdAt': Timestamp.fromDate(created),
      ...overrides,
    },
  );
}
