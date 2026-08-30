import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/handoff_models.dart';

final class HandoffSnapshot {
  const HandoffSnapshot({
    required this.handoff,
    required this.isFromCache,
    required this.hasPendingWrites,
  });

  final HouseholdHandoff? handoff;
  final bool isFromCache;
  final bool hasPendingWrites;
}

enum HandoffRepositoryErrorCode {
  invalidInput,
  network,
  permission,
  malformedData,
  conflict,
  backendUnavailable,
}

final class HandoffRepositoryException implements Exception {
  const HandoffRepositoryException(this.code, {this.diagnosticCode});

  final HandoffRepositoryErrorCode code;
  final String? diagnosticCode;
}

abstract interface class HandoffRepository {
  Stream<HandoffSnapshot> observeHandoff(String householdId);

  Future<void> saveHandoff({
    required String householdId,
    required int? expectedRevision,
    required String careInstructions,
    required String emergencyContactName,
    required String emergencyContactPhone,
    required String veterinaryHospitalName,
    required String veterinaryHospitalPhone,
    required String updatedById,
    required String updatedByName,
  });

  Future<void> stopObserving();
}

final handoffRepositoryProvider = Provider<HandoffRepository>((ref) {
  throw StateError('HandoffRepository must be provided at the app boundary.');
});
