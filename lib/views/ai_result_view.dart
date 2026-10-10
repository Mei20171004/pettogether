import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/ai_plan.dart';
import '../models/care_catalog.dart';
import '../models/models.dart';
import '../store/care_store.dart';
import '../store/pro_access.dart';
import '../theme/app_theme.dart';
import 'widgets/common.dart';
import 'pro_view.dart';

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
  String? _saveError;
  int _savedWeights = 0;
  int _savedTasks = 0;
  String? _saveSession;

  /// Second line of defence: this screen is only reachable through the gated AI
  /// button, but if the quota was already exceeded the write is refused here
  /// too rather than trusting the caller.
  Future<void> _confirm(CareStore store) async {
    if (_saving) return;
    final access = context.read<ProAccess>();
    if (!access.hasAi) {
      final language = context.read<AppLanguageStore>().language;
      await showProPaywall(
        context,
        reason: L10n.text(
          language,
          'AI care entry requires the AI subscription.',
          'AIケア入力にはAIプランが必要です。',
          '使用 AI 护理录入需要订阅 AI 功能。',
          'AI 케어 입력에는 AI 구독이 필요합니다.',
        ),
        feature: ProFeature.ai,
      );
      return;
    }
    final language = context.read<AppLanguageStore>().language;
    final session = '${store.household?.id}|${store.currentCaregiver?.id}';
    if (store.household == null ||
        store.currentCaregiver == null ||
        _saveSession != null && _saveSession != session) {
      setState(
        () => _saveError = L10n.text(
          language,
          'Your household or account changed. Go back and generate a new plan.',
          '家族またはアカウントが変更されました。戻ってプランを作り直してください。',
          '家庭或账号已变更，请返回并重新生成计划。',
          '가족 또는 계정이 변경되었습니다. 돌아가 새 계획을 만드세요.',
        ),
      );
      return;
    }
    _saveSession = session;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final pets = store.household!.pets;
    try {
      while (_savedWeights < widget.result.petWeights.length) {
        if ('${store.household?.id}|${store.currentCaregiver?.id}' != session) {
          throw StateError('Care session changed during AI save.');
        }
        final weight = widget.result.petWeights[_savedWeights];
        final pet = _matchPet(pets, weight.petName);
        if (pet == null) {
          if (mounted) {
            setState(() => _saveError = L10n.text(language,
                'No pet matches ${weight.petName}. Go back and correct the pet name.',
                '${weight.petName}と一致するペットがいません。戻って名前を修正してください。',
                '没有找到名为${weight.petName}的宠物，请返回并修改宠物名称。',
                '${weight.petName}와 일치하는 반려동물이 없습니다. 돌아가 이름을 수정하세요.'));
          }
          return;
        }
        if (!await store.updatePet(pet.copyWith(weightKg: weight.weightKg))) {
          throw StateError('Pet weight save failed.');
        }
        _savedWeights++;
      }
      final today = DateTime.now();
      while (_savedTasks < widget.result.tasks.length) {
        if ('${store.household?.id}|${store.currentCaregiver?.id}' != session) {
          throw StateError('Care session changed during AI save.');
        }
        final task = widget.result.tasks[_savedTasks];
        final petID = _matchPet(pets, task.petName)?.id;
        final date = task.kind == CareTaskKind.oneOff && task.date != null
            ? DateTime(
                task.date!.year,
                task.date!.month,
                task.date!.day,
                task.hour,
                task.minute,
              )
            : DateTime(
                today.year,
                today.month,
                today.day,
                task.hour,
                task.minute,
              );
        final saved = await store.addTask(
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
        if (!saved) throw StateError('Care task save failed.');
        _savedTasks++;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            L10n.text(
              language,
              'Care plan added.',
              'ケアプランを追加しました。',
              '护理计划已录入。',
              '돌봄 계획이 추가되었습니다.',
            ),
          ),
        ),
      );
      Navigator.of(context).pop();
    } catch (error, stackTrace) {
      debugPrint('AI care plan save failed: $error\n$stackTrace');
      if (!mounted) return;
      final remaining =
          widget.result.tasks.length -
          _savedTasks +
          widget.result.petWeights.length -
          _savedWeights;
      setState(
        () => _saveError = L10n.text(
          language,
          '$remaining items were not saved. Check your connection and household access, then retry. Saved items will not be added again.',
          '$remaining件を保存できませんでした。通信状況と家族のアクセス権を確認して再試行してください。保存済みの項目は重複追加しません。',
          '还有 $remaining 项未保存。请检查网络和家庭访问权限后重试；已保存的项目不会重复添加。',
          '$remaining개 항목이 저장되지 않았습니다. 연결과 가족 접근 권한을 확인하고 다시 시도하세요. 저장된 항목은 다시 추가하지 않습니다.',
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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

    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(
            L10n.text(
              language,
              'AI care plan',
              'AIケアプラン',
              'AI 护理计划',
              'AI 케어 플랜',
            ),
          ),
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
                          if (widget.result.tasks.isEmpty &&
                              widget.result.petWeights.isEmpty)
                            Text(
                              L10n.text(
                                language,
                                'No care tasks or weight updates found. Go back and describe what to add.',
                                '追加できるタスクや体重が見つかりませんでした。戻って内容を入力してください。',
                                '没有识别到护理任务或体重更新，请返回并说明要添加的内容。',
                                '돌봄 작업이나 체중 업데이트가 없습니다. 돌아가 추가할 내용을 입력하세요.',
                              ),
                            ),
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
                  if (_saveError != null)
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Text(
                        _saveError!,
                        key: const ValueKey('ai_save_error'),
                        style: const TextStyle(color: PawColors.rose),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
                    child: ElevatedButton(
                      style: pawPrimaryButtonStyle(),
                      onPressed:
                          _saving ||
                              widget.result.tasks.isEmpty &&
                                  widget.result.petWeights.isEmpty
                          ? null
                          : () => _confirm(store),
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              L10n.text(
                                language,
                                _saveError == null
                                    ? 'Confirm & add'
                                    : 'Retry remaining items',
                                _saveError == null ? '確定して追加' : '未保存の項目を再試行',
                                _saveError == null ? '确定并录入' : '重试未保存项目',
                                _saveError == null ? '확인 후 추가' : '남은 항목 다시 시도',
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
