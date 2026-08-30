import '../domain/legacy_firestore_codec.dart';
import '../domain/models.dart';
import 'household_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final class HouseholdSyncSnapshot {
  const HouseholdSyncSnapshot({
    required this.household,
    required this.caregiver,
    this.memberJoinedAt,
    this.members = const [],
    this.diagnostics = const [],
  });

  final Household household;
  final Caregiver caregiver;
  final DateTime? memberJoinedAt;
  final List<Caregiver> members;
  final List<DomainDiagnostic> diagnostics;
}

abstract interface class HouseholdSyncRepository {
  Stream<HouseholdSyncSnapshot> observeSession({
    required String householdId,
    required String userId,
  });

  Future<void> updateProfile({
    required String householdId,
    required String userId,
    required String householdName,
    required String petName,
    required String caregiverName,
  });

  Future<void> stopObserving();
}

final householdSyncRepositoryProvider = Provider<HouseholdSyncRepository>((
  ref,
) {
  throw StateError(
    'HouseholdSyncRepository must be provided at the app boundary.',
  );
});

HouseholdRepositoryException householdSyncError(Object error) {
  if (error is HouseholdRepositoryException) return error;
  return const HouseholdRepositoryException(
    HouseholdRepositoryErrorCode.backendUnavailable,
  );
}
