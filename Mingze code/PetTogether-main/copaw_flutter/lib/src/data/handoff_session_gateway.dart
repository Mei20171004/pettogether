final class StoredHandoffSessionDocument {
  const StoredHandoffSessionDocument({required this.id, required this.data});

  final String id;
  final Map<String, Object?> data;
}

final class StoredHandoffVersionDocument {
  const StoredHandoffVersionDocument({required this.id, required this.data});

  final String id;
  final Map<String, Object?> data;
}

final class StoredHandoffSessionAuthority {
  const StoredHandoffSessionAuthority({
    required this.pointerExists,
    required this.pointerData,
    required this.sessions,
    required this.versions,
    required this.isFromCache,
  });

  final bool pointerExists;
  final Map<String, Object?> pointerData;
  final List<StoredHandoffSessionDocument> sessions;
  final List<StoredHandoffVersionDocument> versions;
  final bool isFromCache;
}

abstract interface class HandoffSessionGateway {
  Stream<StoredHandoffSessionAuthority> observeAuthority(String householdId);

  Future<Map<String, Object?>> mutate(Map<String, Object?> payload);
}
