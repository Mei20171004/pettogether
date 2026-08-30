import 'household_data_gateway.dart';

final class UpdateProfileCommand {
  const UpdateProfileCommand({
    required this.householdId,
    required this.userId,
    required this.householdName,
    required this.petName,
    required this.caregiverName,
  });

  final String householdId;
  final String userId;
  final String householdName;
  final String petName;
  final String caregiverName;
}

abstract interface class HouseholdSyncGateway {
  Stream<StoredDocument> observeHousehold(String householdId);
  Stream<StoredDocument> observeMember(String householdId, String userId);
  Stream<List<StoredDocument>> observeMembers(String householdId);
  Future<void> updateProfileAtomically(UpdateProfileCommand command);
}
