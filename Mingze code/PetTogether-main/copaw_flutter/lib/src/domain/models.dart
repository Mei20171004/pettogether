enum CareTaskStatus { unclaimed, claimed, completed }

const legacyPrimaryPetId = 'legacy-primary';

enum CareTaskKind { routine, oneOff }

enum CarePriority { normal, urgent }

enum CareCategory { feeding, walking, medication, grooming, other }

enum AssignmentMode { direct, open }

enum CareRoutineFrequency { daily, selectedDays }

enum PetSpecies { dog, cat, rabbit, other }

final class Pet {
  const Pet({
    required this.id,
    required this.name,
    required this.species,
    required this.isArchived,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final PetSpecies? species;
  final bool isArchived;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isSynthesizedLegacy => createdAt == null && updatedAt == null;
}

final class Household {
  const Household({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.petName,
    required this.timeZoneIdentifier,
    this.ownerId,
  });

  final String id;
  final String name;
  final String inviteCode;
  final String petName;
  final String? timeZoneIdentifier;
  final String? ownerId;

  bool get legacyNeedsTimezone => timeZoneIdentifier == null;
}

final class Caregiver {
  const Caregiver({required this.id, required this.displayName});

  final String id;
  final String displayName;
}

final class AssignmentRequest {
  const AssignmentRequest({
    required this.id,
    required this.requestedById,
    required this.requestedByNameSnapshot,
    required this.requestedToId,
    required this.requestedToNameSnapshot,
    required this.mode,
    required this.createdAt,
  });

  final String id;
  final String requestedById;
  final String requestedByNameSnapshot;
  final String? requestedToId;
  final String? requestedToNameSnapshot;
  final AssignmentMode mode;
  final DateTime createdAt;
}

final class CareRoutine {
  const CareRoutine({
    required this.id,
    required this.title,
    required this.category,
    required this.priority,
    required this.frequency,
    required this.weekdays,
    required this.hour,
    required this.minute,
    required this.startDate,
    required this.timeZoneIdentifier,
    required this.createdById,
    required this.createdByNameSnapshot,
    required this.isActive,
    this.petId = legacyPrimaryPetId,
    this.petNameSnapshot,
  });

  final String id;
  final String title;
  final CareCategory category;
  final CarePriority priority;
  final CareRoutineFrequency frequency;
  final List<int> weekdays;
  final int hour;
  final int minute;
  final DateTime startDate;
  final String timeZoneIdentifier;
  final String createdById;
  final String createdByNameSnapshot;
  final bool isActive;
  final String petId;
  final String? petNameSnapshot;
}

final class CareTask {
  const CareTask({
    required this.id,
    required this.title,
    required this.category,
    required this.dueTime,
    required this.kind,
    required this.priority,
    required this.routineId,
    required this.status,
    required this.assignmentRequest,
    required this.assigneeId,
    required this.assigneeNameSnapshot,
    required this.claimedAt,
    required this.createdById,
    required this.createdBy,
    required this.createdAt,
    required this.completedById,
    required this.completedBy,
    required this.completedAt,
    required this.revision,
    this.petId = legacyPrimaryPetId,
    this.petNameSnapshot,
  });

  final String id;
  final String title;
  final CareCategory category;
  final DateTime dueTime;
  final CareTaskKind kind;
  final CarePriority priority;
  final String? routineId;
  final CareTaskStatus status;
  final AssignmentRequest? assignmentRequest;
  final String? assigneeId;
  final String? assigneeNameSnapshot;
  final DateTime? claimedAt;
  final String? createdById;
  final String createdBy;
  final DateTime createdAt;
  final String? completedById;
  final String? completedBy;
  final DateTime? completedAt;
  final int revision;
  final String petId;
  final String? petNameSnapshot;
}
