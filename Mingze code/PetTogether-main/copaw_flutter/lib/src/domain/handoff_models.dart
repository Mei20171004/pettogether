final class HouseholdHandoff {
  const HouseholdHandoff({
    required this.careInstructions,
    required this.emergencyContactName,
    required this.emergencyContactPhone,
    required this.veterinaryHospitalName,
    required this.veterinaryHospitalPhone,
    required this.revision,
    required this.updatedById,
    required this.updatedByNameSnapshot,
    required this.updatedAt,
  });

  final String careInstructions;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final String veterinaryHospitalName;
  final String veterinaryHospitalPhone;
  final int revision;
  final String updatedById;
  final String updatedByNameSnapshot;
  final DateTime updatedAt;
}

final class HandoffVersion {
  const HandoffVersion({
    required this.id,
    required this.sourceHandoffRevision,
    required this.careInstructions,
    required this.emergencyContactName,
    required this.emergencyContactPhone,
    required this.veterinaryHospitalName,
    required this.veterinaryHospitalPhone,
    required this.updatedById,
    required this.updatedByNameSnapshot,
    required this.updatedAt,
    required this.materializedAt,
  });

  final String id;
  final int sourceHandoffRevision;
  final String careInstructions;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final String veterinaryHospitalName;
  final String veterinaryHospitalPhone;
  final String updatedById;
  final String updatedByNameSnapshot;
  final DateTime updatedAt;
  final DateTime materializedAt;
}

enum HandoffSessionStatus { offered, accepted, declined, cancelled, closed }

enum HandoffResolutionReason { ownerRecovery }

final class HandoffSession {
  const HandoffSession({
    required this.id,
    required this.versionId,
    required this.handoffRevisionSnapshot,
    required this.creatorId,
    required this.creatorNameSnapshot,
    required this.recipientId,
    required this.recipientNameSnapshot,
    required this.timeZoneIdentifierSnapshot,
    required this.plannedStartAt,
    required this.plannedEndAt,
    required this.status,
    required this.offeredAt,
    required this.acceptedById,
    required this.acceptedByNameSnapshot,
    required this.acceptedAt,
    required this.declinedById,
    required this.declinedByNameSnapshot,
    required this.declinedAt,
    required this.cancelledById,
    required this.cancelledByNameSnapshot,
    required this.cancelledAt,
    required this.closedById,
    required this.closedByNameSnapshot,
    required this.closedAt,
    required this.resolutionReason,
    required this.revision,
  });

  final String id;
  final String versionId;
  final int handoffRevisionSnapshot;
  final String creatorId;
  final String creatorNameSnapshot;
  final String recipientId;
  final String recipientNameSnapshot;
  final String timeZoneIdentifierSnapshot;
  final DateTime plannedStartAt;
  final DateTime plannedEndAt;
  final HandoffSessionStatus status;
  final DateTime offeredAt;
  final String? acceptedById;
  final String? acceptedByNameSnapshot;
  final DateTime? acceptedAt;
  final String? declinedById;
  final String? declinedByNameSnapshot;
  final DateTime? declinedAt;
  final String? cancelledById;
  final String? cancelledByNameSnapshot;
  final DateTime? cancelledAt;
  final String? closedById;
  final String? closedByNameSnapshot;
  final DateTime? closedAt;
  final HandoffResolutionReason? resolutionReason;
  final int revision;
}

final class HandoffSessionMutationResult {
  const HandoffSessionMutationResult({
    required this.sessionId,
    required this.sessionRevision,
    required this.sessionStatus,
    required this.activeSessionId,
    required this.versionId,
    required this.existing,
  });

  final String sessionId;
  final int sessionRevision;
  final HandoffSessionStatus sessionStatus;
  final String? activeSessionId;
  final String versionId;
  final bool existing;
}
