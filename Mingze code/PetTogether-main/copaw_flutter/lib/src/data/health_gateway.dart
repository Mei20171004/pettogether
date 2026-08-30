final class StoredHealthDocument {
  const StoredHealthDocument({
    required this.id,
    required this.data,
    required this.hasPendingWrites,
  });

  final String id;
  final Map<String, Object?> data;
  final bool hasPendingWrites;
}

final class StoredHealthSnapshot {
  const StoredHealthSnapshot({
    required this.documents,
    required this.isFromCache,
  });

  final List<StoredHealthDocument> documents;
  final bool isFromCache;
}

final class CreateHealthRecordCommand {
  const CreateHealthRecordCommand({
    required this.householdId,
    required this.recordId,
    required this.petId,
    required this.type,
    required this.recordedAt,
    required this.detail,
    required this.weightKilograms,
    required this.waterMilliliters,
  });

  final String householdId;
  final String recordId;
  final String petId;
  final String type;
  final DateTime recordedAt;
  final String? detail;
  final double? weightKilograms;
  final double? waterMilliliters;
}

abstract interface class HealthGateway {
  Stream<StoredHealthSnapshot> observeHealth(String householdId);
  String newRecordId(String householdId);
  Future<void> createRecord(CreateHealthRecordCommand command);
  Future<Map<String, Object?>> createDailyCheckIn(Map<String, Object?> payload);
}
