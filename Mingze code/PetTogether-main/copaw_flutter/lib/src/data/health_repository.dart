import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/health_models.dart';

final class HealthSnapshot {
  const HealthSnapshot(
    this.records, {
    this.isFromCache = false,
    this.droppedRecordCount = 0,
  });

  final List<HealthRecord> records;
  final bool isFromCache;
  final int droppedRecordCount;
}

enum HealthRepositoryErrorCode {
  invalidInput,
  network,
  permission,
  malformedData,
  conflict,
  backendUnavailable,
}

final class HealthRepositoryException implements Exception {
  const HealthRepositoryException(this.code, {this.diagnosticCode});

  final HealthRepositoryErrorCode code;
  final String? diagnosticCode;

  @override
  String toString() => diagnosticCode == null
      ? 'HealthRepositoryException(${code.name})'
      : 'HealthRepositoryException(${code.name}, $diagnosticCode)';
}

abstract interface class HealthRepository {
  Stream<HealthSnapshot> observeHealth(String householdId);

  Future<void> createRecord({
    required String householdId,
    required String petId,
    required String petName,
    required HealthRecordType type,
    required DateTime recordedAt,
    required String timeZoneIdentifier,
    required String? detail,
    required double? weightKilograms,
    double? waterMilliliters,
    DailyHealthCheckIn? dailyCheckIn,
    required String createdById,
    required String createdByName,
  });

  Future<void> stopObserving();
}

final healthRepositoryProvider = Provider<HealthRepository>((ref) {
  throw StateError('HealthRepository must be provided at the app boundary.');
});
