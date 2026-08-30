import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/legacy_firestore_codec.dart';
import '../domain/models.dart';

enum LocalSessionPersistence { saved, unavailable }

final class HouseholdSession {
  const HouseholdSession({
    required this.household,
    required this.caregiver,
    this.memberJoinedAt,
    this.diagnostics = const [],
    this.localPersistence = LocalSessionPersistence.saved,
  });

  final Household household;
  final Caregiver caregiver;
  final DateTime? memberJoinedAt;
  final List<DomainDiagnostic> diagnostics;
  final LocalSessionPersistence localPersistence;
}

enum HouseholdRepositoryErrorCode {
  authentication,
  invalidInviteCode,
  inviteCodeUnavailable,
  network,
  permission,
  malformedData,
  backendUnavailable,
  invalidInput,
}

final class HouseholdRepositoryException implements Exception {
  const HouseholdRepositoryException(this.code);

  final HouseholdRepositoryErrorCode code;

  @override
  String toString() => 'HouseholdRepositoryException($code)';
}

abstract interface class HouseholdRepository {
  Future<HouseholdSession?> restoreSession();

  Future<HouseholdSession> createHousehold({
    required String householdName,
    required String petName,
    required String caregiverName,
    required String timeZoneIdentifier,
  });

  Future<HouseholdSession> joinHousehold({
    required String inviteCode,
    required String caregiverName,
  });

  Future<void> leaveHousehold();
}

final householdRepositoryProvider = Provider<HouseholdRepository>((ref) {
  throw StateError('HouseholdRepository must be provided at the app boundary.');
});
