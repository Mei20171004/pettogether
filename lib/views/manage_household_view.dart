import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/l10n.dart';
import '../models/care_catalog.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../store/care_store.dart';
import '../store/pro_access.dart';
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
                    const SizedBox(height: 10),
                    _deleteAccountButton(context, store, language),
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
                          tooltip: L10n.text(language, 'Share invitation',
                              '招待を共有', '分享邀请', '초대 공유'),
                          onPressed: () async {
                            final box = context.findRenderObject() as RenderBox?;
                            final title = L10n.text(
                              language,
                              'Join my pettogether household',
                              'pettogether の家族に参加',
                              '加入我的 pettogether 家庭',
                              '내 pettogether 가족에 참여하세요',
                            );
                            if (!kIsWeb &&
                                defaultTargetPlatform == TargetPlatform.iOS) {
                              try {
                                final logo = await rootBundle.load(
                                  'assets/images/app_icon.png',
                                );
                                await const MethodChannel(
                                  'pettogether/invitation_share',
                                ).invokeMethod<void>('share', {
                                  'link': invitation.deepLink,
                                  'title': title,
                                  'logo': logo.buffer.asUint8List(
                                    logo.offsetInBytes,
                                    logo.lengthInBytes,
                                  ),
                                });
                                return;
                              } catch (error) {
                                debugPrint('iOS invitation preview failed: $error');
                              }
                            }
                            await SharePlus.instance.share(ShareParams(
                              text: invitation.deepLink,
                              subject: title,
                              sharePositionOrigin: box == null
                                  ? null
                                  : box.localToGlobal(Offset.zero) & box.size,
                            ));
                          },
                          icon: const Icon(Icons.ios_share_rounded),
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
    if (pet == null && !context.read<ProAccess>().canAddPet) {
      await showProPaywall(
        context,
        feature: ProFeature.multiPet,
        reason: L10n.text(
          language,
          'Your first pet is free. Adding a second pet requires the ¥300/month multi-pet plan.',
          '1匹目は無料です。2匹目の追加には月額300円の複数ペットプランが必要です。',
          '第 1 只宠物免费；添加第 2 只需要订阅每月 ¥300 的多宠物功能。',
          '첫 반려동물은 무료이며, 두 번째 반려동물부터 월 ¥300 구독이 필요합니다.',
        ),
      );
      return;
    }
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

  Widget _deleteAccountButton(
    BuildContext context,
    CareStore store,
    AppLanguage language,
  ) {
    return TextButton.icon(
      onPressed: () => _confirmDeleteAccount(context, store, language),
      icon: const Icon(Icons.delete_forever_outlined, size: 18),
      label: Text(
        L10n.text(language, 'Delete account', 'アカウントを削除', '删除账号', '계정 삭제'),
      ),
      style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
    );
  }

  Future<void> _confirmDeleteAccount(
    BuildContext context,
    CareStore store,
    AppLanguage language,
  ) async {
    final confirmation = TextEditingController();
    final password = TextEditingController();
    final successors = store.isOwner
        ? store.caregivers
              .where((member) => member.id != store.currentCaregiver?.id)
              .toList(growable: false)
        : const <Caregiver>[];
    String? newOwnerUid = successors.length == 1 ? successors.single.id : null;

    final request = await showDialog<_AccountDeletionRequest>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final canSubmit =
              confirmation.text.trim() == 'DELETE' &&
              (!store.isOwner || successors.isEmpty || newOwnerUid != null) &&
              (!AuthService.instance.deletionNeedsPassword ||
                  password.text.isNotEmpty);
          return AlertDialog(
            title: Text(
              L10n.text(
                language,
                'Permanently delete account?',
                'アカウントを完全に削除しますか？',
                '永久删除账号？',
                '계정을 영구 삭제할까요?',
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    L10n.text(
                      language,
                      'Your account, personal profile, device tokens, and subscription status stored by pettogether will be deleted. Shared care history will keep the event but remove your identity.',
                      'アカウント、個人プロフィール、端末トークン、pettogetherに保存された購読状態が削除されます。共有ケア履歴は残りますが、あなたの識別情報は削除されます。',
                      '你的账号、个人资料、设备令牌及 pettogether 保存的订阅状态将被删除。共享照护记录会保留事件，但会移除你的身份信息。',
                      '계정, 개인 프로필, 기기 토큰 및 pettogether에 저장된 구독 상태가 삭제됩니다. 공유 돌봄 기록은 유지되지만 신원 정보는 제거됩니다.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    L10n.text(
                      language,
                      'Important: deleting this account does not cancel an App Store subscription. Cancel it separately in Apple ID Settings → Subscriptions if you no longer want it to renew.',
                      '重要：アカウントを削除してもApp Storeの購読は解約されません。更新を停止する場合は、Apple ID設定の「サブスクリプション」で別途解約してください。',
                      '重要：删除账号不会取消 App Store 订阅。如不希望继续续费，请另行前往 Apple ID 设置 → 订阅中取消。',
                      '중요: 계정을 삭제해도 App Store 구독은 취소되지 않습니다. 갱신을 원하지 않으면 Apple ID 설정 → 구독에서 별도로 취소하세요.',
                    ),
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (successors.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: newOwnerUid,
                      decoration: InputDecoration(
                        labelText: L10n.text(
                          language,
                          'New household owner',
                          '新しい家族オーナー',
                          '新的家庭 Owner',
                          '새 가족 소유자',
                        ),
                      ),
                      items: [
                        for (final member in successors)
                          DropdownMenuItem(
                            value: member.id,
                            child: Text(member.displayName),
                          ),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => newOwnerUid = value),
                    ),
                  ],
                  if (AuthService.instance.deletionNeedsPassword) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: password,
                      obscureText: true,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: InputDecoration(
                        labelText: L10n.text(
                          language,
                          'Current password',
                          '現在のパスワード',
                          '当前密码',
                          '현재 비밀번호',
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: confirmation,
                    autocorrect: false,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      labelText: L10n.text(
                        language,
                        'Type DELETE to confirm',
                        '確認のためDELETEと入力',
                        '输入 DELETE 以确认',
                        '확인하려면 DELETE 입력',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(L10n.text(language, 'Cancel', 'キャンセル', '取消', '취소')),
              ),
              FilledButton(
                onPressed: canSubmit
                    ? () => Navigator.pop(
                        dialogContext,
                        _AccountDeletionRequest(
                          newOwnerUid: newOwnerUid,
                          password: password.text,
                        ),
                      )
                    : null,
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: Text(
                  L10n.text(
                    language,
                    'Delete permanently',
                    '完全に削除',
                    '永久删除',
                    '영구 삭제',
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
    confirmation.dispose();
    password.dispose();
    if (request == null || !context.mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await AuthService.instance.deleteAccount(
        newOwnerUid: request.newOwnerUid,
        password: request.password,
      );
      if (context.mounted) Navigator.of(context).pop();
    } on FirebaseAuthException catch (error) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      _showDeletionError(context, language, switch (error.code) {
        'wrong-password' || 'invalid-credential' => L10n.text(
          language,
          'The password is incorrect. Your account was not deleted.',
          'パスワードが正しくありません。アカウントは削除されていません。',
          '密码不正确，账号未被删除。',
          '비밀번호가 올바르지 않습니다. 계정은 삭제되지 않았습니다.',
        ),
        'network-request-failed' => L10n.text(
          language,
          'Check your connection and try again. Your account was not deleted.',
          '通信状況を確認して再試行してください。アカウントは削除されていません。',
          '请检查网络后重试，账号未被删除。',
          '네트워크를 확인한 후 다시 시도하세요. 계정은 삭제되지 않았습니다.',
        ),
        _ => L10n.text(
          language,
          'Sign-in verification failed. Your account was not deleted.',
          '本人確認に失敗しました。アカウントは削除されていません。',
          '登录验证失败，账号未被删除。',
          '로그인 확인에 실패했습니다. 계정은 삭제되지 않았습니다.',
        ),
      });
    } on FirebaseFunctionsException catch (error) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      _showDeletionError(
        context,
        language,
        error.code == 'failed-precondition'
            ? L10n.text(
                language,
                'Choose a valid new household owner and try again.',
                '有効な新しい家族オーナーを選んで再試行してください。',
                '请选择有效的新家庭 Owner 后重试。',
                '유효한 새 가족 소유자를 선택한 후 다시 시도하세요.',
              )
            : L10n.text(
                language,
                'The server could not finish deletion. Please try again; repeated attempts are safe.',
                'サーバーで削除を完了できませんでした。再試行してください。繰り返しても問題ありません。',
                '服务器未能完成删除。请重试，重复尝试不会产生额外影响。',
                '서버에서 삭제를 완료하지 못했습니다. 다시 시도해 주세요. 반복해도 안전합니다.',
              ),
      );
    } catch (_) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      _showDeletionError(
        context,
        language,
        L10n.text(
          language,
          'Deletion did not finish. Please check your connection and try again.',
          '削除は完了していません。通信状況を確認して再試行してください。',
          '删除未完成。请检查网络后重试。',
          '삭제가 완료되지 않았습니다. 네트워크를 확인한 후 다시 시도하세요.',
        ),
      );
    }
  }

  void _showDeletionError(
    BuildContext context,
    AppLanguage language,
    String message,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: L10n.text(language, 'OK', 'OK', '知道了', '확인'),
          onPressed: () {},
        ),
      ),
    );
  }
}

class _AccountDeletionRequest {
  const _AccountDeletionRequest({this.newOwnerUid, required this.password});

  final String? newOwnerUid;
  final String password;
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
                              : '${completed.length} / ${todayTasks.length}',
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
