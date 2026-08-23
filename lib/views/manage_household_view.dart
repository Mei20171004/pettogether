import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/care_catalog.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../store/care_store.dart';
import '../theme/app_theme.dart';
import 'widgets/common.dart';

/// "Manage my household": the family organization chart plus the pet list.
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
        title: Text(
            L10n.text(language, 'Family', '家族', '家庭', '가족')),
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
                    _membersSection(store, language),
                    const SizedBox(height: 18),
                    _petsSection(context, store, language),
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
                if (household?.inviteCode.isNotEmpty ?? false) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${L10n.text(language, 'Invite code', '招待コード', '邀请码', '초대 코드')}: ${household!.inviteCode}',
                    style: const TextStyle(fontSize: 12, color: PawColors.muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Family organization chart
  // -------------------------------------------------------------------------

  Widget _membersSection(CareStore store, AppLanguage language) {
    final members = store.caregivers;
    final current = store.currentCaregiver;
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
              if (current != null) _memberRow(current, language, isYou: true),
              if (current != null && members.length > 1)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Icon(Icons.arrow_drop_down,
                      size: 28, color: PawColors.purple),
                ),
              for (final member in members)
                if (member.id != current?.id)
                  _memberRow(member, language, isYou: false),
            ],
          ),
        ),
      ],
    );
  }

  Widget _memberRow(Caregiver member, AppLanguage language,
      {required bool isYou}) {
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
            ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Pets
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
              padding: const EdgeInsets.only(bottom: 10),
              child: _petCard(context, store, pet, language),
            ),
      ],
    );
  }

  Widget _petCard(
      BuildContext context, CareStore store, Pet pet, AppLanguage language) {
    return PetCard(
      padding: 14,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: petTypeAccent(pet.type).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Text(petTypeEmoji(pet.type),
                style: const TextStyle(fontSize: 22)),
          ),
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
                const SizedBox(height: 3),
                Text(
                  [
                    petTypeName(language, pet.type),
                    if (pet.ageYears != null)
                      '${pet.ageYears} ${L10n.text(language, 'years old', '歳', '岁', '살')}',
                    if (pet.weightKg != null) '${pet.weightKg} kg',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 12, color: PawColors.muted),
                ),
                if (pet.habits != null && pet.habits!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    pet.habits!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: PawColors.purpleDark),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined,
                size: 18, color: PawColors.purple),
            onPressed: () => _showPetDialog(context, store, language, pet: pet),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 18, color: PawColors.rose),
            onPressed: () => store.removePet(pet.id),
          ),
        ],
      ),
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
