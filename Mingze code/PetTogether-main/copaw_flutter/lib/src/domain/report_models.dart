import 'health_models.dart';

enum ReportEventKind {
  careCompleted,
  medicationAdministered,
  medicationSkipped,
}

final class ReportEvent {
  const ReportEvent({
    required this.sourceId,
    required this.kind,
    required this.label,
    required this.dueAt,
    required this.recordedAt,
    required this.actorNameSnapshot,
  });

  final String sourceId;
  final ReportEventKind kind;
  final String label;
  final DateTime dueAt;
  final DateTime recordedAt;
  final String actorNameSnapshot;
}

final class CareReportSummary {
  const CareReportSummary({
    required this.planned,
    required this.completed,
    required this.unresolved,
    required this.completedEvents,
  });

  final int planned;
  final int completed;
  final int unresolved;
  final List<ReportEvent> completedEvents;
}

final class MedicationReportSummary {
  const MedicationReportSummary({
    required this.planned,
    required this.administered,
    required this.skipped,
    required this.unresolved,
    required this.late,
    required this.terminalEvents,
  });

  final int planned;
  final int administered;
  final int skipped;
  final int unresolved;
  final int late;
  final List<ReportEvent> terminalEvents;
}

final class HealthReportSummary {
  const HealthReportSummary({
    required this.total,
    required this.countsByType,
    required this.records,
    this.waterDays = const [],
    this.excludedWaterRecordCount = 0,
  });

  final int total;
  final Map<HealthRecordType, int> countsByType;
  final List<HealthRecord> records;
  final List<WaterDaySummary> waterDays;
  final int excludedWaterRecordCount;
}

enum WaterDaySummaryBasis { summedSingleIntakes, localDayToDate, fullLocalDay }

final class WaterDaySummary {
  const WaterDaySummary({
    required this.localDate,
    required this.milliliters,
    required this.basis,
    required this.includedRecordCount,
    required this.excludedRecordCount,
  });

  final String localDate;
  final double milliliters;
  final WaterDaySummaryBasis basis;
  final int includedRecordCount;
  final int excludedRecordCount;
}

/// A section a report can include.
///
/// Part of `PlusFeature.customReport`. Every summary is always computed from
/// the real sources; this only decides what a rendered report shows, so a
/// consumer that ignores [PetCareReport.includedSections] still sees true
/// numbers rather than zeros that look like "nothing happened".
enum ReportSection { care, medication, health, water }

final class PetCareReport {
  const PetCareReport({
    required this.petId,
    required this.petNameSnapshot,
    required this.rangeDays,
    required this.startAt,
    required this.endAt,
    required this.timeZoneIdentifier,
    required this.care,
    required this.medication,
    required this.health,
    this.includedSections = const {
      ReportSection.care,
      ReportSection.medication,
      ReportSection.health,
      ReportSection.water,
    },
  });

  final String petId;
  final String petNameSnapshot;
  final int rangeDays;
  final DateTime startAt;
  final DateTime endAt;
  final String timeZoneIdentifier;
  final CareReportSummary care;
  final MedicationReportSummary medication;
  final HealthReportSummary health;

  /// Which sections a rendered report shows. Excluding a section never removes
  /// it from the summaries above.
  final Set<ReportSection> includedSections;

  bool includes(ReportSection section) => includedSections.contains(section);
}
