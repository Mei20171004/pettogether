import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/medication_models.dart';

enum MedicationRepositoryErrorCode {
  invalidInput,
  network,
  permission,
  stale,
  responsibilityConflict,
  terminalConflict,
  malformedData,
  backendUnavailable,
}

final class MedicationRepositoryException implements Exception {
  const MedicationRepositoryException(
    this.code, {
    this.authoritativeOccurrence,
    this.diagnosticCode,
  });

  final MedicationRepositoryErrorCode code;
  final MedicationOccurrence? authoritativeOccurrence;
  final String? diagnosticCode;

  @override
  String toString() => diagnosticCode == null
      ? 'MedicationRepositoryException(${code.name})'
      : 'MedicationRepositoryException(${code.name}, $diagnosticCode)';
}

final class MedicationSnapshot {
  const MedicationSnapshot({
    required this.medications,
    required this.schedules,
    required this.occurrences,
    required this.isServerConfirmed,
  });

  final List<Medication> medications;
  final List<MedicationScheduleVersion> schedules;
  final List<MedicationOccurrence> occurrences;
  final bool isServerConfirmed;
}

final class MedicationPlanSlotInput {
  const MedicationPlanSlotInput({
    required this.hour,
    required this.minute,
    required this.doseText,
    this.instructions,
  });

  final int hour;
  final int minute;
  final String doseText;
  final String? instructions;
}

abstract interface class MedicationRepository {
  Stream<MedicationSnapshot> observeMedication(String householdId);

  Future<String> createPlan({
    required String householdId,
    required String petId,
    required String medicationName,
    String? purpose,
    String? possibleSideEffects,
    required String effectiveFromLocalDate,
    required List<int> weekdays,
    required List<MedicationPlanSlotInput> slots,
  });

  Future<void> replacePlan({
    required String householdId,
    required Medication medication,
    required String medicationName,
    String? purpose,
    String? possibleSideEffects,
    required String effectiveFromLocalDate,
    required List<int> weekdays,
    required List<MedicationPlanSlotInput> slots,
  });

  Future<void> stopPlan({
    required String householdId,
    required Medication medication,
    required String effectiveUntilLocalDate,
  });

  Future<void> claim({
    required String householdId,
    required PlannedMedicationOccurrence occurrence,
  });

  Future<void> administer({
    required String householdId,
    required PlannedMedicationOccurrence occurrence,
  });

  Future<void> skip({
    required String householdId,
    required PlannedMedicationOccurrence occurrence,
    required MedicationSkipReasonCode reasonCode,
    String? reasonNote,
  });

  Future<void> stopObserving();
}

final medicationRepositoryProvider = Provider<MedicationRepository>((ref) {
  throw StateError(
    'MedicationRepository must be provided at the app boundary.',
  );
});
