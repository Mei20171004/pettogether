import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/care_catalog.dart';
import '../models/models.dart';
import '../store/care_store.dart';
import '../theme/app_theme.dart';
import 'widgets/common.dart';

/// Reusable "pet insights" content: Today (to-do/done), This week (completion)
/// and Trends (timing + weight charts). Used by both the pet detail page and
/// the Activity tab.
class PetInsightsView extends StatefulWidget {
  const PetInsightsView({super.key, required this.pet});

  final Pet pet;

  @override
  State<PetInsightsView> createState() => _PetInsightsViewState();
}

class _PetInsightsViewState extends State<PetInsightsView> {
  int _tab = 0; // 0=今天 1=本周 2=趋势
  int _todayMode = 0; // 0=待做 1=已完成
  CareCategory _trendCategory = CareCategory.feeding;
  int _weightMonths = 3;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CareStore>();
    final language = context.watch<AppLanguageStore>().language;
    final pet = store.household?.pets
            .where((p) => p.id == widget.pet.id)
            .firstOrNull ??
        widget.pet;

    return Column(
      children: [
        _tabBar(language),
        const SizedBox(height: 10),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 2, 18, 24),
            child: switch (_tab) {
              0 => _todaySection(store, pet, language),
              1 => _weekSection(store, pet, language),
              _ => _trendsSection(store, pet, language),
            },
          ),
        ),
      ],
    );
  }

  Widget _tabBar(AppLanguage language) {
    return SegmentedButton<int>(
      segments: [
        ButtonSegment(
          value: 0,
          label: Text(L10n.text(language, 'Today', '今日', '今天', '오늘')),
        ),
        ButtonSegment(
          value: 1,
          label: Text(L10n.text(language, 'This week', '今週', '本周', '이번 주')),
        ),
        ButtonSegment(
          value: 2,
          label: Text(L10n.text(language, 'Trends', '推移', '趋势', '추이')),
        ),
      ],
      selected: {_tab},
      onSelectionChanged: (s) => setState(() => _tab = s.first),
    );
  }

  // -------------------------------------------------------------------------
  // Today
  // -------------------------------------------------------------------------

  Widget _todaySection(CareStore store, Pet pet, AppLanguage language) {
    final tasks = _petTasks(store, DateTime.now(), pet);
    final done =
        tasks.where((t) => t.status == CareTaskStatus.completed).toList();
    final todo =
        tasks.where((t) => t.status != CareTaskStatus.completed).toList();
    final list = _todayMode == 0 ? todo : done;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<int>(
          segments: [
            ButtonSegment(
              value: 0,
              label: Text(L10n.text(language, 'To do', 'やること', '待办', '할 일')),
            ),
            ButtonSegment(
              value: 1,
              label: Text(L10n.text(language, 'Done', '完了', '已完成', '완료')),
            ),
          ],
          selected: {_todayMode},
          onSelectionChanged: (s) => setState(() => _todayMode = s.first),
        ),
        const SizedBox(height: 12),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              L10n.text(language, 'Nothing here', '何もありません', '暂无内容', '없음'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: PawColors.muted),
            ),
          )
        else
          for (final task in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _taskRow(task, language),
            ),
      ],
    );
  }

  Widget _taskRow(CareTask task, AppLanguage language) {
    final color = categoryAccent(task.category);
    final time = task.completedAt ?? task.dueTime;
    return PetCard(
      padding: 12,
      child: Row(
        children: [
          CareIcon(icon: categoryIcon(task.category), color: color, size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Text(task.title,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: PawColors.ink)),
          ),
          Text(
            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
            style: const TextStyle(fontSize: 13, color: PawColors.muted),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // This week
  // -------------------------------------------------------------------------

  Widget _weekSection(CareStore store, Pet pet, AppLanguage language) {
    final days = _weekDays(DateTime.now());
    final totals = <int>[];
    final dones = <int>[];
    for (final day in days) {
      final tasks = _petTasks(store, day, pet);
      totals.add(tasks.length);
      dones.add(
          tasks.where((t) => t.status == CareTaskStatus.completed).length);
    }

    final byCategory = <CareCategory, List<int>>{};
    for (final day in days) {
      for (final task in _petTasks(store, day, pet)) {
        byCategory.putIfAbsent(task.category, () => [0, 0]);
        byCategory[task.category]![0]++;
        if (task.status == CareTaskStatus.completed) {
          byCategory[task.category]![1]++;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PetSectionTitle(
          title: L10n.text(language, 'Daily completion', '日ごとの完了', '每日完成',
              '일별 완료'),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _dayCard(
                      _weekdayShort(language, days[i]), dones[i], totals[i]),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        PetSectionTitle(
          title: L10n.text(language, 'By category', 'カテゴリ別', '按分类', '카테고리별'),
        ),
        const SizedBox(height: 10),
        if (byCategory.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('—', textAlign: TextAlign.center),
          )
        else
          for (final entry in byCategory.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _categoryProgress(
                  entry.key, entry.value[1], entry.value[0], language),
            ),
      ],
    );
  }

  Widget _dayCard(String label, int done, int total) {
    final ratio = total == 0 ? 0.0 : done / total;
    final color = ratio >= 1 && total > 0
        ? PawColors.green
        : (total > 0 ? PawColors.blue : PawColors.muted);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: PawColors.muted)),
          const SizedBox(height: 6),
          Text(
            total == 0 ? '—' : '$done/$total',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _categoryProgress(
      CareCategory category, int done, int total, AppLanguage language) {
    final color = categoryAccent(category);
    final ratio = total == 0 ? 0.0 : done / total;
    return Row(
      children: [
        CareIcon(icon: categoryIcon(category), color: color, size: 34),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                L10n.categoryTitle(language, category),
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: PawColors.ink),
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 6,
                  backgroundColor: color.withValues(alpha: 0.15),
                  color: color,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text('$done/$total',
            style: const TextStyle(fontSize: 12, color: PawColors.muted)),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Trends
  // -------------------------------------------------------------------------

  Widget _trendsSection(CareStore store, Pet pet, AppLanguage language) {
    final days = _weekDays(DateTime.now());
    final times = _categoryTimes(store, days, pet, _trendCategory);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PetSectionTitle(
          title:
              L10n.text(language, 'Schedule timing', '時間の推移', '时间变化', '시간 변화'),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            for (final c in categoriesForPetType(pet.type))
              ChoiceChip(
                label: Text(L10n.categoryTitle(language, c)),
                selected: _trendCategory == c,
                onSelected: (_) => setState(() => _trendCategory = c),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _timingChart(days, times, language),
        const SizedBox(height: 24),
        PetSectionTitle(
          title: L10n.text(language, 'Weight trend', '体重の推移', '体重变化', '체중 추이'),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final m in const [3, 4, 6])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(
                      '$m ${L10n.text(language, 'months', 'か月', '个月', '개월')}'),
                  selected: _weightMonths == m,
                  onSelected: (_) => setState(() => _weightMonths = m),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _weightChart(pet, language),
      ],
    );
  }

  Widget _timingChart(
      List<DateTime> days, List<double?> times, AppLanguage language) {
    final spots = <FlSpot>[
      for (var i = 0; i < times.length; i++)
        if (times[i] != null) FlSpot(i.toDouble(), times[i]!),
    ];
    return Container(
      height: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
      ),
      child: spots.length < 2
          ? Center(
              child: Text(L10n.text(language, 'Not enough data', 'データ不足',
                  '数据不足', '데이터 부족')))
          : LineChart(
              LineChartData(
                minY: 0,
                maxY: 24,
                gridData: const FlGridData(show: true),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: false,
                    color: PawColors.purple,
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: PawColors.purple.withValues(alpha: 0.10),
                    ),
                  ),
                ],
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      getTitlesWidget: (v, meta) => Text(
                        '${v.toInt()}',
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
                        if (i < 0 || i >= days.length) return const SizedBox();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _weekdayShort(language, days[i]),
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

  Widget _weightChart(Pet pet, AppLanguage language) {
    final cutoff = DateTime.now().subtract(Duration(days: _weightMonths * 30));
    final entries = pet.weightHistory
        .where((e) => !e.date.isBefore(cutoff))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final spots = <FlSpot>[
      for (var i = 0; i < entries.length; i++)
        FlSpot(i.toDouble(), entries[i].weightKg),
    ];

    return Container(
      height: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
      ),
      child: spots.length < 2
          ? Center(
              child: Text(L10n.text(language, 'Not enough data', 'データ不足',
                  '数据不足', '데이터 부족')))
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

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  List<CareTask> _petTasks(CareStore store, DateTime day, Pet pet) =>
      store.tasksOn(day).where((t) => t.petID == pet.id).toList();

  List<DateTime> _weekDays(DateTime now) {
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return List.generate(7, (i) => monday.add(Duration(days: i)));
  }

  List<double?> _categoryTimes(CareStore store, List<DateTime> days, Pet pet,
      CareCategory category) {
    return [
      for (final day in days)
        _firstTime(store
            .tasksOn(day)
            .where((t) => t.petID == pet.id && t.category == category)),
    ];
  }

  double? _firstTime(Iterable<CareTask> tasks) {
    if (tasks.isEmpty) return null;
    final t = tasks.first;
    final time = t.completedAt ?? t.dueTime;
    return time.hour + time.minute / 60.0;
  }

  String _weekdayShort(AppLanguage language, DateTime day) {
    const en = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const ja = ['月', '火', '水', '木', '金', '土', '日'];
    const zh = ['一', '二', '三', '四', '五', '六', '日'];
    const ko = ['월', '화', '수', '목', '금', '토', '일'];
    final i = day.weekday - 1;
    return switch (language) {
      AppLanguage.japanese => ja[i],
      AppLanguage.chinese => zh[i],
      AppLanguage.korean => ko[i],
      AppLanguage.english => en[i],
    };
  }
}
