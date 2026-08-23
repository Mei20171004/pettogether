import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/ai_plan.dart';
import '../models/care_catalog.dart';
import '../models/models.dart';
import '../store/care_store.dart';
import '../theme/app_theme.dart';
import 'widgets/common.dart';

/// Shows the tasks the AI parsed from a free-text instruction, and confirms
/// them into the household in one batch.
class AiResultView extends StatefulWidget {
  const AiResultView({super.key, required this.result});

  final AiParseResult result;

  @override
  State<AiResultView> createState() => _AiResultViewState();
}

class _AiResultViewState extends State<AiResultView> {
  bool _saving = false;

  Future<void> _confirm(CareStore store) async {
    setState(() => _saving = true);
    final pets = store.household?.pets ?? const <Pet>[];

    for (final weight in widget.result.petWeights) {
      final pet = _matchPet(pets, weight.petName);
      if (pet != null) {
        await store.updatePet(pet.copyWith(weightKg: weight.weightKg));
      }
    }

    final today = DateTime.now();
    for (final task in widget.result.tasks) {
      final petID = _matchPet(pets, task.petName)?.id;
      final date = task.kind == CareTaskKind.oneOff && task.date != null
          ? DateTime(task.date!.year, task.date!.month, task.date!.day,
              task.hour, task.minute)
          : DateTime(today.year, today.month, today.day, task.hour, task.minute);
      await store.addTask(
        title: task.title,
        category: task.category,
        kind: task.kind,
        priority: CarePriority.normal,
        date: date,
        frequency: task.frequency,
        weekdays: task.weekdays,
        interval: task.interval,
        petID: petID,
      );
    }

    if (mounted) Navigator.of(context).pop();
  }

  Pet? _matchPet(List<Pet> pets, String? name) {
    if (name == null || name.trim().isEmpty) return null;
    final needle = name.trim().toLowerCase();
    for (final pet in pets) {
      if (pet.name.trim().toLowerCase() == needle) return pet;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CareStore>();
    final language = context.watch<AppLanguageStore>().language;
    final pets = store.household?.pets ?? const <Pet>[];

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(L10n.text(language, 'AI care plan', 'AIケアプラン', 'AI 护理计划',
            'AI 케어 플랜')),
      ),
      body: Stack(
        children: [
          const PetScreenBackground(),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${widget.result.tasks.length} ${L10n.text(language, 'tasks found', '件のタスク', '个任务', '개의 할 일')}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: PawColors.muted,
                          ),
                        ),
                        const SizedBox(height: 12),
                        for (final task in widget.result.tasks)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _taskCard(task, language, pets),
                          ),
                        if (widget.result.petWeights.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          for (final weight in widget.result.petWeights)
                            _weightCard(weight, language),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
                  child: ElevatedButton(
                    style: pawPrimaryButtonStyle(),
                    onPressed: _saving ? null : () => _confirm(store),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(L10n.text(language, 'Confirm & add', '確定して追加',
                            '确定并录入', '확인 후 추가')),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _taskCard(AiParsedTask task, AppLanguage language, List<Pet> pets) {
    final pet = _matchPet(pets, task.petName);
    final color = categoryAccent(task.category);
    return PetCard(
      padding: 14,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CareIcon(icon: categoryIcon(task.category), color: color, size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: PawColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  L10n.categoryTitle(language, task.category),
                  style: TextStyle(fontSize: 12, color: color),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    _time(task.hour, task.minute),
                    _frequencyLabel(task, language),
                    if (pet != null) '${petTypeEmoji(pet.type)} ${pet.name}',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 12, color: PawColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _weightCard(AiParsedPetWeight weight, AppLanguage language) {
    return PetCard(
      padding: 14,
      child: Row(
        children: [
          const CareIcon(icon: Icons.monitor_weight_outlined,
              color: PawColors.blue, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${weight.petName} · ${weight.weightKg} kg',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: PawColors.ink),
            ),
          ),
        ],
      ),
    );
  }

  String _time(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  String _frequencyLabel(AiParsedTask task, AppLanguage language) {
    return switch (task.frequency) {
      CareRoutineFrequency.daily =>
        L10n.text(language, 'daily', '毎日', '每天', '매일'),
      CareRoutineFrequency.selectedDays =>
        L10n.text(language, 'selected days', '指定日', '指定星期', '지정 요일'),
      CareRoutineFrequency.intervalDays =>
        L10n.text(language, 'every ${task.interval} days', '${task.interval}日ごと',
            '每 ${task.interval} 天', '${task.interval}일마다'),
      CareRoutineFrequency.intervalWeeks =>
        L10n.text(language, 'every ${task.interval} weeks', '${task.interval}週間ごと',
            '每 ${task.interval} 周', '${task.interval}주마다'),
      CareRoutineFrequency.intervalMonths => L10n.text(
          language,
          'every ${task.interval} months',
          '${task.interval}か月ごと',
          '每 ${task.interval} 个月',
          '${task.interval}개월마다'),
      CareRoutineFrequency.intervalYears =>
        L10n.text(language, 'every ${task.interval} years', '${task.interval}年ごと',
            '每 ${task.interval} 年', '${task.interval}년마다'),
      CareRoutineFrequency.nthWeekday => L10n.text(
          language,
          'week ${task.interval} of month',
          '毎月第${task.interval}週',
          '每月第 ${task.interval} 周',
          '매월 ${task.interval}번째 주'),
    };
  }
}
