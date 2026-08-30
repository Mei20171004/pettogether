import 'package:flutter/material.dart';

import '../domain/handoff_models.dart';
import '../domain/health_models.dart';
import '../domain/medication_models.dart';
import '../domain/models.dart';
import '../domain/vet_visit_pack_service.dart';
import '../localization/app_locale.dart';

/// A source-attributed pack for a veterinarian visit or a caregiver handoff.
///
/// Part of the future Plus tier (see `PlusFeature.vetVisitPack`); it is fully
/// available to everyone and shows nothing about payment.
class VetVisitPackSection extends StatefulWidget {
  const VetVisitPackSection({
    super.key,
    required this.strings,
    required this.pets,
    required this.timeZoneIdentifier,
    required this.endInstant,
    required this.handoff,
    required this.medications,
    required this.medicationOccurrences,
    required this.healthRecords,
  });

  final AppStrings strings;
  final List<Pet> pets;
  final String? timeZoneIdentifier;
  final DateTime endInstant;
  final HouseholdHandoff? handoff;
  final List<Medication> medications;
  final List<MedicationOccurrence> medicationOccurrences;
  final List<HealthRecord> healthRecords;

  @override
  State<VetVisitPackSection> createState() => _VetVisitPackSectionState();
}

class _VetVisitPackSectionState extends State<VetVisitPackSection> {
  static const _service = VetVisitPackService();

  String? _petId;
  int _rangeDays = 7;

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final theme = Theme.of(context);
    final pet = widget.pets.firstWhere(
      (candidate) => candidate.id == _petId,
      orElse: () => widget.pets.first,
    );
    final pack = _service.build(
      pet: pet,
      endInstant: widget.endInstant,
      rangeDays: _rangeDays,
      timeZoneIdentifier: widget.timeZoneIdentifier ?? '',
      handoff: widget.handoff,
      medications: widget.medications,
      medicationOccurrences: widget.medicationOccurrences,
      healthRecords: widget.healthRecords,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.vetPackPurpose,
          key: const Key('vetPack.purpose'),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        if (widget.pets.length > 1) ...[
          DropdownButtonFormField<String>(
            key: const Key('vetPack.pet'),
            initialValue: pet.id,
            decoration: InputDecoration(labelText: strings.pets),
            items: [
              for (final candidate in widget.pets)
                DropdownMenuItem<String>(
                  value: candidate.id,
                  child: Text(candidate.name),
                ),
            ],
            onChanged: (value) => setState(() => _petId = value),
          ),
          const SizedBox(height: 12),
        ],
        SegmentedButton<int>(
          key: const Key('vetPack.range'),
          segments: [
            ButtonSegment(value: 7, label: Text(strings.sevenDays)),
            ButtonSegment(value: 30, label: Text(strings.thirtyDays)),
          ],
          selected: {_rangeDays},
          onSelectionChanged: (value) =>
              setState(() => _rangeDays = value.single),
        ),
        const SizedBox(height: 12),
        if (pack.fromLocalDate != null)
          Text(
            '${pack.fromLocalDate} – ${pack.toLocalDate}',
            key: const Key('vetPack.range.label'),
            style: theme.textTheme.titleSmall,
          )
        else
          Text(
            strings.vetPackNoRange,
            key: const Key('vetPack.noRange'),
            style: theme.textTheme.bodySmall,
          ),
        const SizedBox(height: 12),
        for (final section in VetVisitSection.values) ...[
          Text(_sectionTitle(section), style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          if (pack.missingSections.contains(section))
            Padding(
              key: Key('vetPack.missing.${section.name}'),
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                strings.vetPackNothingRecorded,
                style: theme.textTheme.bodySmall,
              ),
            )
          else
            for (final entry in pack.entriesFor(section))
              _entryTile(entry, strings),
        ],
      ],
    );
  }

  Widget _entryTile(VetVisitEntry entry, AppStrings strings) {
    final attribution = <String>[
      if (entry.localDate != null) entry.localDate!,
      if (entry.recordedBy != null)
        strings.vetPackRecordedBy(entry.recordedBy!)
      else
        strings.vetPackNoRecordedSource,
      if (!entry.isServerConfirmed) strings.searchUnconfirmed,
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        key: Key('vetPack.entry.${entry.section.name}.${entry.label}'),
        title: Text(entry.value.isEmpty ? entry.label : entry.value),
        subtitle: Text(attribution),
        isThreeLine: attribution.length > 40,
      ),
    );
  }

  String _sectionTitle(VetVisitSection section) => switch (section) {
    VetVisitSection.emergencyContacts => widget.strings.vetPackContacts,
    VetVisitSection.careInstructions => widget.strings.vetPackInstructions,
    VetVisitSection.activeMedications => widget.strings.vetPackMedications,
    VetVisitSection.medicationOutcomes => widget.strings.vetPackOutcomes,
    VetVisitSection.healthObservations => widget.strings.vetPackObservations,
  };
}
