import 'package:flutter/material.dart';

import '../domain/care_search_service.dart';
import '../domain/health_models.dart';
import '../domain/medication_models.dart';
import '../domain/models.dart';
import '../localization/app_locale.dart';

/// Long-term search over the household's recorded history.
///
/// Part of the future Plus tier (see `PlusFeature.longTermSearch`); it is fully
/// available to everyone and shows nothing about payment.
class HistorySearchSection extends StatefulWidget {
  const HistorySearchSection({
    super.key,
    required this.strings,
    required this.timeZoneIdentifier,
    required this.pets,
    required this.healthRecords,
    required this.medicationOccurrences,
    required this.tasks,
  });

  final AppStrings strings;
  final String? timeZoneIdentifier;
  final List<Pet> pets;
  final List<HealthRecord> healthRecords;
  final List<MedicationOccurrence> medicationOccurrences;
  final List<CareTask> tasks;

  @override
  State<HistorySearchSection> createState() => _HistorySearchSectionState();
}

class _HistorySearchSectionState extends State<HistorySearchSection> {
  static const _service = CareSearchService();

  final TextEditingController _keyword = TextEditingController();
  String? _petId;
  DateTime? _from;
  DateTime? _to;
  Set<CareSearchKind> _kinds = CareSearchKind.values.toSet();

  @override
  void dispose() {
    _keyword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final theme = Theme.of(context);
    final outcome = _service.search(
      query: CareSearchQuery(
        petId: _petId,
        fromLocalDate: _formatDate(_from),
        toLocalDate: _formatDate(_to),
        kinds: _kinds,
        text: _keyword.text,
      ),
      timeZoneIdentifier: widget.timeZoneIdentifier ?? '',
      healthRecords: widget.healthRecords,
      medicationOccurrences: widget.medicationOccurrences,
      tasks: widget.tasks,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('search.keyword'),
          controller: _keyword,
          decoration: InputDecoration(
            labelText: strings.searchKeywordLabel,
            prefixIcon: const Icon(Icons.search_rounded),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        if (widget.pets.length > 1) ...[
          DropdownButtonFormField<String?>(
            key: const Key('search.pet'),
            initialValue: _petId,
            decoration: InputDecoration(labelText: strings.pets),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(strings.searchAllPets),
              ),
              for (final pet in widget.pets)
                DropdownMenuItem<String?>(value: pet.id, child: Text(pet.name)),
            ],
            onChanged: (value) => setState(() => _petId = value),
          ),
          const SizedBox(height: 12),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _kindChip(CareSearchKind.health, strings.searchKindHealth),
            _kindChip(CareSearchKind.medication, strings.searchKindMedication),
            _kindChip(CareSearchKind.task, strings.searchKindTask),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _dateButton(
              key: const Key('search.from'),
              label: strings.searchFromDate,
              value: _from,
              onPicked: (value) => setState(() => _from = value),
            ),
            _dateButton(
              key: const Key('search.to'),
              label: strings.searchToDate,
              value: _to,
              onPicked: (value) => setState(() => _to = value),
            ),
            TextButton(
              key: const Key('search.clear'),
              onPressed: _clear,
              child: Text(strings.searchClear),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          strings.searchResultCount(outcome.totalCount),
          key: const Key('search.count'),
          style: theme.textTheme.titleSmall,
        ),
        if (outcome.undatedCount > 0) ...[
          const SizedBox(height: 8),
          Text(
            strings.searchUndatedCount(outcome.undatedCount),
            key: const Key('search.undated'),
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 12),
        if (outcome.days.isEmpty)
          Text(strings.searchEmpty, key: const Key('search.empty'))
        else
          for (final day in outcome.days) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(day.localDate, style: theme.textTheme.titleSmall),
            ),
            for (final result in day.results) _resultTile(result, strings),
          ],
      ],
    );
  }

  Widget _kindChip(CareSearchKind kind, String label) {
    final selected = _kinds.contains(kind);
    return FilterChip(
      key: Key('search.kind.${kind.name}'),
      label: Text(label),
      selected: selected,
      onSelected: (value) => setState(() {
        final next = {..._kinds};
        if (value) {
          next.add(kind);
        } else if (next.length > 1) {
          next.remove(kind);
        }
        _kinds = next;
      }),
    );
  }

  Widget _dateButton({
    required Key key,
    required String label,
    required DateTime? value,
    required ValueChanged<DateTime?> onPicked,
  }) {
    final text = value == null
        ? '$label · ${widget.strings.searchAnyDate}'
        : '$label · ${_formatDate(value)}';
    return OutlinedButton.icon(
      key: key,
      icon: const Icon(Icons.calendar_today_rounded, size: 18),
      label: Text(text),
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        );
        if (picked != null) onPicked(picked);
      },
    );
  }

  Widget _resultTile(CareSearchResult result, AppStrings strings) {
    final icon = switch (result.kind) {
      CareSearchKind.health => Icons.monitor_heart_rounded,
      CareSearchKind.medication => Icons.medication_rounded,
      CareSearchKind.task => Icons.check_circle_outline_rounded,
    };
    final subtitle = <String>[
      result.petName,
      if (result.detail != null && result.detail!.isNotEmpty) result.detail!,
      if (!result.isServerConfirmed) strings.searchUnconfirmed,
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        key: Key('search.result.${result.id}'),
        leading: Icon(icon),
        title: Text(result.title),
        subtitle: Text(subtitle),
        isThreeLine: subtitle.length > 40,
      ),
    );
  }

  void _clear() {
    setState(() {
      _keyword.clear();
      _petId = null;
      _from = null;
      _to = null;
      _kinds = CareSearchKind.values.toSet();
    });
  }

  String? _formatDate(DateTime? value) {
    if (value == null) return null;
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}
