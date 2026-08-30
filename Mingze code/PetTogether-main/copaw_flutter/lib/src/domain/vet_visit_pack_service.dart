import 'package:timezone/timezone.dart' as tz;

import 'handoff_models.dart';
import 'health_models.dart';
import 'medication_models.dart';
import 'models.dart';
import 'plus_features.dart';

/// Which part of the pack an entry belongs to.
enum VetVisitSection {
  emergencyContacts,
  careInstructions,
  activeMedications,
  medicationOutcomes,
  healthObservations,
}

/// One line of a pack.
///
/// Every line carries where it came from. The pack never derives, averages, or
/// interprets anything: it collects what caregivers recorded so a veterinarian
/// or a stand-in caregiver can see the source of each statement.
final class VetVisitEntry {
  const VetVisitEntry({
    required this.section,
    required this.label,
    required this.value,
    required this.recordedAt,
    required this.recordedBy,
    this.localDate,
    this.isServerConfirmed = true,
  });

  final VetVisitSection section;

  /// What this line is, taken from the source record.
  final String label;

  /// The recorded value, exactly as stored.
  final String value;

  /// When the source says this was recorded, or null when the source stores no
  /// time. It is never filled in with "now".
  final DateTime? recordedAt;

  /// Who the source says recorded it, or null when the source stores no actor.
  final String? recordedBy;

  /// The household-local day, when one could be determined.
  final String? localDate;

  final bool isServerConfirmed;
}

final class VetVisitPack {
  const VetVisitPack({
    required this.petId,
    required this.petName,
    required this.fromLocalDate,
    required this.toLocalDate,
    required this.entries,
    required this.missingSections,
  });

  final String petId;
  final String petName;
  final String? fromLocalDate;
  final String? toLocalDate;
  final List<VetVisitEntry> entries;

  /// Sections with nothing recorded. They are named so the reader can tell
  /// "nothing was recorded" apart from "this pack left it out".
  final Set<VetVisitSection> missingSections;

  List<VetVisitEntry> entriesFor(VetVisitSection section) =>
      entries.where((entry) => entry.section == section).toList(growable: false);

  bool get isEmpty => entries.isEmpty;
}

/// Builds a source-attributed pack for a veterinarian visit or a caregiver
/// handoff. Part of [PlusFeature.vetVisitPack].
final class VetVisitPackService {
  const VetVisitPackService();

  VetVisitPack build({
    required Pet pet,
    required DateTime endInstant,
    required int rangeDays,
    required String timeZoneIdentifier,
    HouseholdHandoff? handoff,
    List<Medication> medications = const [],
    List<MedicationOccurrence> medicationOccurrences = const [],
    List<HealthRecord> healthRecords = const [],
  }) {
    final location = _location(timeZoneIdentifier);
    final localEnd = location == null
        ? null
        : tz.TZDateTime.from(endInstant, location);
    final localStart = localEnd == null
        ? null
        : tz.TZDateTime(
            location!,
            localEnd.year,
            localEnd.month,
            localEnd.day - (rangeDays - 1),
          );
    final fromLocalDate = localStart == null ? null : _dateKey(localStart);
    final toLocalDate = localEnd == null ? null : _dateKey(localEnd);

    final entries = <VetVisitEntry>[];

    if (handoff != null) {
      for (final contact in <(String, String)>[
        ('emergencyContactName', handoff.emergencyContactName),
        ('emergencyContactPhone', handoff.emergencyContactPhone),
        ('veterinaryHospitalName', handoff.veterinaryHospitalName),
        ('veterinaryHospitalPhone', handoff.veterinaryHospitalPhone),
      ]) {
        if (contact.$2.trim().isEmpty) continue;
        entries.add(
          VetVisitEntry(
            section: VetVisitSection.emergencyContacts,
            label: contact.$1,
            value: contact.$2,
            recordedAt: handoff.updatedAt,
            recordedBy: handoff.updatedByNameSnapshot,
          ),
        );
      }
      if (handoff.careInstructions.trim().isNotEmpty) {
        entries.add(
          VetVisitEntry(
            section: VetVisitSection.careInstructions,
            label: 'careInstructions',
            value: handoff.careInstructions,
            recordedAt: handoff.updatedAt,
            recordedBy: handoff.updatedByNameSnapshot,
          ),
        );
      }
    }

    for (final medication in medications) {
      if (medication.petId != pet.id || !medication.isActive) continue;
      entries.add(
        VetVisitEntry(
          section: VetVisitSection.activeMedications,
          label: medication.displayName,
          value: medication.purpose ?? '',
          recordedAt: null,
          recordedBy: null,
        ),
      );
    }

    for (final occurrence in medicationOccurrences) {
      if (occurrence.petId != pet.id) continue;
      if (occurrence.outcomeStatus == MedicationOutcomeStatus.unresolved) {
        continue;
      }
      if (!_withinRange(occurrence.localDate, fromLocalDate, toLocalDate)) {
        continue;
      }
      entries.add(
        VetVisitEntry(
          section: VetVisitSection.medicationOutcomes,
          label: occurrence.medicationNameSnapshot,
          value: occurrence.doseText,
          recordedAt: occurrence.outcomeAt,
          recordedBy: occurrence.outcomeByNameSnapshot,
          localDate: occurrence.localDate,
          isServerConfirmed: occurrence.isServerConfirmed,
        ),
      );
    }

    for (final record in healthRecords) {
      if (record.petId != pet.id) continue;
      final localDate =
          record.recordedLocalDate ?? _dateKeyFor(record.recordedAt, location);
      if (!_withinRange(localDate, fromLocalDate, toLocalDate)) continue;
      entries.add(
        VetVisitEntry(
          section: VetVisitSection.healthObservations,
          label: record.type.name,
          value: record.detail ?? '',
          recordedAt: record.recordedAt,
          recordedBy: record.createdByNameSnapshot,
          localDate: localDate,
        ),
      );
    }

    entries.sort((left, right) {
      final bySection = left.section.index.compareTo(right.section.index);
      if (bySection != 0) return bySection;
      final leftAt = left.recordedAt;
      final rightAt = right.recordedAt;
      if (leftAt == null && rightAt == null) {
        return left.label.compareTo(right.label);
      }
      if (leftAt == null) return 1;
      if (rightAt == null) return -1;
      final byInstant = rightAt.compareTo(leftAt);
      return byInstant != 0 ? byInstant : left.label.compareTo(right.label);
    });

    final present = entries.map((entry) => entry.section).toSet();
    return VetVisitPack(
      petId: pet.id,
      petName: pet.name,
      fromLocalDate: fromLocalDate,
      toLocalDate: toLocalDate,
      entries: List.unmodifiable(entries),
      missingSections: Set.unmodifiable(
        VetVisitSection.values.where((section) => !present.contains(section)),
      ),
    );
  }

  bool _withinRange(String? localDate, String? from, String? to) {
    if (localDate == null) return false;
    if (from != null && localDate.compareTo(from) < 0) return false;
    if (to != null && localDate.compareTo(to) > 0) return false;
    return true;
  }

  tz.Location? _location(String identifier) {
    try {
      return tz.getLocation(identifier);
    } on Object {
      return null;
    }
  }

  String? _dateKeyFor(DateTime instant, tz.Location? location) {
    if (location == null) return null;
    return _dateKey(tz.TZDateTime.from(instant, location));
  }

  String _dateKey(tz.TZDateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}
