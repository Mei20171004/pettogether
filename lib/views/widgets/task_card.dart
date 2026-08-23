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
    final pet =
        store.household?.pets.where((p) => p.id == task.petID).firstOrNull;

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
    }
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
          return SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: pawCompactButtonStyle(PawColors.green, filled: true),
              onPressed: () => store.complete(task),
              child: Text(L10n.text(
                  language, 'Mark done', '完了にする', '标记完成', '완료로 표시')),
            ),
          );
        }
        return const SizedBox.shrink();
      case CareTaskStatus.completed:
        return const SizedBox.shrink();
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
      ],
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
