import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';

/// A pet's weight over the last [months] months.
///
/// Shared by the Insights tab and the Health tab so both read the same
/// [Pet.weightHistory] — weight logged as a health record shows up in the
/// trend chart without a second source of truth.
class WeightChart extends StatelessWidget {
  const WeightChart({
    super.key,
    required this.pet,
    required this.months,
    required this.language,
    this.height = 220,
  });

  final Pet pet;
  final int months;
  final AppLanguage language;
  final double height;

  List<PetWeightEntry> get _entries {
    final cutoff = DateTime.now().subtract(Duration(days: months * 30));
    return pet.weightHistory.where((e) => !e.date.isBefore(cutoff)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final spots = <FlSpot>[
      for (var i = 0; i < entries.length; i++)
        FlSpot(i.toDouble(), entries[i].weightKg),
    ];

    return Container(
      height: height,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
      ),
      child: spots.length < 2
          ? Center(
              child: Text(
                L10n.text(language, 'Not enough data', 'データ不足', '数据不足',
                    '데이터 부족'),
                style: const TextStyle(color: PawColors.muted),
              ),
            )
          : LineChart(
              LineChartData(
                gridData: const FlGridData(show: true),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: PawColors.blue,
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: PawColors.blue.withValues(alpha: 0.10),
                    ),
                  ),
                ],
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (v, meta) => Text(
                        v.toStringAsFixed(1),
                        style: const TextStyle(
                            fontSize: 10, color: PawColors.muted),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, meta) {
                        final i = v.toInt();
                        if (i < 0 || i >= entries.length) {
                          return const SizedBox();
                        }
                        final d = entries[i].date;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '${d.month}/${d.day}',
                            style: const TextStyle(
                                fontSize: 10, color: PawColors.muted),
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
              ),
            ),
    );
  }
}
