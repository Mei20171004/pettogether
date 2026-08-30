import 'package:flutter/material.dart';

import '../domain/care_coverage_service.dart';
import '../domain/health_models.dart';
import '../domain/medication_models.dart';
import '../domain/models.dart';
import '../localization/app_locale.dart';

/// Where the household's care coverage has gaps.
///
/// Part of the future Plus tier (see `PlusFeature.careCoverageSummary`); it is
/// fully available to everyone and shows nothing about payment.
class CareCoverageSection extends StatefulWidget {
  const CareCoverageSection({
    super.key,
    required this.strings,
    required this.timeZoneIdentifier,
    required this.endInstant,
    required this.tasks,
    required this.medicationOccurrences,
    required this.healthRecords,
  });

  final AppStrings strings;
  final String? timeZoneIdentifier;
  final DateTime endInstant;
  final List<CareTask> tasks;
  final List<MedicationOccurrence> medicationOccurrences;
  final List<HealthRecord> healthRecords;

  @override
  State<CareCoverageSection> createState() => _CareCoverageSectionState();
}

class _CareCoverageSectionState extends State<CareCoverageSection> {
  static const _service = CareCoverageService();

  int _rangeDays = 7;

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final theme = Theme.of(context);
    final summary = _service.build(
      endInstant: widget.endInstant,
      rangeDays: _rangeDays,
      timeZoneIdentifier: widget.timeZoneIdentifier ?? '',
      tasks: widget.tasks,
      medicationOccurrences: widget.medicationOccurrences,
      healthRecords: widget.healthRecords,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.coveragePurpose,
          key: const Key('coverage.purpose'),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        SegmentedButton<int>(
          key: const Key('coverage.range'),
          segments: [
            ButtonSegment(value: 7, label: Text(strings.sevenDays)),
            ButtonSegment(value: 30, label: Text(strings.thirtyDays)),
          ],
          selected: {_rangeDays},
          onSelectionChanged: (value) =>
              setState(() => _rangeDays = value.single),
        ),
        const SizedBox(height: 12),
        if (!summary.isRangeUsable)
          Text(
            strings.coverageNoRange,
            key: const Key('coverage.noRange'),
          )
        else ...[
          Text(
            '${summary.fromLocalDate} – ${summary.toLocalDate}',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 12),
          if (!summary.hasGaps)
            Text(
              strings.coverageNoGaps,
              key: const Key('coverage.noGaps'),
            )
          else ...[
            _gapTile(
              const Key('coverage.gap.medicationOwner'),
              strings.coverageMedicationWithoutOwner(
                summary.medicationWithoutOwner,
              ),
              summary.medicationWithoutOwner,
            ),
            _gapTile(
              const Key('coverage.gap.medicationOutcome'),
              strings.coverageMedicationWithoutOutcome(
                summary.medicationWithoutOutcome,
              ),
              summary.medicationWithoutOutcome,
            ),
            _gapTile(
              const Key('coverage.gap.taskOwner'),
              strings.coverageTasksWithoutOwner(summary.tasksWithoutOwner),
              summary.tasksWithoutOwner,
            ),
            _gapTile(
              const Key('coverage.gap.healthDays'),
              strings.coverageDaysWithoutHealth(
                summary.daysWithoutHealthRecord.length,
              ),
              summary.daysWithoutHealthRecord.length,
            ),
          ],
          const SizedBox(height: 16),
          Text(strings.coverageContributions, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            strings.coverageContributionsNote,
            key: const Key('coverage.contributionsNote'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (summary.contributions.isEmpty)
            Text(
              strings.coverageNoContributions,
              key: const Key('coverage.noContributions'),
            )
          else
            for (final contribution in summary.contributions)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  key: Key('coverage.member.${contribution.memberId}'),
                  title: Text(contribution.memberName),
                  subtitle: Text(
                    strings.coverageContributionDetail(
                      contribution.completedTasks,
                      contribution.medicationOutcomes,
                    ),
                  ),
                ),
              ),
        ],
      ],
    );
  }

  Widget _gapTile(Key key, String label, int count) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      key: key,
      leading: Icon(
        count > 0
            ? Icons.error_outline_rounded
            : Icons.check_circle_outline_rounded,
      ),
      title: Text(label),
    ),
  );
}
