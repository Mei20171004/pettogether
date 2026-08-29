import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/health.dart';
import '../../models/models.dart';
import '../../store/care_store.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import 'medication_course_editor_view.dart';

/// A single medication course: what it is, how it is given, how much of it has
/// actually happened, and every dose anyone recorded.
class MedicationPlanDetailView extends StatefulWidget {
  const MedicationPlanDetailView({super.key, required this.planId});

  final String planId;

  @override
  State<MedicationPlanDetailView> createState() =>
      _MedicationPlanDetailViewState();
}

class _MedicationPlanDetailViewState extends State<MedicationPlanDetailView> {
  int _windowDays = 7;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CareStore>();
    final language = context.watch<AppLanguageStore>().language;
    final plan = store.medicationPlans
        .where((p) => p.id == widget.planId)
        .firstOrNull;

    if (plan == null) {
      // The course was deleted, possibly on another device.
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(backgroundColor: Colors.transparent),
        body: Stack(
          children: [
            const PetScreenBackground(),
            Center(
              child: Text(
                L10n.text(language, 'This course is no longer available.',
                    'この服薬は見つかりません。', '这个疗程已不存在。', '이 복약 정보를 찾을 수 없습니다.'),
                style: const TextStyle(color: PawColors.muted),
              ),
            ),
          ],
        ),
      );
    }

    final running = store.isPlanRunning(plan);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(plan.name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) => switch (value) {
              'edit' => _edit(plan),
              'stop' => _confirmStop(store, plan, language),
              _ => _confirmDelete(store, plan, language),
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'edit',
                child: Text(L10n.text(language, 'Edit', '編集', '编辑', '편집')),
              ),
              if (running)
                PopupMenuItem(
                  value: 'stop',
                  child: Text(L10n.text(
                      language, 'Stop course', '服薬を終了', '停止疗程', '복약 종료')),
                ),
              PopupMenuItem(
                value: 'delete',
                child: Text(
                  L10n.text(language, 'Delete', '削除', '删除', '삭제'),
                  style: const TextStyle(color: PawColors.rose),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          const PetScreenBackground(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 32),
              children: [
                _summaryCard(store, plan, language, running),
                const SizedBox(height: 18),
                _adherenceCard(store, plan, language),
                const SizedBox(height: 18),
                PetSectionTitle(
                  title: L10n.text(
                      language, 'Dose history', '投与履歴', '服药历史', '투여 기록'),
                ),
                const SizedBox(height: 12),
                _history(store, plan, language),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(
    CareStore store,
    MedicationPlan plan,
    AppLanguage language,
    bool running,
  ) {
    final dateFormat = DateFormat.yMMMd(language.rawValue);
    final window = store.courseWindow(plan.id);
    final routines = store.routinesForPlan(plan.id);
    final until = window?.end == null
        ? L10n.text(language, 'ongoing', '継続中', '长期', '계속')
        : dateFormat.format(window!.end!);

    return PetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CareIcon(
                icon: medicationFormIcon(plan.form),
                color: PawColors.rose,
                size: 48,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: PawColors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      L10n.medicationFormTitle(language, plan.form),
                      style: const TextStyle(
                          fontSize: 12, color: PawColors.muted),
                    ),
                  ],
                ),
              ),
              PetTag(
                title: running
                    ? L10n.text(language, 'Running', '服用中', '进行中', '복용 중')
                    : L10n.text(language, 'Finished', '終了', '已结束', '종료'),
                icon: running ? Icons.play_arrow : Icons.check,
                color: running ? PawColors.green : PawColors.muted,
              ),
            ],
          ),
          if (plan.purpose != null) ...[
            const SizedBox(height: 14),
            _block(L10n.text(language, 'What it is for', '目的', '用来治什么', '복용 목적'),
                plan.purpose!),
          ],
          if (plan.sideEffects != null) ...[
            const SizedBox(height: 12),
            _block(
                L10n.text(language, 'Watch for', '注意', '需要留意', '주의'),
                plan.sideEffects!,
                color: PawColors.rose),
          ],
          const SizedBox(height: 14),
          Divider(height: 1, color: PawColors.purple.withValues(alpha: 0.08)),
          const SizedBox(height: 12),
          if (window != null)
            _infoRow(
              Icons.event,
              '${dateFormat.format(window.start)} → $until',
            ),
          if (routines.isNotEmpty)
            _infoRow(Icons.repeat,
                L10n.weekdaySummary(language, routines.first.weekdays)),
          for (final routine in routines)
            _infoRow(
              Icons.access_time,
              '${routine.hour.toString().padLeft(2, '0')}:'
              '${routine.minute.toString().padLeft(2, '0')} · ${routine.doseText ?? ''}'
              '${routine.doseInstructions == null || routine.doseInstructions!.isEmpty ? '' : ' · ${routine.doseInstructions}'}',
            ),
          if (plan.remainingDoses != null)
            _infoRow(
              Icons.inventory_2_outlined,
              '${plan.remainingDoses} ${L10n.text(language, 'doses left in the box', '回分残り', '次剩余', '회 남음')}',
              color: plan.isRunningLow ? PawColors.rose : null,
            ),
        ],
      ),
    );
  }

  Widget _block(String label, String value, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color ?? PawColors.purpleDark,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
              fontSize: 13, color: PawColors.ink, height: 1.4),
        ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String text, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color ?? PawColors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: color ?? PawColors.ink),
            ),
          ),
        ],
      ),
    );
  }

  /// Given / skipped / unrecorded as one bar. The three states stay visible
  /// separately because "skipped because she vomited" and "nobody wrote it
  /// down" mean completely different things to a vet.
  Widget _adherenceCard(
    CareStore store,
    MedicationPlan plan,
    AppLanguage language,
  ) {
    final stats = store.adherence(planId: plan.id, days: _windowDays);

    return PetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  L10n.text(language, 'How it is going', '実施状況', '完成情况',
                      '진행 상황'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: PawColors.ink,
                  ),
                ),
              ),
              SegmentedButton<int>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  ButtonSegment(
                      value: 7,
                      label: Text(L10n.text(language, '7d', '7日', '7天', '7일'))),
                  ButtonSegment(
                      value: 30,
                      label:
                          Text(L10n.text(language, '30d', '30日', '30天', '30일'))),
                ],
                selected: {_windowDays},
                onSelectionChanged: (s) =>
                    setState(() => _windowDays = s.first),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (stats.isEmpty)
            Text(
              L10n.text(language, 'No doses were scheduled in this window.',
                  'この期間に予定された投与はありません。', '这段时间内没有安排用药。',
                  '이 기간에 예정된 투여가 없습니다.'),
              style: const TextStyle(fontSize: 13, color: PawColors.muted),
            )
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 12,
                child: Row(
                  children: [
                    if (stats.given > 0)
                      Expanded(
                          flex: stats.given,
                          child: Container(color: PawColors.green)),
                    if (stats.skipped > 0)
                      Expanded(
                          flex: stats.skipped,
                          child: Container(color: PawColors.yellow)),
                    if (stats.missed > 0)
                      Expanded(
                        flex: stats.missed,
                        child: Container(
                            color: PawColors.muted.withValues(alpha: 0.3)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${stats.given} ${L10n.text(language, 'of', '/', '/', '/')} ${stats.planned} '
              '${L10n.text(language, 'doses given', '回投与', '次已喂', '회 투여')} · ${stats.percent}%',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: PawColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                PetTag(
                  title:
                      '${stats.given} ${L10n.text(language, 'given', '投与', '已喂', '투여')}',
                  icon: Icons.check_circle,
                  color: PawColors.green,
                ),
                if (stats.skipped > 0)
                  PetTag(
                    title:
                        '${stats.skipped} ${L10n.text(language, 'skipped', 'スキップ', '跳过', '건너뜀')}',
                    icon: Icons.next_plan_outlined,
                    color: PawColors.yellow,
                  ),
                if (stats.missed > 0)
                  PetTag(
                    title:
                        '${stats.missed} ${L10n.text(language, 'not recorded', '未記録', '未记录', '미기록')}',
                    icon: Icons.help_outline,
                    color: PawColors.muted,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Every dose of this course anyone completed or skipped, newest first.
  /// The doses are ordinary task documents, so this is just a filtered view of
  /// the same history the rest of the app shows.
  Widget _history(
    CareStore store,
    MedicationPlan plan,
    AppLanguage language,
  ) {
    final routineIds = store.routinesForPlan(plan.id).map((r) => r.id).toSet();
    final doses = store.tasks
        .where((t) =>
            t.routineID != null &&
            routineIds.contains(t.routineID) &&
            (t.status == CareTaskStatus.completed ||
                t.status == CareTaskStatus.skipped))
        .toList()
      ..sort((a, b) => b.dueTime.compareTo(a.dueTime));

    if (doses.isEmpty) {
      return PetCard(
        child: Text(
          L10n.text(language, 'Nothing recorded yet.', 'まだ記録がありません。',
              '还没有记录。', '아직 기록이 없습니다.'),
          style: const TextStyle(fontSize: 13, color: PawColors.muted),
        ),
      );
    }

    final dateFormat = DateFormat.MMMd(language.rawValue);
    final timeFormat = DateFormat.Hm(language.rawValue);

    return PetCard(
      padding: 8,
      child: Column(
        children: [
          for (final dose in doses)
            ListTile(
              dense: true,
              leading: Icon(
                dose.status == CareTaskStatus.completed
                    ? Icons.check_circle
                    : Icons.next_plan_outlined,
                color: doseStateColor(dose.status),
              ),
              title: Text(
                '${dateFormat.format(dose.dueTime)} '
                '${timeFormat.format(dose.dueTime)}'
                '${store.routineForTask(dose)?.doseText == null ? '' : ' · ${store.routineForTask(dose)!.doseText}'}',
                style: const TextStyle(fontSize: 13, color: PawColors.ink),
              ),
              subtitle: Text(
                _historyDetail(dose, language, timeFormat),
                style: const TextStyle(fontSize: 12, color: PawColors.muted),
              ),
            ),
        ],
      ),
    );
  }

  String _historyDetail(
    CareTask dose,
    AppLanguage language,
    DateFormat timeFormat,
  ) {
    final parts = <String>[];
    if (dose.status == CareTaskStatus.completed) {
      final who = dose.completedBy;
      final at = dose.completedAt;
      if (who != null) {
        parts.add(at == null ? who : '$who · ${timeFormat.format(at)}');
      }
    }
    final reason = dose.skipReason;
    if (reason != null) parts.add(L10n.skipReasonTitle(language, reason));
    final note = dose.skipNote;
    if (note != null && note.isNotEmpty) parts.add(note);
    return parts.join(' · ');
  }

  void _edit(MedicationPlan plan) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => MedicationCourseEditorView(planId: plan.id),
      ),
    );
  }

  /// Stopping is irreversible for future doses, so it says exactly what it is
  /// about to cancel and what it is keeping.
  Future<void> _confirmStop(
    CareStore store,
    MedicationPlan plan,
    AppLanguage language,
  ) async {
    final remaining = store.remainingDoseCount(plan);
    final recorded = store.recordedDoseCount(plan);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(L10n.text(
            language, 'Stop this course?', '服薬を終了しますか？', '停止这个疗程？', '복약을 종료할까요?')),
        content: Text(
          L10n.text(
            language,
            '$remaining upcoming doses will stop appearing. The $recorded doses already recorded stay in the history.',
            'これから予定されている$remaining回の投与は表示されなくなります。記録済みの$recorded回はそのまま残ります。',
            '接下来的 $remaining 次用药将不再出现。已记录的 $recorded 次会保留在历史里。',
            '앞으로 예정된 $remaining회의 투여가 사라집니다. 이미 기록된 $recorded회는 그대로 남습니다.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(L10n.text(language, 'Cancel', 'キャンセル', '取消', '취소')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              L10n.text(language, 'Stop course', '終了する', '停止疗程', '종료'),
              style: const TextStyle(color: PawColors.rose),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await store.stopMedicationCourse(plan);
  }

  Future<void> _confirmDelete(
    CareStore store,
    MedicationPlan plan,
    AppLanguage language,
  ) async {
    final recorded = store.recordedDoseCount(plan);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(L10n.text(language, 'Delete this course?', '削除しますか？',
            '删除这个疗程？', '삭제할까요?')),
        content: Text(
          L10n.text(
            language,
            'This also removes the $recorded recorded doses. To keep the history, stop the course instead.',
            '記録済みの$recorded回も一緒に削除されます。履歴を残したい場合は「終了」を選んでください。',
            '已记录的 $recorded 次用药也会一并删除。想保留历史请改用「停止疗程」。',
            '기록된 $recorded회도 함께 삭제됩니다. 기록을 남기려면 종료를 선택하세요.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(L10n.text(language, 'Cancel', 'キャンセル', '取消', '취소')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              L10n.text(language, 'Delete', '削除', '删除', '삭제'),
              style: const TextStyle(color: PawColors.rose),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final removed = await store.deleteMedicationCourse(plan);
    if (removed && mounted) Navigator.of(context).pop();
  }
}
