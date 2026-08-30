import 'package:cloud_functions/cloud_functions.dart';
import 'package:copaw_flutter/src/data/firebase_medication_repository.dart';
import 'package:copaw_flutter/src/data/medication_gateway.dart';
import 'package:copaw_flutter/src/data/medication_mutation_store.dart';
import 'package:copaw_flutter/src/data/medication_repository.dart';
import 'package:copaw_flutter/src/domain/medication_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cache and pending writes are never server-confirmed', () async {
    final gateway = _Gateway(
      snapshot: const MedicationGatewaySnapshot(
        medications: [],
        schedules: [],
        occurrences: [],
        isFromCache: false,
        hasPendingWrites: true,
      ),
    );
    final repository = FirebaseMedicationRepository(
      gateway: gateway,
      mutationStore: _MutationStore(),
    );

    final snapshot = await repository.observeMedication('home-1').first;

    expect(snapshot.isServerConfirmed, isFalse);
  });

  test('medication profile fields are normalized into the callable', () async {
    final gateway = _Gateway();
    final repository = FirebaseMedicationRepository(
      gateway: gateway,
      mutationStore: _MutationStore(),
    );

    await repository.createPlan(
      householdId: 'home-1',
      petId: 'pet-1',
      medicationName: '  ハートケア錠  ',
      purpose: '  処方理由  ',
      possibleSideEffects: '  観察事項  ',
      effectiveFromLocalDate: '2026-08-13',
      weekdays: const [1],
      slots: const [
        MedicationPlanSlotInput(hour: 8, minute: 0, doseText: '1錠'),
      ],
    );

    expect(gateway.calls.single['medicationName'], 'ハートケア錠');
    expect(gateway.calls.single['purpose'], '処方理由');
    expect(gateway.calls.single['possibleSideEffects'], '観察事項');
  });

  test('occurrence time accepts the same instant in local form', () async {
    final dueAtUtc = DateTime.parse('2026-08-12T23:00:00Z');
    final dueAtLocal = DateTime.fromMillisecondsSinceEpoch(
      dueAtUtc.millisecondsSinceEpoch,
    );
    final repository = FirebaseMedicationRepository(
      gateway: _Gateway(
        snapshot: MedicationGatewaySnapshot(
          medications: const [
            MedicationStoredDocument(
              id: 'med-1',
              data: {
                'id': 'med-1',
                'petID': 'pet-1',
                'displayName': 'Tablet A',
                'purpose': 'Prescription record',
                'possibleSideEffects': 'Watch appetite',
                'isActive': true,
                'currentScheduleVersion': 1,
                'currentScheduleVersionID': 'v000001',
                'revision': 0,
              },
            ),
          ],
          schedules: const [
            MedicationStoredDocument(
              id: 'v000001',
              data: {
                'id': 'v000001',
                'medicationID': 'med-1',
                'version': 1,
                'petID': 'pet-1',
                'petName': 'Mochi',
                'medicationName': 'Tablet A',
                'weekdays': [1, 2, 3, 4, 5, 6, 7],
                'slots': [
                  {
                    'slotID': '0800',
                    'hour': 8,
                    'minute': 0,
                    'doseText': '1 tablet',
                    'instructions': null,
                  },
                ],
                'timeZoneIdentifier': 'Asia/Tokyo',
                'effectiveFromLocalDate': '2026-08-13',
                'effectiveUntilLocalDate': null,
              },
            ),
          ],
          occurrences: [
            MedicationStoredDocument(
              id: 'med-1_v000001_2026-08-13_0800',
              data: {
                'id': 'med-1_v000001_2026-08-13_0800',
                'medicationID': 'med-1',
                'scheduleVersionID': 'v000001',
                'scheduleVersion': 1,
                'slotID': '0800',
                'localDate': '2026-08-13',
                'dueAt': dueAtLocal,
                'petID': 'pet-1',
                'petName': 'Mochi',
                'medicationName': 'Tablet A',
                'doseText': '1 tablet',
                'instructions': null,
                'responsibilityStatus': 'unclaimed',
                'responsibleByID': null,
                'responsibleByName': null,
                'claimedAt': null,
                'outcomeStatus': 'unresolved',
                'outcomeByID': null,
                'outcomeByName': null,
                'outcomeAt': null,
                'skippedReasonCode': null,
                'skippedReasonNote': null,
                'revision': 0,
              },
            ),
          ],
          isFromCache: false,
          hasPendingWrites: false,
        ),
      ),
      mutationStore: _MutationStore(),
    );

    final snapshot = await repository.observeMedication('home-1').first;

    expect(snapshot.medications.single.purpose, 'Prescription record');
    expect(snapshot.medications.single.possibleSideEffects, 'Watch appetite');
    expect(snapshot.occurrences.single.dueAt.isAtSameMomentAs(dueAtUtc), true);
  });

  test('responsibility and terminal conflicts remain distinct', () async {
    final responsibility = FirebaseMedicationRepository(
      gateway: _Gateway(
        callError: FirebaseFunctionsException(
          code: 'already-exists',
          message: 'claimed',
          details: const {'responsibleByName': 'Alex'},
        ),
      ),
      mutationStore: _MutationStore(),
    );
    final terminal = FirebaseMedicationRepository(
      gateway: _Gateway(
        callError: FirebaseFunctionsException(
          code: 'already-exists',
          message: 'terminal',
          details: const {'outcomeStatus': 'skipped'},
        ),
      ),
      mutationStore: _MutationStore(),
    );

    await expectLater(
      responsibility.claim(householdId: 'home-1', occurrence: _planned()),
      throwsA(
        isA<MedicationRepositoryException>().having(
          (error) => error.code,
          'code',
          MedicationRepositoryErrorCode.responsibilityConflict,
        ),
      ),
    );
    await expectLater(
      terminal.administer(householdId: 'home-1', occurrence: _planned()),
      throwsA(
        isA<MedicationRepositoryException>().having(
          (error) => error.code,
          'code',
          MedicationRepositoryErrorCode.terminalConflict,
        ),
      ),
    );
  });

  test('ambiguous network retry reuses the mutation ID and payload', () async {
    final gateway = _Gateway(failFirstCall: true);
    final repository = FirebaseMedicationRepository(
      gateway: gateway,
      mutationStore: _MutationStore(),
    );

    await expectLater(
      repository.administer(householdId: 'home-1', occurrence: _planned()),
      throwsA(
        isA<MedicationRepositoryException>().having(
          (error) => error.code,
          'code',
          MedicationRepositoryErrorCode.network,
        ),
      ),
    );
    await repository.administer(householdId: 'home-1', occurrence: _planned());

    expect(gateway.calls, hasLength(2));
    expect(
      gateway.calls.first['clientMutationID'],
      gateway.calls.last['clientMutationID'],
    );
    expect(gateway.calls.first, gateway.calls.last);
  });

  test('ambiguous retry survives restart without persisting content', () async {
    final store = _MutationStore();
    final firstGateway = _Gateway(failFirstCall: true);
    final firstRepository = FirebaseMedicationRepository(
      gateway: firstGateway,
      mutationStore: store,
    );

    await expectLater(
      firstRepository.createPlan(
        householdId: 'home-1',
        petId: 'pet-1',
        medicationName: 'Private medication',
        effectiveFromLocalDate: '2026-08-13',
        weekdays: const [1],
        slots: const [
          MedicationPlanSlotInput(hour: 8, minute: 0, doseText: 'Private dose'),
        ],
      ),
      throwsA(
        isA<MedicationRepositoryException>().having(
          (error) => error.code,
          'code',
          MedicationRepositoryErrorCode.network,
        ),
      ),
    );
    final pendingId = firstGateway.calls.single['clientMutationID'];
    expect(store.values, hasLength(1));
    expect(store.values.keys.single, hasLength(64));
    expect(store.values.keys.single, isNot(contains('Private')));

    final secondGateway = _Gateway();
    final secondRepository = FirebaseMedicationRepository(
      gateway: secondGateway,
      mutationStore: store,
    );
    await secondRepository.createPlan(
      householdId: 'home-1',
      petId: 'pet-1',
      medicationName: 'Private medication',
      effectiveFromLocalDate: '2026-08-13',
      weekdays: const [1],
      slots: const [
        MedicationPlanSlotInput(hour: 8, minute: 0, doseText: 'Private dose'),
      ],
    );

    expect(secondGateway.calls.single['clientMutationID'], pendingId);
    expect(store.values, isEmpty);
  });

  test(
    'request fingerprints cannot collide through value separators',
    () async {
      final store = _MutationStore();
      final firstRepository = FirebaseMedicationRepository(
        gateway: _Gateway(failFirstCall: true),
        mutationStore: store,
      );
      final secondRepository = FirebaseMedicationRepository(
        gateway: _Gateway(failFirstCall: true),
        mutationStore: store,
      );

      Future<void> create(
        FirebaseMedicationRepository repository, {
        required String medicationName,
        required String petId,
      }) async {
        await expectLater(
          repository.createPlan(
            householdId: 'home-1',
            petId: petId,
            medicationName: medicationName,
            effectiveFromLocalDate: '2026-08-13',
            weekdays: const [1],
            slots: const [
              MedicationPlanSlotInput(hour: 8, minute: 0, doseText: '1 tablet'),
            ],
          ),
          throwsA(isA<MedicationRepositoryException>()),
        );
      }

      await create(
        firstRepository,
        medicationName: 'Tablet&petID=pet-b',
        petId: 'pet-c',
      );
      await create(
        secondRepository,
        medicationName: 'Tablet',
        petId: 'pet-b&petID=pet-c',
      );

      expect(store.values, hasLength(2));
      expect(store.values.values.toSet(), hasLength(2));
    },
  );

  test('parallel repository instances share one pending mutation ID', () async {
    final store = _MutationStore();
    final firstGateway = _Gateway(failFirstCall: true);
    final secondGateway = _Gateway(failFirstCall: true);
    final repositories = [
      FirebaseMedicationRepository(gateway: firstGateway, mutationStore: store),
      FirebaseMedicationRepository(
        gateway: secondGateway,
        mutationStore: store,
      ),
    ];

    await Future.wait(
      repositories.map(
        (repository) => expectLater(
          repository.administer(householdId: 'home-1', occurrence: _planned()),
          throwsA(isA<MedicationRepositoryException>()),
        ),
      ),
    );

    expect(
      firstGateway.calls.single['clientMutationID'],
      secondGateway.calls.single['clientMutationID'],
    );
    expect(store.values, hasLength(1));
  });

  test('stopping observation delegates listener cleanup', () async {
    final gateway = _Gateway();
    final repository = FirebaseMedicationRepository(
      gateway: gateway,
      mutationStore: _MutationStore(),
    );

    await repository.stopObserving();

    expect(gateway.stopCalls, 1);
  });

  test('malformed terminal state is rejected instead of displayed', () async {
    final gateway = _Gateway(
      snapshot: MedicationGatewaySnapshot(
        medications: const [],
        schedules: const [],
        occurrences: [
          MedicationStoredDocument(
            id: 'med-1_v000001_2026-08-13_0800',
            data: {
              'id': 'med-1_v000001_2026-08-13_0800',
              'medicationID': 'med-1',
              'scheduleVersionID': 'v000001',
              'scheduleVersion': 1,
              'slotID': '0800',
              'localDate': '2026-08-13',
              'dueAt': DateTime.parse('2026-08-12T23:00:00Z'),
              'petID': 'pet-1',
              'petName': 'Mochi',
              'medicationName': 'Tablet A',
              'doseText': '1 tablet',
              'instructions': null,
              'responsibilityStatus': 'unclaimed',
              'responsibleByID': null,
              'responsibleByName': null,
              'claimedAt': null,
              'outcomeStatus': 'administered',
              'outcomeByID': null,
              'outcomeByName': null,
              'outcomeAt': null,
              'skippedReasonCode': null,
              'skippedReasonNote': null,
              'revision': 1,
            },
          ),
        ],
        isFromCache: false,
        hasPendingWrites: false,
      ),
    );
    final repository = FirebaseMedicationRepository(
      gateway: gateway,
      mutationStore: _MutationStore(),
    );

    await expectLater(
      repository.observeMedication('home-1').first,
      throwsA(
        isA<MedicationRepositoryException>().having(
          (error) => error.code,
          'code',
          MedicationRepositoryErrorCode.malformedData,
        ),
      ),
    );
  });
}

final class _Gateway implements MedicationGateway {
  _Gateway({this.snapshot, this.callError, this.failFirstCall = false});

  final MedicationGatewaySnapshot? snapshot;
  final Object? callError;
  final bool failFirstCall;
  final calls = <Map<String, Object?>>[];
  int stopCalls = 0;

  @override
  Stream<MedicationGatewaySnapshot> observe(String householdId) => Stream.value(
    snapshot ??
        const MedicationGatewaySnapshot(
          medications: [],
          schedules: [],
          occurrences: [],
          isFromCache: false,
          hasPendingWrites: false,
        ),
  );

  @override
  Future<Map<String, Object?>> call(
    String name,
    Map<String, Object?> payload,
  ) async {
    calls.add(Map.of(payload));
    if (callError case final Object error) throw error;
    if (failFirstCall && calls.length == 1) {
      throw FirebaseFunctionsException(code: 'unavailable', message: 'offline');
    }
    return const {'confirmed': true, 'medicationID': 'med-1'};
  }

  @override
  Future<void> stopObserving() async {
    stopCalls += 1;
  }
}

final class _MutationStore implements MedicationMutationStore {
  final values = <String, String>{};

  @override
  Future<String> readOrCreate(
    String requestHash,
    String Function() createMutationId,
  ) async {
    return values.putIfAbsent(requestHash, createMutationId);
  }

  @override
  Future<void> clear(String requestHash) async {
    values.remove(requestHash);
  }
}

PlannedMedicationOccurrence _planned() => PlannedMedicationOccurrence(
  id: 'med-1_v000001_2026-08-13_0800',
  medicationId: 'med-1',
  scheduleVersionId: 'v000001',
  scheduleVersion: 1,
  slotId: '0800',
  localDate: '2026-08-13',
  dueAt: DateTime.parse('2026-08-12T23:00:00Z'),
  petId: 'pet-1',
  petNameSnapshot: 'Mochi',
  medicationNameSnapshot: 'Tablet A',
  doseText: '1 tablet',
  instructions: null,
  persisted: null,
);
