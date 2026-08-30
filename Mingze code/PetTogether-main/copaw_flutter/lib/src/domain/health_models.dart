enum HealthRecordType {
  dailyCheckIn,
  weight,
  waterIntake,
  appetite,
  energy,
  mood,
  stoolObservation,
  symptom,
  visit,
  vaccine,
  note,
}

enum DailyHealthLevel { lessThanUsual, usual, moreThanUsual, notObserved }

enum DailyHealthStatus { usual, changed, notObserved }

enum WaterMeasurementBasis {
  singleIntake,
  localDayToDate,
  fullLocalDay,
  legacyUnknown,
}

final class DailyHealthCheckIn {
  const DailyHealthCheckIn({
    required this.water,
    required this.appetite,
    required this.urination,
    required this.stool,
    required this.energy,
    required this.mood,
  });

  final DailyHealthLevel water;
  final DailyHealthLevel appetite;
  final DailyHealthLevel urination;
  final DailyHealthStatus stool;
  final DailyHealthLevel energy;
  final DailyHealthStatus mood;
}

final class HealthRecord {
  const HealthRecord({
    required this.id,
    required this.petId,
    required this.petNameSnapshot,
    required this.type,
    required this.recordedAt,
    this.recordedLocalDate,
    this.recordedTimeZoneIdentifier,
    required this.detail,
    required this.weightKilograms,
    this.waterMilliliters,
    this.waterMeasurementBasis,
    this.dailyCheckIn,
    required this.createdById,
    required this.createdByNameSnapshot,
    required this.createdAt,
  });

  final String id;
  final String petId;
  final String petNameSnapshot;
  final HealthRecordType type;
  final DateTime recordedAt;
  final String? recordedLocalDate;
  final String? recordedTimeZoneIdentifier;
  final String? detail;
  final double? weightKilograms;
  final double? waterMilliliters;
  final WaterMeasurementBasis? waterMeasurementBasis;
  final DailyHealthCheckIn? dailyCheckIn;
  final String createdById;
  final String createdByNameSnapshot;
  final DateTime createdAt;
}
