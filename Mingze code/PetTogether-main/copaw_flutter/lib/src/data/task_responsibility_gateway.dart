final class StoredResponsibilityTransferDocument {
  const StoredResponsibilityTransferDocument({
    required this.id,
    required this.data,
  });

  final String id;
  final Map<String, Object?> data;
}

final class StoredResponsibilityTransferSnapshot {
  const StoredResponsibilityTransferSnapshot({
    required this.documents,
    required this.isFromCache,
    this.pointers = const [],
  });

  final List<StoredResponsibilityTransferDocument> documents;
  final bool isFromCache;
  final List<StoredResponsibilityPointerDocument> pointers;
}

final class StoredResponsibilityPointerDocument {
  const StoredResponsibilityPointerDocument({
    required this.id,
    required this.data,
  });

  final String id;
  final Map<String, Object?> data;
}

abstract interface class TaskResponsibilityGateway {
  Stream<StoredResponsibilityTransferSnapshot> observeTransfers(
    String householdId,
  );

  Future<Map<String, Object?>> mutate(Map<String, Object?> payload);
}
