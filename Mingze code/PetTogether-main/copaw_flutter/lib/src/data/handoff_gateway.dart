final class StoredHandoffDocument {
  const StoredHandoffDocument({
    required this.exists,
    required this.data,
    required this.isFromCache,
    required this.hasPendingWrites,
  });

  final bool exists;
  final Map<String, Object?> data;
  final bool isFromCache;
  final bool hasPendingWrites;
}

final class SaveHandoffCommand {
  const SaveHandoffCommand({
    required this.householdId,
    required this.expectedRevision,
    required this.careInstructions,
    required this.emergencyContactName,
    required this.emergencyContactPhone,
    required this.veterinaryHospitalName,
    required this.veterinaryHospitalPhone,
    required this.updatedById,
    required this.updatedByName,
  });

  final String householdId;
  final int? expectedRevision;
  final String careInstructions;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final String veterinaryHospitalName;
  final String veterinaryHospitalPhone;
  final String updatedById;
  final String updatedByName;
}

abstract interface class HandoffGateway {
  Stream<StoredHandoffDocument> observeHandoff(String householdId);
  Future<void> saveHandoff(SaveHandoffCommand command);
}

final class HandoffRevisionConflict implements Exception {
  const HandoffRevisionConflict();
}
