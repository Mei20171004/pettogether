import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../models/models.dart';
import '../../store/care_store.dart';
import '../../theme/app_theme.dart';
import 'common.dart';

class MedicationTrendDay {
  const MedicationTrendDay({
    required this.date,
    required this.planned,
    required this.completed,
  });

  final DateTime date;
  final int planned;
  final int completed;
}

List<MedicationTrendDay> medicationTrendForPet(
  CareStore store,
  String petId, {
  DateTime? now,
  int days = 7,
}) {
  final today = now ?? DateTime.now();
  final start = DateTime(
    today.year,
    today.month,
    today.day,
  ).subtract(Duration(days: days - 1));

  return [
    for (var index = 0; index < days; index++)
      (() {
        final date = start.add(Duration(days: index));
        final doses = store.doseTasksOn(date, petId: petId);
        return MedicationTrendDay(
          date: date,
          planned: doses.length,
          completed: doses
              .where(
                (dose) =>
                    dose.status == CareTaskStatus.completed &&
                    dose.isServerConfirmed,
              )
              .length,
        );
      })(),
  ];
}

/// Seven days of medication execution from the same tasks shown on Today.
///
/// The full pale bar is the number scheduled; the green portion is the number
/// recorded as given. This avoids inventing a composite "health score" while
/// still making a real, actionable trend visible.
class MedicationAdherenceChart extends StatelessWidget {
  const MedicationAdherenceChart({
    super.key,
    required this.store,
    required this.petId,
    required this.language,
    this.now,
  });

  final CareStore store;
  final String petId;
  final AppLanguage language;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final trend = medicationTrendForPet(store, petId, now: now);
    final planned = trend.fold<int>(0, (sum, day) => sum + day.planned);
    final completed = trend.fold<int>(0, (sum, day) => sum + day.completed);

    return PetCard(
      child: Column(
        key: const ValueKey('health-medication-trend'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const CareIcon(
                icon: Icons.medication_outlined,
                color: PawColors.green,
                size: 38,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L10n.text(
                        language,
                        'Medication follow-through',
                        '服薬の実行状況',
                        '用药执行情况',
                        '복약 실행 현황',
                      ),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: PawColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      planned == 0
                          ? L10n.text(
                              language,
                              'No doses scheduled in the last 7 days',
                              '直近7日間の予定はありません',
                              '最近 7 天没有用药计划',
                              '최근 7일간 복약 예정이 없습니다',
                            )
                          : L10n.text(
                              language,
                              '$completed of $planned recorded as given',
                              '$planned回中$completed回の服薬を記録',
                              '已记录 $completed/$planned 次用药',
                              '$planned회 중 $completed회 복약 기록',
                            ),
                      style: const TextStyle(
                        fontSize: 12,
                        color: PawColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (planned == 0)
            const SizedBox(height: 72)
          else
            SizedBox(
              height: 138,
              child: BarChart(
                BarChartData(
                  minY: 0,
                  maxY: trend.fold<double>(1, (max, day) {
                    return math.max(max, day.planned.toDouble());
                  }),
                  alignment: BarChartAlignment.spaceAround,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  barTouchData: BarTouchData(enabled: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          if (value != value.roundToDouble()) {
                            return const SizedBox.shrink();
                          }
                          final index = value.round();
                          if (index < 0 || index >= trend.length) {
                            return const SizedBox.shrink();
                          }
                          final day = trend[index].date;
                          return Padding(
                            padding: const EdgeInsets.only(top: 7),
                            child: Text(
                              '${day.month}/${day.day}',
                              style: const TextStyle(
                                fontSize: 9,
                                color: PawColors.muted,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var index = 0; index < trend.length; index++)
                      BarChartGroupData(
                        x: index,
                        barRods: [
                          BarChartRodData(
                            toY: trend[index].planned.toDouble(),
                            width: 16,
                            color: PawColors.lavender,
                            borderRadius: BorderRadius.circular(5),
                            rodStackItems: [
                              BarChartRodStackItem(
                                0,
                                trend[index].completed.toDouble(),
                                PawColors.green,
                              ),
                            ],
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
