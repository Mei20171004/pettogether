import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:copaw_flutter/src/data/active_household_store.dart';
import 'package:copaw_flutter/src/data/firebase_household_repository.dart';
import 'package:copaw_flutter/src/data/household_data_gateway.dart';
import 'package:copaw_flutter/src/data/household_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeHouseholdDataGateway gateway;
  late FakeActiveHouseholdStore activeStore;
  late SequenceInviteCodeGenerator codeGenerator;
  late FakePendingHouseholdStore pendingStore;
  late FirebaseHouseholdRepository repository;

  setUp(() {
    gateway = FakeHouseholdDataGateway();
    activeStore = FakeActiveHouseholdStore();
    codeGenerator = SequenceInviteCodeGenerator(['ABC234', 'DEF567']);
    pendingStore = FakePendingHouseholdStore();
    repository = FirebaseHouseholdRepository(
      gateway: gateway,
      activeHouseholdStore: activeStore,
      pendingHouseholdStore: pendingStore,
      inviteCodeGenerator: codeGenerator,
    );
  });

  test(
    'create emits one atomic command and retries invite collision',
    () async {
      gateway.createOutcomes.addAll([const InviteCodeCollision(), null]);

      final session = await repository.createHousehold(
        householdName: 'Family',
        petName: 'Pet',
        caregiverName: 'Caregiver',
        timeZoneIdentifier: 'Asia/Tokyo',
      );

      expect(gateway.createCommands, hasLength(2));
      expect(gateway.createCommands.map((item) => item.inviteCode), [
        'ABC234',
        'DEF567',
      ]);
      expect(
        gateway.createCommands
            .singleWhere((item) => item.inviteCode == 'DEF567')
            .ownerId,
        'user-1',
      );
      expect(session.household.inviteCode, 'DEF567');
      expect(activeStore.value, 'household-1');
    },
  );

  test('join normalizes code and passes one atomic join command', () async {
    gateway.joinResult = JoinHouseholdResult(
      householdId: 'household-1',
      returningMember: false,
    );
    gateway.householdDocument = _householdDocument(inviteCode: 'ABC234');

    final session = await repository.joinHousehold(
      inviteCode: ' abc234 ',
      caregiverName: 'Caregiver',
    );

    expect(gateway.joinCommands, hasLength(1));
    expect(gateway.joinCommands.single.inviteCode, 'ABC234');
    expect(gateway.joinCommands.single.userId, 'user-1');
    expect(session.household.id, 'household-1');
    expect(activeStore.value, 'household-1');
  });

  test(
    'join forwards a legacy six-character code containing 0 1 I O',
    () async {
      gateway.joinResult = JoinHouseholdResult(
        householdId: 'household-1',
        returningMember: false,
      );
      gateway.householdDocument = _householdDocument(inviteCode: 'I0O1A2');

      await repository.joinHousehold(
        inviteCode: 'i0o1a2',
        caregiverName: 'Caregiver',
      );

      expect(gateway.joinCommands.single.inviteCode, 'I0O1A2');
    },
  );

  test('rejoin retains gateway returning-member semantics', () async {
    gateway.joinResult = JoinHouseholdResult(
      householdId: 'household-1',
      returningMember: true,
    );
    gateway.householdDocument = _householdDocument(inviteCode: 'ABC234');

    await repository.joinHousehold(
      inviteCode: 'ABC234',
      caregiverName: 'Updated caregiver',
    );

    expect(gateway.joinCommands.single.caregiverName, 'Updated caregiver');
    expect(gateway.joinResult?.returningMember, isTrue);
  });

  test('restore missing member clears stale local session', () async {
    activeStore.value = 'household-1';
    gateway.householdDocument = _householdDocument(inviteCode: 'ABC234');
    gateway.memberDocument = const StoredDocument(id: 'user-1', exists: false);

    expect(await repository.restoreSession(), isNull);
    expect(activeStore.value, isNull);
    expect(activeStore.clears, 1);
    expect(gateway.reads, ['member']);
  });

  test(
    'restore without local or pending session does not authenticate',
    () async {
      expect(await repository.restoreSession(), isNull);
      expect(gateway.authCalls, 0);
    },
  );

  test('restore decodes valid household and member', () async {
    final joinedAt = DateTime.utc(2026, 8, 1, 2, 3);
    activeStore.value = 'household-1';
    gateway.householdDocument = _householdDocument(inviteCode: 'ABC234');
    gateway.memberDocument = StoredDocument(
      id: 'user-1',
      exists: true,
      data: {
        'displayName': 'Caregiver',
        'joinedAt': Timestamp.fromDate(joinedAt),
      },
    );

    final session = await repository.restoreSession();

    expect(session?.household.id, 'household-1');
    expect(session?.caregiver.id, 'user-1');
    expect(session?.memberJoinedAt, joinedAt);
  });

  test('leave clears local session without a remote command', () async {
    activeStore.value = 'household-1';

    await repository.leaveHousehold();

    expect(activeStore.value, isNull);
    expect(activeStore.clears, 1);
    expect(gateway.createCommands, isEmpty);
    expect(gateway.joinCommands, isEmpty);
  });

  test('invalid invite is rejected before auth or gateway access', () async {
    await expectLater(
      repository.joinHousehold(inviteCode: 'BAD!', caregiverName: 'Caregiver'),
      throwsA(
        isA<HouseholdRepositoryException>().having(
          (error) => error.code,
          'code',
          HouseholdRepositoryErrorCode.invalidInviteCode,
        ),
      ),
    );

    expect(gateway.authCalls, 0);
    expect(gateway.joinCommands, isEmpty);
  });

  test('provider permission error maps to a stable category', () async {
    activeStore.value = 'household-1';
    gateway.authError = FirebaseException(
      plugin: 'firebase_auth',
      code: 'permission-denied',
    );

    await expectLater(
      repository.restoreSession(),
      throwsA(
        isA<HouseholdRepositoryException>().having(
          (error) => error.code,
          'code',
          HouseholdRepositoryErrorCode.permission,
        ),
      ),
    );
  });

  test('a local save failure does not repeat a committed household', () async {
    activeStore.saveError = StateError('storage unavailable');

    final session = await repository.createHousehold(
      householdName: 'Family',
      petName: 'Pet',
      caregiverName: 'Caregiver',
      timeZoneIdentifier: 'Asia/Tokyo',
    );

    expect(gateway.createCommands, hasLength(1));
    expect(session.localPersistence, LocalSessionPersistence.unavailable);
    expect(pendingStore.value?.householdId, 'household-1');
  });

  test('pending committed household is reconciled on next restore', () async {
    pendingStore.value = const PendingHouseholdMarker(
      householdId: 'household-1',
      inviteCode: 'ABC234',
    );
    gateway.householdDocument = _householdDocument(inviteCode: 'ABC234');
    gateway.memberDocument = const StoredDocument(
      id: 'user-1',
      exists: true,
      data: {'displayName': 'Caregiver'},
    );

    final session = await repository.restoreSession();

    expect(session?.household.id, 'household-1');
    expect(activeStore.value, 'household-1');
    expect(pendingStore.value, isNull);
  });

  test(
    'persistent active save failure keeps pending recovery marker',
    () async {
      pendingStore.value = const PendingHouseholdMarker(
        householdId: 'household-1',
        inviteCode: 'ABC234',
      );
      activeStore.saveError = StateError('still unavailable');
      gateway.householdDocument = _householdDocument(inviteCode: 'ABC234');
      gateway.memberDocument = const StoredDocument(
        id: 'user-1',
        exists: true,
        data: {'displayName': 'Caregiver'},
      );

      final session = await repository.restoreSession();

      expect(session?.localPersistence, LocalSessionPersistence.unavailable);
      expect(pendingStore.value?.householdId, 'household-1');
    },
  );

  test('leave clears pending recovery before the active session', () async {
    activeStore.value = 'household-1';
    pendingStore.value = const PendingHouseholdMarker(
      householdId: 'household-1',
      inviteCode: 'ABC234',
    );

    await repository.leaveHousehold();

    expect(pendingStore.value, isNull);
    expect(activeStore.value, isNull);
    expect(await repository.restoreSession(), isNull);
  });

  test(
    'create reconciles a pending committed household before a new write',
    () async {
      pendingStore.value = const PendingHouseholdMarker(
        householdId: 'household-1',
        inviteCode: 'ABC234',
      );
      gateway.householdDocument = _householdDocument(inviteCode: 'ABC234');
      gateway.memberDocument = const StoredDocument(
        id: 'user-1',
        exists: true,
        data: {'displayName': 'Caregiver'},
      );

      final session = await repository.createHousehold(
        householdName: 'Ignored duplicate',
        petName: 'Ignored pet',
        caregiverName: 'Ignored name',
        timeZoneIdentifier: 'Asia/Tokyo',
      );

      expect(session.household.name, 'Family');
      expect(gateway.createCommands, isEmpty);
    },
  );

  test('empty caregiver name is input error, not an invite error', () async {
    await expectLater(
      repository.joinHousehold(inviteCode: 'ABC234', caregiverName: '  '),
      throwsA(
        isA<HouseholdRepositoryException>().having(
          (error) => error.code,
          'code',
          HouseholdRepositoryErrorCode.invalidInput,
        ),
      ),
    );
  });
}

StoredDocument _householdDocument({required String inviteCode}) {
  return StoredDocument(
    id: 'household-1',
    exists: true,
    data: {
      'name': 'Family',
      'petName': 'Pet',
      'inviteCode': inviteCode,
      'timeZoneIdentifier': 'Asia/Tokyo',
      'createdAt': Timestamp.fromDate(DateTime.utc(2026)),
    },
  );
}

final class FakeActiveHouseholdStore implements ActiveHouseholdStore {
  String? value;
  int clears = 0;
  Object? saveError;

  @override
  Future<void> clear() async {
    clears += 1;
    value = null;
  }

  @override
  Future<String?> read() async => value;

  @override
  Future<void> save(String householdId) async {
    if (saveError case final Object error) throw error;
    value = householdId;
  }
}

final class FakePendingHouseholdStore implements PendingHouseholdStore {
  PendingHouseholdMarker? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<PendingHouseholdMarker?> read() async => value;

  @override
  Future<void> save(PendingHouseholdMarker marker) async => value = marker;
}

final class SequenceInviteCodeGenerator implements InviteCodeGenerator {
  SequenceInviteCodeGenerator(this.values);

  final List<String> values;
  int index = 0;

  @override
  String next() => values[index++];
}

final class FakeHouseholdDataGateway implements HouseholdDataGateway {
  final createCommands = <CreateHouseholdCommand>[];
  final joinCommands = <JoinHouseholdCommand>[];
  final createOutcomes = <Object?>[];
  JoinHouseholdResult? joinResult;
  StoredDocument householdDocument = const StoredDocument(
    id: 'household-1',
    exists: false,
  );
  StoredDocument memberDocument = const StoredDocument(
    id: 'user-1',
    exists: false,
  );
  int authCalls = 0;
  Object? authError;
  final reads = <String>[];

  @override
  Future<void> createHouseholdAtomically(CreateHouseholdCommand command) async {
    createCommands.add(command);
    if (createOutcomes.isEmpty) return;
    final outcome = createOutcomes.removeAt(0);
    if (outcome is Exception) throw outcome;
  }

  @override
  Future<String> ensureAnonymousUserId() async {
    authCalls += 1;
    if (authError case final Object error) throw error;
    return 'user-1';
  }

  @override
  Future<JoinHouseholdResult> joinHouseholdAtomically(
    JoinHouseholdCommand command,
  ) async {
    joinCommands.add(command);
    return joinResult!;
  }

  @override
  String newHouseholdId() => 'household-1';

  @override
  Future<StoredDocument> readHousehold(String householdId) async =>
      _recordRead('household', householdDocument);

  @override
  Future<StoredDocument> readMember(String householdId, String userId) async =>
      _recordRead('member', memberDocument);

  StoredDocument _recordRead(String kind, StoredDocument document) {
    reads.add(kind);
    return document;
  }
}
