import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n/l10n.dart';
import '../models/care_catalog.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../store/care_store.dart';
import '../theme/app_theme.dart';
import 'pro_view.dart';
import 'widgets/common.dart';
import 'widgets/pet_species_icon.dart';

/// "Manage my household": the family organization chart, invitation sharing,
/// join-request review, notifications, per-pet care cards, and Pro entry.
class ManageHouseholdView extends StatelessWidget {
  const ManageHouseholdView({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CareStore>();
    final language = context.watch<AppLanguageStore>().language;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(L10n.text(language, 'Family', '家族', '家庭', '가족')),
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
                    _householdHeader(store, language),
                    const SizedBox(height: 18),
                    if (store.isOwner) ...[
                      _invitationCard(context, store, language),
                      const SizedBox(height: 18),
                      _joinRequestsCard(context, store, language),
                      const SizedBox(height: 18),
                    ],
                    _membersSection(context, store, language),
                    const SizedBox(height: 18),
                    _notificationsCard(context, store, language),
                    const SizedBox(height: 18),
                    _petsSection(context, store, language),
                    const SizedBox(height: 18),
                    _proCard(context, language),
                    const SizedBox(height: 24),
                    _signOutButton(language),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _householdHeader(CareStore store, AppLanguage language) {
    final household = store.household;
    return PetCard(
      child: Row(
        children: [
          const CareIcon(icon: Icons.home, color: PawColors.purple, size: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  household?.name ?? '—',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: PawColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  L10n.text(
                    language,
                    store.isOwner
                        ? 'You are the owner'
                        : 'Shared with ${(store.caregivers.length - 1).clamp(0, 999)} other${store.caregivers.length > 2 ? 's' : ''}',
                    store.isOwner
                        ? 'あなたがオーナーです'
                        : '他 ${(store.caregivers.length - 1).clamp(0, 999)} 人と共有中',
                    store.isOwner ? '你是房主' : '与 ${(store.caregivers.length - 1).clamp(0, 999)} 位家人共享',
                    store.isOwner
                        ? '당신이 소유자입니다'
                        : '다른 ${(store.caregivers.length - 1).clamp(0, 999)}명과 공유 중',
                  ),
                  style: const TextStyle(fontSize: 12, color: PawColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Invitation sharing (owner only): one-time 24h link + QR code
  // -------------------------------------------------------------------------

  Widget _invitationCard(
      BuildContext context, CareStore store, AppLanguage language) {
    final invitation = store.activeInvitation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PetSectionTitle(
          title: L10n.text(language, 'Invite a caregiver', 'ケアギバーを招待',
              '邀请照护者', '케어기버 초대'),
          detail: null,
        ),
        const SizedBox(height: 8),
        PetCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    L10n.text(
                      language,
                      'Each invitation expires after 24 hours, works once, and still requires your approval.',
                      '招待は24時間で期限切れ、一度きり、承認が必要です。',
                      '每个邀请 24 小时后过期、只能使用一次，且仍需你的批准。',
                      '초대장은 24시간 후 만료되며, 한 번만 사용할 수 있고 승인이 필요합니다.',
                    ),
                    style: const TextStyle(
                        fontSize: 12, color: PawColors.muted),
                  ),
                  if (invitation == null) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        style: pawCompactButtonStyle(PawColors.purple,
                            filled: true),
                        onPressed:
                            store.isLoading ? null : () => store.createInvitation(),
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: Text(L10n.text(
                            language, 'Create one-time invitation',
                            '一回限りの招待を作成', '创建一次性邀请', '일회용 초대장 만들기')),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 14),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: QrImageView(
                          data: invitation.deepLink,
                          size: 180,
                          eyeStyle:
                              const QrEyeStyle(color: PawColors.purpleDark),
                          dataModuleStyle: const QrDataModuleStyle(
                              color: PawColors.purpleDark),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: PawColors.lavender.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        invitation.deepLink,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: PawColors.purpleDark,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: pawCompactButtonStyle(PawColors.purple,
                                filled: true),
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(
                                  text: invitation.deepLink));
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(L10n.text(
                                      language,
                                      'Invitation link copied.',
                                      '招待リンクをコピーしました。',
                                      '邀请链接已复制。',
                                      '초대 링크가 복사되었습니다.')),
                                ),
                              );
                            },
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            label: Text(L10n.text(language, 'Copy link',
                                'リンクをコピー', '复制链接', '링크 복사')),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton.outlined(
                          tooltip: L10n.text(language, 'Revoke invitation',
                              '招待を取り消す', '撤销邀请', '초대 취소'),
                          onPressed: store.isLoading
                              ? null
                              : () => store.revokeInvitation(),
                          icon: const Icon(Icons.block_rounded,
                              color: PawColors.rose),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
  }

  // -------------------------------------------------------------------------
  // Join requests (owner only)
  // -------------------------------------------------------------------------

  Widget _joinRequestsCard(
      BuildContext context, CareStore store, AppLanguage language) {
    final requests = store.joinRequests;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PetSectionTitle(
          title: L10n.text(
              language, 'Join requests', '参加リクエスト', '加入请求', '참여 요청'),
          detail: requests.isEmpty ? null : '${requests.length}',
        ),
        const SizedBox(height: 8),
        if (requests.isEmpty)
          PetCard(
            child: Text(
              L10n.text(
                language,
                'No pending requests.',
                '保留中のリクエストはありません。',
                '暂无待处理的请求。',
                '대기 중인 요청이 없습니다.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: PawColors.muted),
            ),
          )
        else
          for (final request in requests)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: PetCard(
                padding: 14,
                child: Column(
                  children: [
                    Row(
                      children: [
                        const CircleAvatar(
                          backgroundColor: PawColors.lavender,
                          child: Icon(Icons.person_outline_rounded,
                              color: PawColors.purple),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                request.name,
                                style: const TextStyle(
                                  color: PawColors.ink,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (request.email != null)
                                Text(
                                  request.email!,
                                  style: const TextStyle(
                                      color: PawColors.muted, fontSize: 12),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: pawCompactButtonStyle(PawColors.muted),
                            onPressed: store.isLoading
                                ? null
                                : () => store.reviewJoinRequest(
                                      request,
                                      approve: false,
                                    ),
                            child: Text(L10n.text(language, 'Decline', '断る',
                                '拒绝', '거절')),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            style: pawCompactButtonStyle(PawColors.green,
                                filled: true),
                            onPressed: store.isLoading
                                ? null
                                : () => store.reviewJoinRequest(
                                      request,
                                      approve: true,
                                    ),
                            child: Text(L10n.text(language, 'Approve',
                                '承認する', '批准', '승인')),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Family organization chart
  // -------------------------------------------------------------------------

  Widget _membersSection(
      BuildContext context, CareStore store, AppLanguage language) {
    final members = store.caregivers;
    final current = store.currentCaregiver;
    final canRemove = store.isOwner;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PetSectionTitle(
          title: L10n.text(language, 'Household members', '家族メンバー',
              '家庭成员', '가족 구성원'),
          detail: '${members.length}',
        ),
        const SizedBox(height: 12),
        PetCard(
          child: Column(
            children: [
              // The current member sits at the top of the org chart.
              if (current != null)
                _memberRow(context, store, current, language, isYou: true),
              if (current != null && members.length > 1)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Icon(Icons.arrow_drop_down,
                      size: 28, color: PawColors.purple),
                ),
              for (final member in members)
                if (member.id != current?.id)
                  _memberRow(context, store, member, language,
                      isYou: false, canRemove: canRemove),
            ],
          ),
        ),
      ],
    );
  }

  Widget _memberRow(BuildContext context, CareStore store, Caregiver member,
      AppLanguage language,
      {required bool isYou, bool canRemove = false}) {
    final initial = member.displayName.trim().isEmpty
        ? '?'
        : member.displayName.trim()[0].toUpperCase();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isYou ? PawColors.purple : PawColors.lavender,
              shape: BoxShape.circle,
            ),
            child: Text(
              initial,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isYou ? Colors.white : PawColors.purple,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              member.displayName,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: PawColors.ink,
              ),
            ),
          ),
          if (isYou)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: PawColors.lavender,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                L10n.text(language, 'You', 'あなた', '你', '나'),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: PawColors.purple,
                ),
              ),
            )
          else if (canRemove)
            IconButton(
              tooltip: L10n.text(language, 'Remove member', 'メンバーを削除',
                  '移除成员', '멤버 제거'),
              onPressed: () => _confirmRemoveMember(context, store, member),
              icon: const Icon(Icons.person_remove_outlined,
                  size: 20, color: PawColors.rose),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmRemoveMember(
      BuildContext context, CareStore store, Caregiver member) async {
    final language = context.read<AppLanguageStore>().language;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(L10n.text(language, 'Remove member', 'メンバーを削除',
            '移除成员', '멤버 제거')),
        content: Text(L10n.text(
          language,
          'Remove ${member.displayName} from this household? They will lose access immediately.',
          '${member.displayName}さんをこの家族から削除しますか？すぐにアクセスできなくなります。',
          '将 ${member.displayName} 从家庭中移除？他们将立即失去访问权限。',
          '${member.displayName}님을 가족에서 제거할까요? 즉시 접근할 수 없게 됩니다.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
                L10n.text(language, 'Cancel', 'キャンセル', '取消', '취소')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(L10n.text(
                language, 'Remove', '削除', '移除', '제거')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await store.removeMember(member);
    }
  }

  // -------------------------------------------------------------------------
  // Notifications (current member)
  // -------------------------------------------------------------------------

  Widget _notificationsCard(
      BuildContext context, CareStore store, AppLanguage language) {
    final supported = store.notificationPermission !=
        NotificationPermissionState.unavailable;
    return PetCard(
      child: Row(
        children: [
          const CareIcon(
              icon: Icons.notifications_active_outlined,
              color: PawColors.purple,
              size: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  L10n.text(language, 'Care reminders', 'ケアの通知',
                      '护理提醒', '케어 알림'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: PawColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  L10n.text(
                    language,
                    'Get notified about task handoffs and upcoming care.',
                    'タスクの引き継ぎやケアの予定を通知で受け取ります。',
                    '接收任务交接和护理安排的通知。',
                    '작업 인수인계와 예정된 케어 알림을 받습니다.',
                  ),
                  style: const TextStyle(
                      fontSize: 12, color: PawColors.muted),
                ),
              ],
            ),
          ),
          Switch(
            value: store.notificationsEnabled,
            onChanged: supported
                ? (value) {
                    if (value) {
                      store.enableNotifications();
                    } else {
                      store.disableNotifications();
                    }
                  }
                : null,
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Pets: per-pet care cards with today progress + routine list
  // -------------------------------------------------------------------------

  Widget _petsSection(
      BuildContext context, CareStore store, AppLanguage language) {
    final pets = store.household?.pets ?? const <Pet>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: PetSectionTitle(
                title: L10n.text(language, 'Pets', 'ペット', '宠物', '반려동물'),
                detail: '${pets.length}',
              ),
            ),
            TextButton.icon(
              onPressed: () => _showPetDialog(context, store, language),
              icon: const Icon(Icons.add, size: 18),
              label: Text(L10n.text(
                  language, 'Add pet', 'ペットを追加', '添加宠物', '반려동물 추가')),
              style: TextButton.styleFrom(foregroundColor: PawColors.purple),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (pets.isEmpty)
          PetCard(
            child: Text(
              L10n.text(language, 'No pets yet', 'まだペットがいません', '还没有宠物',
                  '아직 반려동물이 없습니다'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: PawColors.muted),
            ),
          )
        else
          for (final pet in pets)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _PetCareCard(pet: pet, store: store),
            ),
      ],
    );
  }

  Future<void> _showPetDialog(
    BuildContext context,
    CareStore store,
    AppLanguage language, {
    Pet? pet,
  }) async {
    final name = TextEditingController(text: pet?.name ?? '');
    final age = TextEditingController(text: pet?.ageYears?.toString() ?? '');
    final weight =
        TextEditingController(text: pet?.weightKg?.toString() ?? '');
    final habits = TextEditingController(text: pet?.habits ?? '');
    var type = pet?.type ?? PetType.cat;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(L10n.text(
              language,
              pet == null ? 'Add pet' : 'Edit pet',
              pet == null ? 'ペットを追加' : 'ペットを編集',
              pet == null ? '添加宠物' : '编辑宠物',
              pet == null ? '반려동물 추가' : '반려동물 편집',
            )),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    autofocus: true,
                    decoration: petFieldDecoration(
                      hintText: L10n.text(language, 'Pet name', 'ペットの名前',
                          '宠物名字', '반려동물 이름'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in PetType.values)
                        ChoiceChip(
                          avatar: Text(petTypeEmoji(t),
                              style: const TextStyle(fontSize: 16)),
                          label: Text(petTypeName(language, t)),
                          selected: type == t,
                          onSelected: (_) => setState(() => type = t),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: age,
                    keyboardType: TextInputType.number,
                    decoration: petFieldDecoration(
                      hintText: L10n.text(language, 'Age (years)', '年齢（歳）',
                          '年龄（岁）', '나이(세)'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: weight,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: petFieldDecoration(
                      hintText: L10n.text(language, 'Weight (kg)', '体重（kg）',
                          '体重（公斤）', '몸무게(kg)'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: habits,
                    decoration: petFieldDecoration(
                      hintText: L10n.text(language, 'Habits & notes', '習性・メモ',
                          '习性和备注', '습성 및 메모'),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(
                    L10n.text(language, 'Cancel', 'キャンセル', '取消', '취소')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(L10n.text(
                    language, 'Save', '保存', '保存', '저장')),
              ),
            ],
          ),
        );
      },
    );

    if (saved != true) return;
    final trimmedName = name.text.trim();
    if (trimmedName.isEmpty) return;
    final ageYears = int.tryParse(age.text.trim());
    final weightKg = double.tryParse(weight.text.trim());
    final trimmedHabits = habits.text.trim();

    if (pet == null) {
      await store.addPet(
        name: trimmedName,
        type: type,
        ageYears: ageYears,
        habits: trimmedHabits.isEmpty ? null : trimmedHabits,
        weightKg: weightKg,
      );
    } else {
      await store.updatePet(pet.copyWith(
        name: trimmedName,
        type: type,
        ageYears: ageYears,
        habits: trimmedHabits.isEmpty ? null : trimmedHabits,
        weightKg: weightKg,
      ));
    }
  }

  // -------------------------------------------------------------------------
  // Pro entry
  // -------------------------------------------------------------------------

  Widget _proCard(BuildContext context, AppLanguage language) {
    return PetCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const CareIcon(
            icon: Icons.workspace_premium_rounded,
            color: PawColors.purple,
            size: 44),
        title: Text(
          L10n.text(language, 'pettogether Pro', 'pettogether Pro', 'pettogether Pro',
              'pettogether Pro'),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: PawColors.ink,
          ),
        ),
        subtitle: Text(
          L10n.text(language, 'Smart reminders, insights and more',
              'スマート通知、洞察など', '智能提醒、洞察等', '스마트 알림, 인사이트 등'),
          style: const TextStyle(fontSize: 12, color: PawColors.muted),
        ),
        trailing: const Icon(Icons.chevron_right, color: PawColors.purple),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ProView()),
        ),
      ),
    );
  }

  Widget _signOutButton(AppLanguage language) {
    return OutlinedButton.icon(
      onPressed: () => AuthService.instance.signOut(),
      icon: const Icon(Icons.logout, size: 18),
      label: Text(L10n.text(
          language, 'Sign out', 'ログアウト', '退出登录', '로그아웃')),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.red,
        minimumSize: const Size(double.infinity, 50),
        side: BorderSide(color: Colors.red.withValues(alpha: 0.4)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

/// Per-pet care card: today's progress bar, next care item and the pet's
/// routines (ported from the Kate build's pets page).
class _PetCareCard extends StatefulWidget {
  const _PetCareCard({required this.pet, required this.store});

  final Pet pet;
  final CareStore store;

  @override
  State<_PetCareCard> createState() => _PetCareCardState();
}

class _PetCareCardState extends State<_PetCareCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final language = context.watch<AppLanguageStore>().language;
    final pet = widget.pet;
    final store = widget.store;
    final petIds = pet.id;
    final todayTasks = store.todayTasks
        .where((task) =>
            task.status != CareTaskStatus.skipped &&
            _belongsToPet(task, petIds))
        .toList();
    final completed =
        todayTasks.where((task) => task.status == CareTaskStatus.completed);
    final remaining = todayTasks
        .where((task) => task.status != CareTaskStatus.completed)
        .toList();
    final routines = store.routines
        .where((routine) => _routineBelongsToPet(routine, petIds))
        .toList();
    final progress = todayTasks.isEmpty ? 0.0 : completed.length / todayTasks.length;

    return PetCard(
      padding: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                _PetAvatar(type: pet.type),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pet.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: PawColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        petTypeName(language, pet.type),
                        style: const TextStyle(
                            fontSize: 12, color: PawColors.muted),
                      ),
                    ],
                  ),
                ),
                PetTag(
                  title: remaining.isEmpty
                      ? L10n.text(language, 'All done', 'すべて完了', '全部完成',
                          '모두 완료')
                      : '${remaining.length} ${L10n.text(language, 'left', '残り', '剩余', '남음')}',
                  icon: remaining.isEmpty
                      ? Icons.check_circle
                      : Icons.schedule,
                  color: remaining.isEmpty
                      ? PawColors.green
                      : PawColors.purple,
                ),
              ],
            ),
          ),
          Material(
            color: PawColors.cream.withValues(alpha: 0.62),
            child: InkWell(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            L10n.text(language, "Today's care", '今日のケア',
                                '今日护理', '오늘의 케어'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: PawColors.ink,
                            ),
                          ),
                        ),
                        Text(
                          todayTasks.isEmpty
                              ? L10n.text(language, 'Nothing scheduled',
                                  '予定なし', '暂无安排', '예정 없음')
                              : '$completed.length / ${todayTasks.length}',
                          style: const TextStyle(
                              fontSize: 12, color: PawColors.muted),
                        ),
                        const SizedBox(width: 6),
                        AnimatedRotation(
                          turns: _isExpanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: const Icon(Icons.keyboard_arrow_down_rounded,
                              color: PawColors.purple),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 7,
                        backgroundColor: PawColors.purple.withValues(alpha: 0.12),
                        color: remaining.isEmpty && todayTasks.isNotEmpty
                            ? PawColors.green
                            : PawColors.purple,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_isExpanded
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (remaining.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _NextCare(task: remaining.first),
                        ],
                        if (routines.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            L10n.text(language, 'Routine care', 'ルーティンケア',
                                '例行护理', '루틴 케어'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: PawColors.ink,
                            ),
                          ),
                          const SizedBox(height: 8),
                          for (final routine in routines)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _RoutineRow(routine: routine),
                            ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  bool _belongsToPet(CareTask task, String petId) =>
      task.effectivePetIds.isEmpty || task.effectivePetIds.contains(petId);

  bool _routineBelongsToPet(CareRoutine routine, String petId) =>
      routine.effectivePetIds.isEmpty ||
      routine.effectivePetIds.contains(petId);
}

class _RoutineRow extends StatelessWidget {
  const _RoutineRow({required this.routine});

  final CareRoutine routine;

  @override
  Widget build(BuildContext context) {
    final language = context.watch<AppLanguageStore>().language;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: categoryAccent(routine.category).withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          CareIcon(
              icon: categoryIcon(routine.category),
              color: categoryAccent(routine.category),
              size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  routine.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: PawColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_routineDays(language)} · ${_timeText(language, routine.hour, routine.minute)}',
                  style: const TextStyle(fontSize: 12, color: PawColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _routineDays(AppLanguage language) {
    if (routine.weekdays.length == 7) {
      return L10n.text(language, 'Every day', '毎日', '每天', '매일');
    }
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final days = routine.weekdays.toList()..sort();
    return days.map((day) => labels[day - 1]).join(', ');
  }

  String _timeText(AppLanguage language, int hour, int minute) {
    return DateFormat.jm(language.rawValue)
        .format(DateTime(2000, 1, 1, hour, minute));
  }
}

class _NextCare extends StatelessWidget {
  const _NextCare({required this.task});

  final CareTask task;

  @override
  Widget build(BuildContext context) {
    final language = context.watch<AppLanguageStore>().language;
    final status = task.status == CareTaskStatus.claimed
        ? '${task.assigneeNameSnapshot ?? L10n.text(language, 'Someone', '誰か', '某人', '누군가')} ${L10n.text(language, 'is handling this', 'が担当中', '正在负责', '가 맡고 있어요')}'
        : L10n.text(language, 'Needs someone', '担当者募集中', '需要人接取', '담당자 필요');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: categoryAccent(task.category).withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          CareIcon(
              icon: categoryIcon(task.category),
              color: categoryAccent(task.category),
              size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: PawColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_dueText(language, task.dueTime)} · $status',
                  style: const TextStyle(fontSize: 12, color: PawColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _dueText(AppLanguage language, DateTime date) {
    return DateFormat.jm(language.rawValue).format(date);
  }
}

class _PetAvatar extends StatelessWidget {
  const _PetAvatar({required this.type});

  final PetType type;

  @override
  Widget build(BuildContext context) => Container(
    width: 52,
    height: 52,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
      border: Border.all(color: PawColors.purple.withValues(alpha: 0.18)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x120E0621),
          blurRadius: 8,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: PetTypeIcon(
      type: type,
      color: PawColors.purpleDark,
      size: 26,
    ),
  );
}
