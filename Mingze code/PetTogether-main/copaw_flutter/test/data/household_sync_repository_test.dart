import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:copaw_flutter/src/data/firebase_household_sync_repository.dart';
import 'package:copaw_flutter/src/data/household_data_gateway.dart';
import 'package:copaw_flutter/src/data/household_repository.dart';
import 'package:copaw_flutter/src/data/household_sync_gateway.dart';
import 'package:copaw_flutter/src/domain/legacy_firestore_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeHouseholdSyncGateway gateway;
  late FirebaseHouseholdSyncRepository repository;

  setUp(() {
    gateway = FakeHouseholdSyncGateway();
    repository = FirebaseHouseholdSyncRepository(gateway: gateway);
  });

  tearDown(() => repository.stopObserving());

  test('emits decoded household/member and preserves diagnostics', () async {
    final events = <Object>[];
    repository
        .observeSession(householdId: 'home-a', userId: 'user-a')
        .listen(events.add, onError: events.add);
    await _settle();

    gateway.households['home-a']!.add(_household('home-a', timezone: null));
    gateway.members['home-a:user-a']!.add(_member('user-a'));
    await _settle();

    final snapshot = events.single as dynamic;
    expect(snapshot.household.id, 'home-a');
    expect(snapshot.memberJoinedAt, DateTime.utc(2026, 8, 1));
    expect(
      snapshot.diagnostics.map((dynamic item) => item.code),
      contains(DomainDiagnosticCode.legacyNeedsTimezone),
    );
  });

  test(
    'session replacement cancels old listeners and drops late values',
    () async {
      final firstEvents = <Object>[];
      final secondEvents = <Object>[];
      repository
          .observeSession(householdId: 'home-a', userId: 'user-a')
          .listen(firstEvents.add, onError: firstEvents.add);
      await _settle();

      repository
          .observeSession(householdId: 'home-b', userId: 'user-b')
          .listen(secondEvents.add, onError: secondEvents.add);
      await _settle();

      gateway.households['home-a']!.add(_household('home-a'));
      gateway.members['home-a:user-a']!.add(_member('user-a'));
      gateway.households['home-b']!.add(_household('home-b'));
      gateway.members['home-b:user-b']!.add(_member('user-b'));
      await _settle();

      expect(firstEvents, isEmpty);
      expect(secondEvents, hasLength(1));
      expect(
        gateway.cancelledStreams,
        containsAll(['h:home-a', 'm:home-a:user-a']),
      );
    },
  );

  test('malformed member emits stable malformed-data error', () async {
    final errors = <Object>[];
    repository
        .observeSession(householdId: 'home-a', userId: 'user-a')
        .listen((_) {}, onError: errors.add);
    await _settle();
    gateway.households['home-a']!.add(_household('home-a'));
    gateway.members['home-a:user-a']!.add(
      const StoredDocument(id: 'user-a', exists: true),
    );
    await _settle();

    expect(
      (errors.single as HouseholdRepositoryException).code,
      HouseholdRepositoryErrorCode.malformedData,
    );
  });

  test('profile update trims values and sends one atomic command', () async {
    await repository.updateProfile(
      householdId: 'home-a',
      userId: 'user-a',
      householdName: ' Family ',
      petName: ' Pet ',
      caregiverName: ' Caregiver ',
    );

    expect(gateway.profileCommands, hasLength(1));
    final command = gateway.profileCommands.single;
    expect(command.householdName, 'Family');
    expect(command.petName, 'Pet');
    expect(command.caregiverName, 'Caregiver');
  });

  test('listener provider permission error maps stably', () async {
    final errors = <Object>[];
    repository
        .observeSession(householdId: 'home-a', userId: 'user-a')
        .listen((_) {}, onError: errors.add);
    await _settle();
    gateway.households['home-a']!.addError(
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
    );
    await _settle();

    expect(
      (errors.single as HouseholdRepositoryException).code,
      HouseholdRepositoryErrorCode.permission,
    );
  });
}

StoredDocument _household(String id, {String? timezone = 'Asia/Tokyo'}) {
  return StoredDocument(
    id: id,
    exists: true,
    data: {
      'name': 'Family',
      'petName': 'Pet',
      'inviteCode': 'ABC234',
      'timeZoneIdentifier': ?timezone,
    },
  );
}

StoredDocument _member(String id) => StoredDocument(
  id: id,
  exists: true,
  data: {
    'displayName': 'Caregiver',
    'joinedAt': Timestamp.fromDate(DateTime.utc(2026, 8, 1)),
  },
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

final class FakeHouseholdSyncGateway implements HouseholdSyncGateway {
  final households = <String, StreamController<StoredDocument>>{};
  final members = <String, StreamController<StoredDocument>>{};
  final memberLists = <String, StreamController<List<StoredDocument>>>{};
  final profileCommands = <UpdateProfileCommand>[];
  final cancelledStreams = <String>[];

  @override
  Stream<StoredDocument> observeHousehold(String householdId) {
    final controller = StreamController<StoredDocument>.broadcast(
      onCancel: () => cancelledStreams.add('h:$householdId'),
    );
    households[householdId] = controller;
    return controller.stream;
  }

  @override
  Stream<StoredDocument> observeMember(String householdId, String userId) {
    final key = '$householdId:$userId';
    final controller = StreamController<StoredDocument>.broadcast(
      onCancel: () => cancelledStreams.add('m:$key'),
    );
    members[key] = controller;
    return controller.stream;
  }

  @override
  Stream<List<StoredDocument>> observeMembers(String householdId) {
    final controller = StreamController<List<StoredDocument>>.broadcast(
      onCancel: () => cancelledStreams.add('ml:$householdId'),
    );
    memberLists[householdId] = controller;
    return controller.stream;
  }

  @override
  Future<void> updateProfileAtomically(UpdateProfileCommand command) async {
    profileCommands.add(command);
  }
}
