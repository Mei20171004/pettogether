import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/care_catalog.dart';
import '../models/models.dart';
import '../store/care_store.dart';
import '../theme/app_theme.dart';
import 'widgets/common.dart';

class ProfileEditView extends StatefulWidget {
  const ProfileEditView({super.key});

  @override
  State<ProfileEditView> createState() => _ProfileEditViewState();
}

class _ProfileEditViewState extends State<ProfileEditView> {
  late final TextEditingController _caregiverName;
  late final TextEditingController _householdName;
  late final TextEditingController _petName;
  bool _copied = false;
  bool _didLoad = false;
  PetType _petType = PetType.cat;

  @override
  void initState() {
    super.initState();
    _caregiverName = TextEditingController();
    _householdName = TextEditingController();
    _petName = TextEditingController();
  }

  @override
  void dispose() {
    _caregiverName.dispose();
    _householdName.dispose();
    _petName.dispose();
    super.dispose();
  }

  void _loadIfNeeded(CareStore store) {
    if (_didLoad) return;
    _caregiverName.text = store.currentCaregiver?.displayName ?? '';
    _householdName.text = store.household?.name ?? '';
    _petName.text = store.household?.petName ?? '';
    _petType = store.household?.petType ?? PetType.cat;
    _didLoad = true;
  }

  bool get _canSave {
    final caregiver = _caregiverName.text.trim();
    final household = _householdName.text.trim();
    final pet = _petName.text.trim();
    return caregiver.isNotEmpty &&
        caregiver.length <= 50 &&
        household.isNotEmpty &&
        household.length <= 60 &&
        pet.isNotEmpty &&
        pet.length <= 60;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CareStore>();
    _loadIfNeeded(store);

    final language = context.watch<AppLanguageStore>().language;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(L10n.text(
            language, 'Family profile', '家族プロフィール', '家庭资料', '가족 프로필')),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: store.isSavingProfile ? null : () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          const PetScreenBackground(),
          SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(context),
                    const SizedBox(height: 18),
                    _profileCard(context),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      style: pawPrimaryButtonStyle(),
                      onPressed: (!_canSave || store.isSavingProfile)
                          ? null
                          : () => _save(store),
                      child: store.isSavingProfile
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(store.isSavingProfile
                                    ? L10n.text(language, 'Saving…', '保存中…',
                                        '保存中…', '저장 중…')
                                    : L10n.text(language, 'Save changes',
                                        '変更を保存', '保存更改', '변경사항 저장')),
                                if (!store.isSavingProfile) ...[
                                  const SizedBox(width: 8),
                                  const Icon(Icons.check, size: 18),
                                ],
                              ],
                            ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      L10n.text(
                        language,
                        'Changes are shared with everyone in this household.',
                        '変更は家族全員と共有されます。',
                        '更改会与家里的每个人共享。',
                        '변경사항은 가족 모두와 공유됩니다.',
                      ),
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(fontSize: 12, color: PawColors.muted),
                    ),
                    const SizedBox(height: 20),
                    _leaveCard(context, store, language),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final initial = _caregiverName.text.trim().isNotEmpty
        ? _caregiverName.text.trim()[0].toUpperCase()
        : '?';
    return Column(
      children: [
        Container(
          width: 74,
          height: 74,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: PawColors.purple.withValues(alpha: 0.14),
                blurRadius: 14,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Text(
            initial,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: PawColors.purple,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _t(context, 'Keep your family details current', '家族の情報を最新に保ちましょう',
              '让家庭信息保持最新', '가족 정보를 최신으로 유지하세요'),
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: PawColors.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _t(context, 'Your name and pet details update across devices.',
              '名前とペット情報はすべての端末に反映されます。',
              '你的名字和宠物信息会同步到所有设备。',
              '이름과 반려동물 정보가 모든 기기에 반영됩니다.'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: PawColors.muted),
        ),
      ],
    );
  }

  Widget _profileCard(BuildContext context) {
    final language = context.watch<AppLanguageStore>().language;
    final store = context.watch<CareStore>();
    final inviteCode = store.household?.inviteCode ?? '';

    return PetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PetSectionTitle(
            title: L10n.text(language, 'About you', 'あなたについて', '关于你', '당신에 대해'),
            detail: 'CAREGIVER',
          ),
          const SizedBox(height: 12),
          _fieldLabel(
              L10n.text(language, 'Your name', 'あなたの名前', '你的名字', '이름'),
              Icons.person),
          const SizedBox(height: 8),
          TextField(
            controller: _caregiverName,
            onChanged: (_) => setState(() {}),
            textCapitalization: TextCapitalization.words,
            decoration: petFieldDecoration(
              hintText: L10n.text(language, 'How should your family see you?',
                  '家族に表示する名前', '家人会怎么称呼你？', '가족에게 어떻게 보일까요?'),
            ),
          ),
          const SizedBox(height: 18),
          PetSectionTitle(
            title: L10n.text(language, 'Home & pet', '家とペット', '家和宠物',
                '집과 반려동물'),
            detail: 'SHARED',
          ),
          const SizedBox(height: 12),
          _fieldLabel(
              L10n.text(language, 'Household name', '家の名前', '家庭名称', '가족 이름'),
              Icons.home),
          const SizedBox(height: 8),
          TextField(
            controller: _householdName,
            onChanged: (_) => setState(() {}),
            textCapitalization: TextCapitalization.words,
            decoration: petFieldDecoration(
              hintText: L10n.text(
                  language, 'Household name', '家の名前', '家庭名称', '가족 이름'),
            ),
          ),
          const SizedBox(height: 12),
          _fieldLabel(
              L10n.text(language, 'Pet name', 'ペットの名前', '宠物名字', '반려동물 이름'),
              Icons.pets),
          const SizedBox(height: 8),
          TextField(
            controller: _petName,
            onChanged: (_) => setState(() {}),
            textCapitalization: TextCapitalization.words,
            decoration: petFieldDecoration(
              hintText: L10n.text(
                  language, 'Pet name', 'ペットの名前', '宠物名字', '반려동물 이름'),
            ),
          ),
          const SizedBox(height: 12),
          _fieldLabel(
              L10n.text(language, 'Pet type', 'ペットの種類', '宠物类型', '반려동물 종류'),
              Icons.category),
          const SizedBox(height: 8),
          _petTypeSelector(language),
          if (inviteCode.isNotEmpty) ...[
            const SizedBox(height: 20),
            PetSectionTitle(
              title: L10n.text(
                  language, 'Invite a caregiver', '家族を招待', '邀请家人', '가족 초대'),
              detail: 'SHARE ACCESS',
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const CareIcon(icon: Icons.group, color: PawColors.blue, size: 50),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        L10n.text(
                            language, 'Invite code', '招待コード', '邀请码', '초대 코드'),
                        style: const TextStyle(
                            fontSize: 12, color: PawColors.muted),
                      ),
                      Text(
                        inviteCode,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: PawColors.ink,
                          letterSpacing: 1.2,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _copy(inviteCode),
                  icon: Icon(_copied ? Icons.check : Icons.content_copy,
                      size: 16),
                  label: Text(_copied
                      ? L10n.text(language, 'Copied', 'コピー済み', '已复制', '복사됨')
                      : L10n.text(language, 'Copy', 'コピー', '复制', '복사')),
                  style: TextButton.styleFrom(
                    foregroundColor: PawColors.purple,
                    backgroundColor: PawColors.lavender,
                    shape: const StadiumBorder(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              L10n.text(
                language,
                'Share this code with someone you trust so they can join this household.',
                '信頼できる人にこのコードを共有して、家族に招待しましょう。',
                '把这个代码分享给你信任的人，让他们加入这个家庭。',
                '신뢰하는 사람에게 이 코드를 공유해 가족에 초대하세요.',
              ),
              style: const TextStyle(fontSize: 12, color: PawColors.muted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _leaveCard(
      BuildContext context, CareStore store, AppLanguage language) {
    return PetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            L10n.text(language, 'Household membership', '家族メンバーシップ',
                '家庭成员', '가족 멤버십'),
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: PawColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            L10n.text(
              language,
              'Return this device to the welcome screen without deleting shared household data.',
              '共有データを削除せずに、この端末をウェルカム画面に戻します。',
              '在不删除共享家庭数据的情况下，将本设备返回欢迎界面。',
              '공유 데이터를 삭제하지 않고 이 기기를 환영 화면으로 되돌립니다.',
            ),
            style: const TextStyle(fontSize: 13, color: PawColors.muted),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: store.isSavingProfile
                ? null
                : () => _confirmLeave(context, store),
            icon: const Icon(Icons.logout, size: 18),
            label: Text(L10n.text(
                language, 'Leave household', '家から退出', '退出家庭', '가족에서 나가기')),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              backgroundColor: Colors.red.withValues(alpha: 0.09),
              side: BorderSide.none,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLeave(BuildContext context, CareStore store) async {
    final language = context.read<AppLanguageStore>().language;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L10n.text(language, 'Leave this household?',
            'この家から退出しますか？', '要退出这个家庭吗？', '이 가족에서 나가시겠어요?')),
        content: Text(L10n.text(
          language,
          'This device will return to the welcome screen. The shared household stays available to other caregivers, and you can rejoin later with the invite code.',
          'この端末はウェルカム画面に戻ります。共有データは他の家族に残り、後で招待コードで再参加できます。',
          '本设备将返回欢迎界面。共享的家庭对其他家人仍然可用，之后你可以用邀请码重新加入。',
          '이 기기는 환영 화면으로 돌아갑니다. 공유 데이터는 다른 가족에게 남으며, 나중에 초대 코드로 다시 참여할 수 있습니다.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
                L10n.text(language, 'Cancel', 'キャンセル', '取消', '취소')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              L10n.text(language, 'Leave household', '家から退出', '退出家庭',
                  '가족에서 나가기'),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      store.leaveHousehold();
      Navigator.of(context).pop();
    }
  }

  Future<void> _copy(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  Future<void> _save(CareStore store) async {
    final saved = await store.updateProfile(
      caregiverName: _caregiverName.text,
      householdName: _householdName.text,
      petName: _petName.text,
      petType: _petType,
    );
    if (saved && mounted) Navigator.of(context).pop();
  }

  Widget _fieldLabel(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 15, color: PawColors.purpleDark),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: PawColors.purpleDark,
          ),
        ),
      ],
    );
  }

  Widget _petTypeSelector(AppLanguage language) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final type in PetType.values) _petTypeChip(type, language),
      ],
    );
  }

  Widget _petTypeChip(PetType type, AppLanguage language) {
    final selected = _petType == type;
    final accent = petTypeAccent(type);
    return InkWell(
      onTap: () => setState(() => _petType = type),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.16)
              : PawColors.lavender.withValues(alpha: 0.52),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(petTypeEmoji(type), style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 6),
            Text(
              petTypeName(language, type),
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                color: selected ? accent : PawColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _t(BuildContext context, String en, String ja, String zh, String ko) =>
      L10n.text(
          context.watch<AppLanguageStore>().language, en, ja, zh, ko);
}
