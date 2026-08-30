import 'package:copaw_flutter/src/data/firebase_household_data_gateway.dart';
import 'package:copaw_flutter/src/data/household_data_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const serverTime = _ServerTime();
  const create = CreateHouseholdCommand(
    householdId: 'household-1',
    ownerId: 'user-1',
    householdName: 'Family',
    petName: 'Pet',
    caregiverName: 'Caregiver',
    inviteCode: 'ABC234',
    timeZoneIdentifier: 'Asia/Tokyo',
  );
  const join = JoinHouseholdCommand(
    userId: 'user-2',
    caregiverName: 'Joining caregiver',
    inviteCode: 'ABC234',
  );
  final builder = HouseholdWritePayloadBuilder(
    serverTimestamp: () => serverTime,
  );

  test('create payloads include complete Rules writer fields', () {
    final pet = builder.newFirstPet(create);
    expect(builder.newHousehold(create), {
      'id': 'household-1',
      'name': 'Family',
      'petName': 'Pet',
      'inviteCode': 'ABC234',
      'timeZoneIdentifier': 'Asia/Tokyo',
      'ownerID': 'user-1',
      'createdAt': serverTime,
    });
    expect(builder.newOwnerMember(create), {
      'id': 'user-1',
      'displayName': 'Caregiver',
      'inviteCode': 'ABC234',
      'joinedAt': serverTime,
    });
    expect(pet, {
      'id': 'legacy-primary',
      'name': 'Pet',
      'species': null,
      'isArchived': false,
      'createdAt': serverTime,
      'updatedAt': serverTime,
    });
    expect(identical(pet['createdAt'], pet['updatedAt']), isTrue);
    expect(builder.newInvite(create), {
      'householdID': 'household-1',
      'createdBy': 'user-1',
      'createdAt': serverTime,
      'active': true,
    });
  });

  test('new and returning join payloads use distinct Rules fields', () {
    expect(builder.newJoiningMember(join), {
      'id': 'user-2',
      'displayName': 'Joining caregiver',
      'inviteCode': 'ABC234',
      'joinedAt': serverTime,
    });
    expect(builder.returningMember(join), {
      'displayName': 'Joining caregiver',
      'updatedAt': serverTime,
    });
  });
}

final class _ServerTime {
  const _ServerTime();
}
