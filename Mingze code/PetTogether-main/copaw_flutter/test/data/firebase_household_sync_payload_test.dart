import 'package:copaw_flutter/src/data/firebase_household_sync_gateway.dart';
import 'package:copaw_flutter/src/data/household_sync_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const timestamp = _ServerTimestamp();
  const command = UpdateProfileCommand(
    householdId: 'home-a',
    userId: 'user-a',
    householdName: 'Family',
    petName: 'Pet',
    caregiverName: 'Caregiver',
  );
  final payloads = ProfileWritePayloadBuilder(serverTimestamp: () => timestamp);

  test('profile payloads contain only Rules-approved mutable fields', () {
    expect(payloads.household(command), {
      'name': 'Family',
      'petName': 'Pet',
      'updatedAt': timestamp,
    });
    expect(payloads.member(command), {
      'displayName': 'Caregiver',
      'updatedAt': timestamp,
    });
  });
}

final class _ServerTimestamp {
  const _ServerTimestamp();
}
