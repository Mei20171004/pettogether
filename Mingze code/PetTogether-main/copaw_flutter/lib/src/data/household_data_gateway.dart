final class StoredDocument {
  const StoredDocument({
    required this.id,
    required this.exists,
    this.data = const {},
  });

  final String id;
  final bool exists;
  final Map<String, Object?> data;
}

final class CreateHouseholdCommand {
  const CreateHouseholdCommand({
    required this.householdId,
    required this.ownerId,
    required this.householdName,
    required this.petName,
    required this.caregiverName,
    required this.inviteCode,
    required this.timeZoneIdentifier,
  });

  final String householdId;
  final String ownerId;
  final String householdName;
  final String petName;
  final String caregiverName;
  final String inviteCode;
  final String timeZoneIdentifier;
}

final class JoinHouseholdCommand {
  const JoinHouseholdCommand({
    required this.userId,
    required this.caregiverName,
    required this.inviteCode,
  });

  final String userId;
  final String caregiverName;
  final String inviteCode;
}

final class JoinHouseholdResult {
  const JoinHouseholdResult({
    required this.householdId,
    required this.returningMember,
  });

  final String householdId;
  final bool returningMember;
}

final class InviteCodeCollision implements Exception {
  const InviteCodeCollision();
}

final class InvalidInvite implements Exception {
  const InvalidInvite();
}

abstract interface class HouseholdDataGateway {
  Future<String> ensureAnonymousUserId();
  String newHouseholdId();
  Future<void> createHouseholdAtomically(CreateHouseholdCommand command);
  Future<JoinHouseholdResult> joinHouseholdAtomically(
    JoinHouseholdCommand command,
  );
  Future<StoredDocument> readHousehold(String householdId);
  Future<StoredDocument> readMember(String householdId, String userId);
}

abstract interface class InviteCodeGenerator {
  String next();
}
