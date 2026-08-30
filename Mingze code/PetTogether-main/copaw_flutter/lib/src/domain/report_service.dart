import 'package:timezone/data/latest.dart' as time_zone_data;
import 'package:timezone/timezone.dart' as tz;

import 'health_models.dart';
import 'medication_models.dart';
import 'medication_occurrence_service.dart';
import 'models.dart';
import 'report_models.dart';
import 'routine_occurrence_service.dart';

final class ReportBuildException implements Exception {
  const ReportBuildException();
}

final class ReportService {
  ReportService() {
    if (!_initialized) {
      time_zone_data.initializeTimeZones();
      _initialized = true;
    }
  }

  static bool _initialized = false;

  /// Builds a report for [rangeDays] ending at [endInstant], or for the custom
  /// span [startInstant]..[endInstant] when a start is given.
  ///
  /// [sections] decides what a rendered report shows. Every summary is still
  /// computed from the real sources, so excluding a section never turns real
  /// activity into a zero.
  PetCareReport build({
    required String petId,
    required String petName,
    int? rangeDays,
    DateTime? startInstant,
    Set<ReportSection> sections = const {
      ReportSection.care,
      ReportSection.medication,
      ReportSection.health,
      ReportSection.water,
    },
    required DateTime endInstant,
    required String timeZoneIdentifier,
    required Iterable<CareRoutine> routines,
    required Iterable<CareTask> tasks,
    required Iterable<MedicationScheduleVersion> medicationSchedules,
    required Iterable<MedicationOccurrence> medicationOccurrences,
    required Iterable<HealthRecord> healthRecords,
  }) {
    final usesCustomRange = startInstant != null;
    if (petId.isEmpty ||
        petName.trim().isEmpty ||
        sections.isEmpty ||
        (usesCustomRange && rangeDays != null) ||
        (!usesCustomRange && rangeDays != 7 && rangeDays != 30) ||
        (usesCustomRange && !startInstant.isBefore(endInstant))) {
      throw const ReportBuildException();
    }
    try {
      final location = tz.getLocation(timeZoneIdentifier);
      final localEnd = tz.TZDateTime.from(endInstant, location);
      final start = usesCustomRange
          ? tz.TZDateTime.from(startInstant, location)
          : tz.TZDateTime(
              location,
              localEnd.year,
              localEnd.month,
              localEnd.day - (rangeDays! - 1),
            );
      final startOfDay = tz.TZDateTime(
        location,
        start.year,
        start.month,
        start.day,
      );
      final spanDays = localEnd.difference(startOfDay).inDays + 1;
      if (spanDays < 1 || spanDays > 366) throw const ReportBuildException();
      final end = endInstant.toUtc();
      final startLocalDate = _dateKey(start);
      final endLocalDate = _dateKey(localEnd);
      final petRoutines = routines.where((item) => item.petId == petId);
      final petTasks = tasks.where((item) => item.petId == petId);
      final petSchedules = medicationSchedules.where(
        (item) => item.petId == petId,
      );
      final petMedicationOccurrences = medicationOccurrences.where(
        (item) => item.petId == petId,
      );
      final taskService = RoutineOccurrenceService();
      final medicationService = MedicationOccurrenceService();
      final plannedTasks = <String, CareTask>{};
      final plannedMedication = <String, PlannedMedicationOccurrence>{};

      for (var offset = 0; offset < spanDays; offset += 1) {
        final day = tz.TZDateTime(
          location,
          startOfDay.year,
          startOfDay.month,
          startOfDay.day + offset,
          12,
        );
        for (final task in taskService.tasksForDay(
          selectedInstant: day,
          householdTimeZoneIdentifier: timeZoneIdentifier,
          routines: petRoutines,
          persistedTasks: petTasks,
        )) {
          if (!task.dueTime.isBefore(start) && !task.dueTime.isAfter(end)) {
            plannedTasks[task.id] = task;
          }
        }
        for (final occurrence in medicationService.forDay(
          selectedInstant: day,
          schedules: petSchedules,
          persisted: petMedicationOccurrences,
        )) {
          if (!occurrence.dueAt.isBefore(start) &&
              !occurrence.dueAt.isAfter(end)) {
            plannedMedication[occurrence.id] = occurrence;
          }
        }
      }

      final completedTasks = plannedTasks.values
          .where((task) => task.status == CareTaskStatus.completed)
          .toList(growable: false);
      final careEvents =
          completedTasks
              .where(
                (task) => task.completedAt != null && task.completedBy != null,
              )
              .map(
                (task) => ReportEvent(
                  sourceId: task.id,
                  kind: ReportEventKind.careCompleted,
                  label: task.title,
                  dueAt: task.dueTime,
                  recordedAt: task.completedAt!,
                  actorNameSnapshot: task.completedBy!,
                ),
              )
              .toList(growable: false)
            ..sort(
              (left, right) => left.recordedAt.compareTo(right.recordedAt),
            );

      var administered = 0;
      var skipped = 0;
      var late = 0;
      final medicationEvents = <ReportEvent>[];
      for (final occurrence in plannedMedication.values) {
        final persisted = occurrence.persisted;
        final outcome = occurrence.outcomeStatus;
        if (outcome == MedicationOutcomeStatus.administered) {
          administered += 1;
        } else if (outcome == MedicationOutcomeStatus.skipped) {
          skipped += 1;
        }
        if (outcome == MedicationOutcomeStatus.unresolved ||
            persisted?.outcomeAt == null ||
            persisted?.outcomeByNameSnapshot == null) {
          continue;
        }
        if (persisted!.outcomeAt!.isAfter(occurrence.dueAt)) late += 1;
        medicationEvents.add(
          ReportEvent(
            sourceId: occurrence.id,
            kind: outcome == MedicationOutcomeStatus.administered
                ? ReportEventKind.medicationAdministered
                : ReportEventKind.medicationSkipped,
            label:
                '${occurrence.medicationNameSnapshot} · ${occurrence.doseText}',
            dueAt: occurrence.dueAt,
            recordedAt: persisted.outcomeAt!,
            actorNameSnapshot: persisted.outcomeByNameSnapshot!,
          ),
        );
      }
      medicationEvents.sort(
        (left, right) => left.recordedAt.compareTo(right.recordedAt),
      );

      final reportHealthRecords =
          healthRecords
              .where(
                (record) =>
                    record.petId == petId &&
                    _healthRecordIsInRange(
                      record,
                      start: start,
                      end: end,
                      startLocalDate: startLocalDate,
                      endLocalDate: endLocalDate,
                    ),
              )
              .toList(growable: false)
            ..sort(
              (left, right) => left.recordedAt.compareTo(right.recordedAt),
            );
      final healthCounts = <HealthRecordType, int>{};
      for (final record in reportHealthRecords) {
        healthCounts.update(
          record.type,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
      final water = _reduceWater(reportHealthRecords);

      return PetCareReport(
        petId: petId,
        petNameSnapshot: petName.trim(),
        rangeDays: spanDays,
        startAt: startOfDay.toUtc(),
        endAt: end,
        timeZoneIdentifier: timeZoneIdentifier,
        care: CareReportSummary(
          planned: plannedTasks.length,
          completed: completedTasks.length,
          unresolved: plannedTasks.length - completedTasks.length,
          completedEvents: List.unmodifiable(careEvents),
        ),
        medication: MedicationReportSummary(
          planned: plannedMedication.length,
          administered: administered,
          skipped: skipped,
          unresolved: plannedMedication.length - administered - skipped,
          late: late,
          terminalEvents: List.unmodifiable(medicationEvents),
        ),
        health: HealthReportSummary(
          total: reportHealthRecords.length,
          countsByType: Map.unmodifiable(healthCounts),
          records: List.unmodifiable(reportHealthRecords),
          waterDays: List.unmodifiable(water.days),
          excludedWaterRecordCount: water.excludedRecordCount,
        ),
        includedSections: Set.unmodifiable(sections),
      );
    } on Object catch (error) {
      if (error is ReportBuildException) rethrow;
      throw const ReportBuildException();
    }
  }
}

bool _healthRecordIsInRange(
  HealthRecord record, {
  required DateTime start,
  required DateTime end,
  required String startLocalDate,
  required String endLocalDate,
}) {
  if (record.recordedAt.isAfter(end)) return false;
  final localDate = record.recordedLocalDate;
  if (localDate != null) {
    return localDate.compareTo(startLocalDate) >= 0 &&
        localDate.compareTo(endLocalDate) <= 0;
  }
  return !record.recordedAt.isBefore(start);
}

_WaterReduction _reduceWater(Iterable<HealthRecord> records) {
  final grouped = <String, List<HealthRecord>>{};
  var excluded = 0;
  for (final record in records.where(
    (record) => record.waterMilliliters != null,
  )) {
    final localDate = record.recordedLocalDate;
    if (localDate == null ||
        record.waterMeasurementBasis == null ||
        record.waterMeasurementBasis == WaterMeasurementBasis.legacyUnknown) {
      excluded += 1;
      continue;
    }
    grouped.putIfAbsent(localDate, () => []).add(record);
  }

  final days = <WaterDaySummary>[];
  for (final entry in grouped.entries) {
    final recordsForDay = entry.value
      ..sort((left, right) => left.recordedAt.compareTo(right.recordedAt));
    final fullDay = recordsForDay
        .where(
          (record) =>
              record.waterMeasurementBasis ==
              WaterMeasurementBasis.fullLocalDay,
        )
        .toList(growable: false);
    final dayToDate = recordsForDay
        .where(
          (record) =>
              record.waterMeasurementBasis ==
              WaterMeasurementBasis.localDayToDate,
        )
        .toList(growable: false);
    final singleIntakes = recordsForDay
        .where(
          (record) =>
              record.waterMeasurementBasis ==
              WaterMeasurementBasis.singleIntake,
        )
        .toList(growable: false);

    late final double milliliters;
    late final WaterDaySummaryBasis basis;
    late final int includedCount;
    if (fullDay.isNotEmpty) {
      milliliters = fullDay.last.waterMilliliters!;
      basis = WaterDaySummaryBasis.fullLocalDay;
      includedCount = 1;
    } else if (dayToDate.isNotEmpty) {
      milliliters = dayToDate.last.waterMilliliters!;
      basis = WaterDaySummaryBasis.localDayToDate;
      includedCount = 1;
    } else {
      milliliters = singleIntakes.fold(
        0,
        (total, record) => total + record.waterMilliliters!,
      );
      basis = WaterDaySummaryBasis.summedSingleIntakes;
      includedCount = singleIntakes.length;
    }
    final excludedForDay = recordsForDay.length - includedCount;
    excluded += excludedForDay;
    days.add(
      WaterDaySummary(
        localDate: entry.key,
        milliliters: milliliters,
        basis: basis,
        includedRecordCount: includedCount,
        excludedRecordCount: excludedForDay,
      ),
    );
  }
  days.sort((left, right) => left.localDate.compareTo(right.localDate));
  return _WaterReduction(days: days, excludedRecordCount: excluded);
}

String _dateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

final class _WaterReduction {
  const _WaterReduction({
    required this.days,
    required this.excludedRecordCount,
  });

  final List<WaterDaySummary> days;
  final int excludedRecordCount;
}
