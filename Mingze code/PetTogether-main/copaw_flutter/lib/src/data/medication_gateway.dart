final class MedicationStoredDocument {
  const MedicationStoredDocument({required this.id, required this.data});

  final String id;
  final Map<String, Object?> data;
}

final class MedicationGatewaySnapshot {
  const MedicationGatewaySnapshot({
    required this.medications,
    required this.schedules,
    required this.occurrences,
    required this.isFromCache,
    required this.hasPendingWrites,
  });

  final List<MedicationStoredDocument> medications;
  final List<MedicationStoredDocument> schedules;
  final List<MedicationStoredDocument> occurrences;
  final bool isFromCache;
  final bool hasPendingWrites;
}

abstract interface class MedicationGateway {
  Stream<MedicationGatewaySnapshot> observe(String householdId);

  Future<Map<String, Object?>> call(String name, Map<String, Object?> payload);

  Future<void> stopObserving();
}
