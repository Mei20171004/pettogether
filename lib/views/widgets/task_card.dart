import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/care_catalog.dart';
import '../../models/models.dart';
import '../../store/care_store.dart';
import '../../theme/app_theme.dart';
import 'common.dart';

/// A single care task card with claim/request/complete actions, ported from
/// `TaskCardView.swift`.
class TaskCard extends StatelessWidget {
  const TaskCard({super.key, required this.task});

  final CareTask task;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CareStore>();
    final language = context.watch<AppLanguageStore>().language;

    final isMutating = store.mutatingTaskIDs.contains(task.id);
    final stateColor = _stateColor;
    final petId = task.effectivePetIds.firstOrNull ?? task.petID;
    final pet =
        store.household?.pets.where((p) => p.id == petId).firstOrNull;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _cardBackground,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: stateColor.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: PawColors.purpleDark.withValues(alpha: 0.08),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CareIcon(
                    icon: categoryIcon(task.category),
                    color: categoryAccent(task.category),
                    size: 48,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: PawColors.ink,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            const Icon(Icons.schedule,
                                size: 13, color: PawColors.muted),
                            const SizedBox(width: 4),
                            Text(
                              _timeText(language, task.dueTime),
                              style: const TextStyle(
                                  fontSize: 12, color: PawColors.muted),
                            ),
                            if (_doseLine(store) != null) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _doseLine(store)!,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: PawColors.ink,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            if (pet != null)
                              PetTag(
                                title:
                                    '${petTypeEmoji(pet.type)} ${pet.name}',
                                icon: Icons.pets,
                                color: PawColors.green,
                              ),
                            PetTag(
                              title: task.kind == CareTaskKind.routine
                                  ? L10n.text(language, 'Routine', '繰り返し',
                                      '例行', '루틴')
                                  : L10n.text(language, 'One-time', '一回のみ',
                                      '一次性', '일회성'),
                              icon: task.kind == CareTaskKind.routine
                                  ? Icons.repeat
                                  : Icons.add_circle_outline,
                              color: task.kind == CareTaskKind.routine
                                  ? PawColors.purple
                                  : PawColors.blue,
                            ),
                            if (task.priority == CarePriority.urgent)
                              PetTag(
                                title: L10n.text(
                                    language, 'Urgent', '緊急', '紧急', '긴급'),
                                icon: Icons.error,
                                color: PawColors.rose,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(_stateIcon, size: 20, color: stateColor),
                ],
              ),
              const SizedBox(height: 12),
              Divider(height: 1, color: PawColors.purple.withValues(alpha: 0.08)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(_stateIcon, size: 15, color: stateColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _stateMessage(language, store),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: PawColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _ActionButtons(task: task),
            ],
          ),
          if (isMutating)
            Positioned(
              top: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: stateColor,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  IconData get _stateIcon {
    switch (task.status) {
      case CareTaskStatus.unclaimed:
        return task.assignmentRequest == null
            ? Icons.help_outline
            : Icons.send;
      case CareTaskStatus.claimed:
        return Icons.how_to_reg;
      case CareTaskStatus.completed:
        return Icons.verified;
      case CareTaskStatus.skipped:
        return Icons.skip_next;
    }
  }

  Color get _stateColor {
    switch (task.status) {
      case CareTaskStatus.unclaimed:
        return PawColors.rose;
      case CareTaskStatus.claimed:
        return PawColors.purple;
      case CareTaskStatus.completed:
        return PawColors.green;
      case CareTaskStatus.skipped:
        return PawColors.muted;
    }
  }

  Color get _cardBackground {
    switch (task.status) {
      case CareTaskStatus.unclaimed:
        return Colors.white.withValues(alpha: 0.97);
      case CareTaskStatus.claimed:
        return PawColors.lavender.withValues(alpha: 0.92);
      case CareTaskStatus.completed:
        return PawColors.green.withValues(alpha: 0.10);
      case CareTaskStatus.skipped:
        return Colors.white.withValues(alpha: 0.55);
    }
  }

  String _stateMessage(AppLanguage language, CareStore store) {
    final currentID = store.currentCaregiver?.id;
    switch (task.status) {
      case CareTaskStatus.unclaimed:
        final request = task.assignmentRequest;
        if (request != null) {
          if (request.requestedToID == currentID) {
            return switch (language) {
              AppLanguage.japanese =>
                '${request.requestedByNameSnapshot}さんからの依頼',
              AppLanguage.chinese => '${request.requestedByNameSnapshot}请你来负责',
              AppLanguage.korean =>
                '${request.requestedByNameSnapshot}님이 맡아달라고 요청했어요',
              AppLanguage.english =>
                '${request.requestedByNameSnapshot} asked you to take this',
            };
          }
          if (request.mode == AssignmentMode.open) {
            return L10n.text(language, 'Open to anyone in the household',
                '家族の誰でも引き受けられます', '对家里的任何人开放', '가족 누구나 맡을 수 있습니다');
          }
          return switch (language) {
            AppLanguage.japanese =>
              '${request.requestedToNameSnapshot ?? '担当者'}さんの返事待ち',
            AppLanguage.chinese =>
              '等待${request.requestedToNameSnapshot ?? '家人'}回复',
            AppLanguage.korean =>
              '${request.requestedToNameSnapshot ?? '가족'}님의 답변을 기다리는 중',
            AppLanguage.english =>
              'Waiting for ${request.requestedToNameSnapshot ?? 'a caregiver'}',
          };
        }
        return L10n.text(language, 'Nobody has claimed this yet',
            'まだ担当者がいません', '还没有人认领', '아직 담당자가 없습니다');
      case CareTaskStatus.claimed:
        if (task.assigneeID == currentID) {
          return L10n.text(
              language, 'You’re on it', 'あなたが担当中', '你在负责', '당신이 맡고 있어요');
        }
        return switch (language) {
          AppLanguage.japanese =>
            '${task.assigneeNameSnapshot ?? '担当者'}さんが担当中',
          AppLanguage.chinese => '${task.assigneeNameSnapshot ?? '家人'}正在负责',
          AppLanguage.korean =>
            '${task.assigneeNameSnapshot ?? '가족'}님이 맡고 있어요',
          AppLanguage.english =>
            '${task.assigneeNameSnapshot ?? 'A caregiver'} is on it',
        };
      case CareTaskStatus.completed:
        // A completion the server has not confirmed is not evidence the dose
        // happened. Believing a pet was already dosed is the one failure here
        // that could leave it dosed twice, or not at all.
        if (_isMedication(store) && !task.isServerConfirmed) {
          return L10n.text(
            language,
            "Not confirmed yet — you're offline",
            'オフラインのため未確認',
            '离线中，尚未确认',
            '오프라인 상태라 미확인',
          );
        }
        final name = task.completedBy ?? 'A caregiver';
        final at = task.completedAt;
        if (at != null) {
          final time = _timeText(language, at);
          return switch (language) {
            AppLanguage.japanese => '$nameさんが完了 · $time',
            AppLanguage.chinese => '$name已完成 · $time',
            AppLanguage.korean => '$name님이 완료 · $time',
            AppLanguage.english => 'Done by $name · $time',
          };
        }
        return switch (language) {
          AppLanguage.japanese => '$nameさんが完了',
          AppLanguage.chinese => '$name已完成',
          AppLanguage.korean => '$name님이 완료',
          AppLanguage.english => 'Done by $name',
        };
      case CareTaskStatus.skipped:
        final reason = task.skipReason;
        if (reason == null) {
          return L10n.text(language, 'Skipped for today', '今日はスキップ済み',
              '今天已跳过', '오늘은 건너뜀');
        }
        final label = L10n.skipReasonTitle(language, reason);
        final note = task.skipNote;
        return note == null || note.isEmpty ? label : '$label · $note';
    }
  }

  /// True when this task is a dose of a medication course.
  bool _isMedication(CareStore store) => store.planForTask(task) != null;

  /// "Half a tablet · after food", read off the routine behind the dose.
  String? _doseLine(CareStore store) {
    final routine = store.routineForTask(task);
    final dose = routine?.doseText;
    if (dose == null || dose.isEmpty) return null;
    final how = routine?.doseInstructions;
    return how == null || how.isEmpty ? dose : '$dose · $how';
  }

  String _timeText(AppLanguage language, DateTime date) {
    return DateFormat.jm(language.rawValue).format(date);
  }
}

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({required this.task});

  final CareTask task;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CareStore>();
    final language = context.watch<AppLanguageStore>().language;
    final currentID = store.currentCaregiver?.id;

    switch (task.status) {
      case CareTaskStatus.unclaimed:
        return _UnclaimedActions(task: task);
      case CareTaskStatus.claimed:
        if (task.assigneeID == currentID) {
          // Recording a dose before its time is nearly always a mis-tap on the
          // wrong row, so the button waits rather than erroring afterwards.
          final tooEarly = store.planForTask(task) != null &&
              task.dueTime.isAfter(DateTime.now());
          final at = DateFormat.jm(language.rawValue).format(task.dueTime);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton(
                style: pawCompactButtonStyle(PawColors.green, filled: true),
                onPressed: tooEarly ? null : () => store.complete(task),
                child: Text(L10n.text(
                    language, 'Mark done', '完了にする', '标记完成', '완료로 표시')),
              ),
              if (tooEarly) ...[
                const SizedBox(height: 6),
                Text(
                  L10n.text(
                    language,
                    'You can record it from $at',
                    '$at から記録できます',
                    '$at 起可记录',
                    '$at 부터 기록할 수 있어요',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: PawColors.muted),
                ),
              ],
            ],
          );
        }
        return const SizedBox.shrink();
      case CareTaskStatus.completed:
        return const SizedBox.shrink();
      case CareTaskStatus.skipped:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: pawCompactButtonStyle(PawColors.muted),
            onPressed: () => store.restoreTaskOccurrence(task),
            child: Text(L10n.text(language, 'Restore task', 'タスクを戻す',
                '恢复任务', '작업 복원')),
          ),
        );
    }
  }
}

class _UnclaimedActions extends StatelessWidget {
  const _UnclaimedActions({required this.task});

  final CareTask task;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CareStore>();
    final language = context.watch<AppLanguageStore>().language;
    final currentID = store.currentCaregiver?.id;
    final request = task.assignmentRequest;

    if (request?.requestedToID == currentID) {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton(
              style: pawCompactButtonStyle(PawColors.muted),
              onPressed: () => store.declineRequest(task),
              child: Text(L10n.text(language, 'Decline', '断る', '拒绝', '거절')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              style: pawCompactButtonStyle(PawColors.purple, filled: true),
              onPressed: () => store.acceptRequest(task),
              child: Text(L10n.text(language, 'Accept', '引き受ける', '接受', '수락')),
            ),
          ),
        ],
      );
    }

    if (request?.requestedByID == currentID) {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton(
              style: pawCompactButtonStyle(PawColors.muted),
              onPressed: () => store.cancelRequest(task),
              child: Text(L10n.text(
                  language, 'Cancel request', '依頼を取り消す', '取消请求', '요청 취소')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              style: pawCompactButtonStyle(PawColors.purple, filled: true),
              onPressed: () => store.claim(task),
              child: Text(
                  L10n.text(language, 'I’ll do it', '私がやる', '我来做', '제가 할게요')),
            ),
          ),
        ],
      );
    }

    final otherCaregivers =
        store.caregivers.where((c) => c.id != currentID).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton(
          style: pawCompactButtonStyle(PawColors.purple, filled: true),
          onPressed: () => store.claim(task),
          child: Text(
              L10n.text(language, 'I’ll do it', '私がやる', '我来做', '제가 할게요')),
        ),
        const SizedBox(height: 10),
        ElevatedButton(
          style: pawCompactButtonStyle(PawColors.blue),
          onPressed: () => store.requestAnyone(task),
          child: Text(L10n.text(
              language, 'Let anyone take it', '誰でも引き受ける', '让任何人接取', '누구나 맡기')),
        ),
        const SizedBox(height: 10),
        ElevatedButton(
          style: pawCompactButtonStyle(PawColors.blue),
          onPressed: otherCaregivers.isEmpty
              ? null
              : () => _showCaregiverPicker(context, otherCaregivers, store),
          child: Text(L10n.text(
              language, 'Choose a person', '担当者を指定', '指定负责人', '담당자 지정')),
        ),
        if (task.kind == CareTaskKind.routine) ...[
          const SizedBox(height: 10),
          ElevatedButton(
            style: pawCompactButtonStyle(PawColors.muted),
            onPressed: () => _skip(context, store),
            child: Text(L10n.text(
                language, 'Skip today', '今日はスキップ', '今天跳过', '오늘 건너뛰기')),
          ),
        ],
      ],
    );
  }

  /// Skipping a walk needs no explanation; skipping a dose does. For
  /// medication the reason is asked for and stored, because "refused it twice,
  /// vomited once" is something a vet can act on.
  Future<void> _skip(BuildContext context, CareStore store) async {
    if (store.planForTask(task) == null) {
      await store.skipTaskOccurrence(task);
      return;
    }
    final language = context.read<AppLanguageStore>().language;
    final choice = await showModalBottomSheet<_SkipChoice>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _SkipReasonSheet(language: language),
    );
    if (choice == null) return;
    await store.skipTaskOccurrence(
      task,
      reason: choice.reason,
      note: choice.note,
    );
  }

  Future<void> _showCaregiverPicker(
    BuildContext context,
    List<Caregiver> caregivers,
    CareStore store,
  ) async {
    final language = context.read<AppLanguageStore>().language;
    final selected = await showModalBottomSheet<Caregiver>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Text(
                  L10n.text(language, 'Choose who should take this',
                      '担当者を選択', '选择负责人', '담당자 선택'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: PawColors.ink,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  L10n.text(
                    language,
                    'Only this caregiver will be asked, and they can accept or decline.',
                    'この人だけに依頼します。引き受けるか断るかを選べます。',
                    '只会询问这位家人，他/她可以选择接受或拒绝。',
                    '이 사람에게만 요청하며, 수락하거나 거절할 수 있습니다.',
                  ),
                  style: const TextStyle(fontSize: 13, color: PawColors.muted),
                ),
              ),
              for (final caregiver in caregivers)
                ListTile(
                  leading: const Icon(Icons.person, color: PawColors.purple),
                  title: Text(caregiver.displayName),
                  onTap: () => Navigator.pop(context, caregiver),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (selected != null) {
      store.request(task, selected);
    }
  }
}

class _SkipChoice {
  const _SkipChoice(this.reason, this.note);
  final MedicationSkipReason reason;
  final String? note;
}

/// Asks why a dose was not given.
class _SkipReasonSheet extends StatefulWidget {
  const _SkipReasonSheet({required this.language});

  final AppLanguage language;

  @override
  State<_SkipReasonSheet> createState() => _SkipReasonSheetState();
}

class _SkipReasonSheetState extends State<_SkipReasonSheet> {
  MedicationSkipReason? _reason;
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final needsNote = _reason?.requiresNote ?? false;
    final canConfirm = _reason != null &&
        (!needsNote || _noteController.text.trim().isNotEmpty);

    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Text(
                L10n.text(language, 'Why was it skipped?', 'スキップの理由は？',
                    '为什么跳过？', '건너뛴 이유는?'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: PawColors.ink,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                L10n.text(
                  language,
                  'The reason is kept with the dose, so a vet can see the pattern later.',
                  '理由は記録に残り、後で獣医が経過を確認できます。',
                  '原因会记录下来，之后兽医可以看到规律。',
                  '이유가 기록에 남아 나중에 수의사가 확인할 수 있습니다.',
                ),
                style: const TextStyle(fontSize: 13, color: PawColors.muted),
              ),
            ),
            for (final reason in MedicationSkipReason.values)
              ListTile(
                onTap: () => setState(() => _reason = reason),
                leading: Icon(
                  _reason == reason
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: _reason == reason ? PawColors.purple : PawColors.muted,
                ),
                title: Text(
                  L10n.skipReasonTitle(language, reason),
                  style: TextStyle(
                    color: PawColors.ink,
                    fontWeight: _reason == reason
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ),
            if (needsNote)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                child: TextField(
                  controller: _noteController,
                  maxLength: CareTask.maxSkipNoteLength,
                  maxLines: 2,
                  onChanged: (_) => setState(() {}),
                  decoration: petFieldDecoration(
                    hintText: L10n.text(language, 'What happened?',
                        '何がありましたか？', '发生了什么？', '무슨 일이 있었나요?'),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: ElevatedButton(
                style: pawPrimaryButtonStyle(),
                onPressed: canConfirm
                    ? () => Navigator.pop(
                          context,
                          _SkipChoice(
                            _reason!,
                            _noteController.text.trim().isEmpty
                                ? null
                                : _noteController.text.trim(),
                          ),
                        )
                    : null,
                child: Text(L10n.text(language, 'Record skip', 'スキップを記録',
                    '记录跳过', '건너뜀 기록')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
