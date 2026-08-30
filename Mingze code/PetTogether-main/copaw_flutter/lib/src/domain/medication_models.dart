enum MedicationResponsibilityStatus { unclaimed, claimed }

enum MedicationOutcomeStatus { unresolved, administered, skipped }

enum MedicationSkipReasonCode {
  petRefused,
  vomited,
  unavailable,
  vetInstruction,
  other,
}

final class Medication {
  const Medication({
    required this.id,
    required this.petId,
    required this.displayName,
    this.purpose,
    this.possibleSideEffects,
    required this.isActive,
    required this.currentScheduleVersion,
    required this.currentScheduleVersionId,
    required this.revision,
  });

  final String id;
  final String petId;
  final String displayName;
  final String? purpose;
  final String? possibleSideEffects;
  final bool isActive;
  final int currentScheduleVersion;
  final String currentScheduleVersionId;
  final int revision;
}

final class MedicationSlot {
  const MedicationSlot({
    required this.slotId,
    required this.hour,
    required this.minute,
    required this.doseText,
    required this.instructions,
  });

  final String slotId;
  final int hour;
  final int minute;
  final String doseText;
  final String? instructions;
}

final class MedicationScheduleVersion {
  const MedicationScheduleVersion({
    required this.id,
    required this.medicationId,
    required this.version,
    required this.petId,
    required this.petNameSnapshot,
    required this.medicationNameSnapshot,
    required this.weekdays,
    required this.slots,
    required this.timeZoneIdentifier,
    required this.effectiveFromLocalDate,
    required this.effectiveUntilLocalDate,
  });

  final String id;
  final String medicationId;
  final int version;
  final String petId;
  final String petNameSnapshot;
  final String medicationNameSnapshot;
  final List<int> weekdays;
  final List<MedicationSlot> slots;
  final String timeZoneIdentifier;
  final String effectiveFromLocalDate;
  final String? effectiveUntilLocalDate;
}

final class MedicationOccurrence {
  const MedicationOccurrence({
    required this.id,
    required this.medicationId,
    required this.scheduleVersionId,
    required this.scheduleVersion,
    required this.slotId,
    required this.localDate,
    required this.dueAt,
    required this.petId,
    required this.petNameSnapshot,
    required this.medicationNameSnapshot,
    required this.doseText,
    required this.instructions,
    required this.responsibilityStatus,
    required this.responsibleById,
    required this.responsibleByNameSnapshot,
    required this.claimedAt,
    required this.outcomeStatus,
    required this.outcomeById,
    required this.outcomeByNameSnapshot,
    required this.outcomeAt,
    required this.skippedReasonCode,
    required this.skippedReasonNote,
    required this.revision,
    required this.isServerConfirmed,
  });

  final String id;
  final String medicationId;
  final String scheduleVersionId;
  final int scheduleVersion;
  final String slotId;
  final String localDate;
  final DateTime dueAt;
  final String petId;
  final String petNameSnapshot;
  final String medicationNameSnapshot;
  final String doseText;
  final String? instructions;
  final MedicationResponsibilityStatus responsibilityStatus;
  final String? responsibleById;
  final String? responsibleByNameSnapshot;
  final DateTime? claimedAt;
  final MedicationOutcomeStatus outcomeStatus;
  final String? outcomeById;
  final String? outcomeByNameSnapshot;
  final DateTime? outcomeAt;
  final MedicationSkipReasonCode? skippedReasonCode;
  final String? skippedReasonNote;
  final int revision;
  final bool isServerConfirmed;
}

final class PlannedMedicationOccurrence {
  const PlannedMedicationOccurrence({
    required this.id,
    required this.medicationId,
    required this.scheduleVersionId,
    required this.scheduleVersion,
    required this.slotId,
    required this.localDate,
    required this.dueAt,
    required this.petId,
    required this.petNameSnapshot,
    required this.medicationNameSnapshot,
    required this.doseText,
    required this.instructions,
    required this.persisted,
  });

  final String id;
  final String medicationId;
  final String scheduleVersionId;
  final int scheduleVersion;
  final String slotId;
  final String localDate;
  final DateTime dueAt;
  final String petId;
  final String petNameSnapshot;
  final String medicationNameSnapshot;
  final String doseText;
  final String? instructions;
  final MedicationOccurrence? persisted;

  MedicationResponsibilityStatus get responsibilityStatus =>
      persisted?.responsibilityStatus ??
      MedicationResponsibilityStatus.unclaimed;

  MedicationOutcomeStatus get outcomeStatus =>
      persisted?.isServerConfirmed == true
      ? persisted!.outcomeStatus
      : MedicationOutcomeStatus.unresolved;

  bool get isServerConfirmed => persisted?.isServerConfirmed ?? false;
}
