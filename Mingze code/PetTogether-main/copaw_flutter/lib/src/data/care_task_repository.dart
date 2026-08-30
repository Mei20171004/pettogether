import '../domain/legacy_firestore_codec.dart';
import '../domain/models.dart';
import 'household_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final class CareTaskSnapshot {
  const CareTaskSnapshot({
    required this.routines,
    required this.tasks,
    this.diagnostics = const [],
    this.isServerConfirmed = true,
  });

  final List<CareRoutine> routines;
  final List<CareTask> tasks;
  final List<DomainDiagnostic> diagnostics;
  final bool isServerConfirmed;
}

abstract interface class CareTaskRepository {
  Stream<CareTaskSnapshot> observeCare(String householdId);

  Future<String> createOneOffTask({
    required String householdId,
    required String title,
    required CareCategory category,
    required DateTime dueTime,
    required CarePriority priority,
    required String createdById,
    required String createdByName,
  });

  Future<String> createRoutine({
    required String householdId,
    required String title,
    required CareCategory category,
    required CarePriority priority,
    required CareRoutineFrequency frequency,
    required List<int> weekdays,
    required int hour,
    required int minute,
    required DateTime startDate,
    required String timeZoneIdentifier,
    required String createdById,
    required String createdByName,
  });

  Future<void> stopObserving();
}

/// Strict writer used once the UI has an explicit pet selection.
///
/// The legacy [CareTaskRepository] methods remain available during migration
/// and resolve the household's legacy pet snapshot before writing.
abstract interface class PetBoundCareTaskWriter {
  Future<String> createOneOffTaskForPet({
    required String householdId,
    required String petId,
    required String petName,
    required String title,
    required CareCategory category,
    required DateTime dueTime,
    required CarePriority priority,
    required String createdById,
    required String createdByName,
  });

  Future<String> createRoutineForPet({
    required String householdId,
    required String petId,
    required String petName,
    required String title,
    required CareCategory category,
    required CarePriority priority,
    required CareRoutineFrequency frequency,
    required List<int> weekdays,
    required int hour,
    required int minute,
    required DateTime startDate,
    required String timeZoneIdentifier,
    required String createdById,
    required String createdByName,
  });
}

final careTaskRepositoryProvider = Provider<CareTaskRepository>((ref) {
  throw StateError('CareTaskRepository must be provided at the app boundary.');
});

HouseholdRepositoryException careTaskError(Object error) {
  if (error is HouseholdRepositoryException) return error;
  return const HouseholdRepositoryException(
    HouseholdRepositoryErrorCode.backendUnavailable,
  );
}
