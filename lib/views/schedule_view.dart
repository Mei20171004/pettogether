import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/care_catalog.dart';
import '../models/models.dart';
import '../store/care_store.dart';
import '../theme/app_theme.dart';
import '../utils/care_calendar.dart';
import 'add_task_view.dart';
import 'widgets/common.dart';
import 'widgets/task_card.dart';

enum _Filter { all, routine, oneOff }

class ScheduleView extends StatefulWidget {
  const ScheduleView({super.key});

  @override
  State<ScheduleView> createState() => _ScheduleViewState();
}

class _ScheduleViewState extends State<ScheduleView> {
  DateTime _selectedDate = DateTime.now();
  _Filter _filter = _Filter.all;
  String? _petID;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CareStore>();
    final language = context.watch<AppLanguageStore>().language;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title:
            Text(L10n.text(language, 'Calendar', 'カレンダー', '日历', '캘린더')),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) => AddTaskView(initialDate: _selectedDate),
              ),
            ),
            icon: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: PawColors.purple,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, size: 20, color: Colors.white),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          const PetScreenBackground(),
          SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _calendarCard(context, store, language),
                    const SizedBox(height: 12),
                    _petFilterBar(store, language),
                    const SizedBox(height: 12),
                    _filterBar(language),
                    const SizedBox(height: 18),
                    _agenda(context, store, language),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _calendarCard(
      BuildContext context, CareStore store, AppLanguage language) {
    final locale = language.rawValue;
    final days = _monthDays(_selectedDate);

    return PetCard(
      padding: 15,
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => _moveMonth(-1),
                icon: const Icon(Icons.chevron_left, color: PawColors.purple),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      DateFormat('LLLL yyyy', locale).format(_selectedDate),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: PawColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      L10n.text(language, 'Routine and extra care together',
                          'ルーティンと特別なケアを一緒に', '例行和额外护理在一起',
                          '루틴과 특별 케어를 함께'),
                      style: const TextStyle(
                          fontSize: 11, color: PawColors.muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _moveMonth(1),
                icon: const Icon(Icons.chevron_right, color: PawColors.purple),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final symbol in _weekdaySymbols(language))
                Expanded(
                  child: Text(
                    symbol,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: PawColors.muted,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 4,
            ),
            itemCount: days.length,
            itemBuilder: (context, index) {
              final date = days[index];
              if (date == null) return const SizedBox.shrink();
              return _DayCell(
                date: date,
                isSelected: _sameDay(date, _selectedDate),
                isToday: _sameDay(date, DateTime.now()),
                tasks: store
                    .tasksOn(date)
                    .where((t) => _petID == null || t.petID == _petID)
                    .toList(),
                onTap: () => setState(() => _selectedDate = date),
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _legend(L10n.text(language, 'Routine', '繰り返し', '例行', '루틴'),
                  Icons.repeat, PawColors.purple),
              const SizedBox(width: 14),
              _legend(L10n.text(language, 'One-time', '一回のみ', '一次性', '일회성'),
                  Icons.circle, PawColors.blue),
              const SizedBox(width: 14),
              _legend(L10n.text(language, 'Urgent', '緊急', '紧急', '긴급'),
                  Icons.error, PawColors.rose),
            ],
          ),
        ],
      ),
    );
  }

  Widget _petFilterBar(CareStore store, AppLanguage language) {
    final pets = store.household?.pets ?? const <Pet>[];
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(L10n.text(language, 'All pets', 'すべてのペット',
                  '所有宠物', '모든 반려동물')),
              selected: _petID == null,
              onSelected: (_) => setState(() => _petID = null),
            ),
          ),
          for (final pet in pets)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Text(petTypeEmoji(pet.type)),
                label: Text(pet.name),
                selected: _petID == pet.id,
                onSelected: (_) => setState(() => _petID = pet.id),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterBar(AppLanguage language) {
    return Row(
      children: [
        _filterButton(
            _Filter.all, L10n.text(language, 'All', 'すべて', '全部', '전체')),
        const SizedBox(width: 8),
        _filterButton(_Filter.routine,
            L10n.text(language, 'Routine', '繰り返し', '例行', '루틴')),
        const SizedBox(width: 8),
        _filterButton(_Filter.oneOff,
            L10n.text(language, 'One-time', '一回のみ', '一次性', '일회성')),
      ],
    );
  }

  Widget _filterButton(_Filter filter, String title) {
    final selected = _filter == filter;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _filter = filter),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          alignment: Alignment.center,
          height: 44,
          decoration: BoxDecoration(
            color: selected ? PawColors.purple : Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: selected ? Colors.white : PawColors.purple,
            ),
          ),
        ),
      ),
    );
  }

  Widget _agenda(
      BuildContext context, CareStore store, AppLanguage language) {
    final locale = language.rawValue;
    final allTasks = store
        .tasksOn(_selectedDate)
        .where((t) => _petID == null || t.petID == _petID)
        .toList();
    final routineTasks =
        allTasks.where((t) => t.kind == CareTaskKind.routine).toList();
    final oneOffTasks =
        allTasks.where((t) => t.kind == CareTaskKind.oneOff).toList();

    final visible = switch (_filter) {
      _Filter.all => allTasks,
      _Filter.routine => routineTasks,
      _Filter.oneOff => oneOffTasks,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PetSectionTitle(
          title: DateFormat('EEEE, MMM d', locale).format(_selectedDate),
          detail: '${visible.length} TASK${visible.length == 1 ? '' : 'S'}',
        ),
        const SizedBox(height: 14),
        if (visible.isEmpty)
          PetCard(
            child: Column(
              children: [
                const CareIcon(
                    icon: Icons.add_circle_outline,
                    color: PawColors.purple,
                    size: 56),
                const SizedBox(height: 10),
                Text(
                  L10n.text(language, 'No care planned yet',
                      'まだケアの予定がありません', '还没有安排护理', '아직 예정된 케어가 없습니다'),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: PawColors.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  L10n.text(
                      language,
                      'Add a one-time need or start a daily routine for this date.',
                      'この日に一回のケアや毎日のルーティンを追加しましょう。',
                      '为这一天添加一次性需求，或开始每日例行。',
                      '이 날짜에 일회성 케어나 매일 루틴을 추가하세요.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: PawColors.muted),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      fullscreenDialog: true,
                      builder: (_) => AddTaskView(initialDate: _selectedDate),
                    ),
                  ),
                  child: Text(L10n.text(
                      language, 'Add care', 'ケアを追加', '添加护理', '케어 추가')),
                ),
              ],
            ),
          )
        else ...[
          if (_filter != _Filter.oneOff && routineTasks.isNotEmpty)
            _taskGroup(
              language,
              L10n.text(
                  language, 'Daily routine', '毎日のルーティン', '每日例行', '매일 루틴'),
              'REPEATS',
              routineTasks,
            ),
          if (_filter != _Filter.routine && oneOffTasks.isNotEmpty)
            _taskGroup(
              language,
              L10n.text(language, 'Extra care', '特別なケア', '额外护理', '특별 케어'),
              oneOffTasks.any((t) => t.priority == CarePriority.urgent)
                  ? 'URGENT INCLUDED'
                  : 'ONE-TIME',
              oneOffTasks,
            ),
        ],
      ],
    );
  }

  Widget _taskGroup(
      AppLanguage language, String title, String detail, List<CareTask> tasks) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PetSectionTitle(title: title, detail: detail),
          const SizedBox(height: 11),
          for (final task in tasks)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TaskCard(task: task),
            ),
        ],
      ),
    );
  }

  Widget _legend(String title, IconData icon, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  List<String> _weekdaySymbols(AppLanguage language) {
    return switch (language) {
      AppLanguage.japanese => const ['日', '月', '火', '水', '木', '金', '土'],
      AppLanguage.chinese => const ['日', '一', '二', '三', '四', '五', '六'],
      AppLanguage.korean => const ['일', '월', '화', '수', '목', '금', '토'],
      AppLanguage.english => const ['S', 'M', 'T', 'W', 'T', 'F', 'S'],
    };
  }

  List<DateTime?> _monthDays(DateTime selected) {
    final first = DateTime(selected.year, selected.month, 1);
    final daysInMonth = DateTime(selected.year, selected.month + 1, 0).day;
    final leading = swiftWeekday(first) - 1;
    return [
      for (var i = 0; i < leading; i++) null,
      for (var d = 1; d <= daysInMonth; d++)
        DateTime(selected.year, selected.month, d),
    ];
  }

  void _moveMonth(int value) {
    setState(() {
      final day = _selectedDate.day;
      final target = DateTime(_selectedDate.year, _selectedDate.month + value, 1);
      final lastDay = DateTime(target.year, target.month + 1, 0).day;
      _selectedDate = DateTime(
          target.year, target.month, day.clamp(1, lastDay).toInt());
    });
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.isSelected,
    required this.isToday,
    required this.tasks,
    required this.onTap,
  });

  final DateTime date;
  final bool isSelected;
  final bool isToday;
  final List<CareTask> tasks;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasRoutine = tasks.any((t) => t.kind == CareTaskKind.routine);
    final hasOneOff = tasks.any((t) => t.kind == CareTaskKind.oneOff);
    final hasUrgent = tasks.any((t) => t.priority == CarePriority.urgent);
    final indicatorColor = hasUrgent ? PawColors.rose : PawColors.purple;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? PawColors.purple : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: isToday && !isSelected
              ? Border.all(color: PawColors.purple.withValues(alpha: 0.55))
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : PawColors.ink,
              ),
            ),
            SizedBox(
              height: 8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (hasRoutine)
                    Icon(Icons.repeat,
                        size: 7,
                        color: isSelected ? Colors.white : indicatorColor),
                  if (hasRoutine) const SizedBox(width: 2),
                  if (hasOneOff)
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white : indicatorColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  if (hasUrgent) ...[
                    const SizedBox(width: 2),
                    Icon(Icons.error,
                        size: 8,
                        color: isSelected ? Colors.white : indicatorColor),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
