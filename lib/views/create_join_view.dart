import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/care_catalog.dart';
import '../models/models.dart';
import '../store/care_store.dart';
import '../theme/app_theme.dart';
import 'widgets/common.dart';

enum _Mode { create, join }

class CreateJoinView extends StatefulWidget {
  const CreateJoinView({super.key});

  @override
  State<CreateJoinView> createState() => _CreateJoinViewState();
}

class _CreateJoinViewState extends State<CreateJoinView> {
  _Mode _mode = _Mode.create;
  PetType _petType = PetType.cat;
  final _caregiverName = TextEditingController(text: '');
  final _householdName = TextEditingController(text: 'Mochi Family');
  final _petName = TextEditingController(text: 'Mochi');
  final _inviteCode = TextEditingController(text: '');

  @override
  void dispose() {
    _caregiverName.dispose();
    _householdName.dispose();
    _petName.dispose();
    _inviteCode.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    if (_caregiverName.text.trim().isEmpty) return false;
    if (_mode == _Mode.create) {
      return _householdName.text.trim().isNotEmpty &&
          _petName.text.trim().isNotEmpty;
    }
    return _inviteCode.text.trim().isNotEmpty;
  }

  void _submit(CareStore store) {
    if (_mode == _Mode.create) {
      store.createHousehold(
        name: _householdName.text,
        petName: _petName.text,
        petType: _petType,
        caregiverName: _caregiverName.text,
      );
    } else {
      store.joinHousehold(
        inviteCode: _inviteCode.text,
        caregiverName: _caregiverName.text,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = context.watch<AppLanguageStore>().language;
    final store = context.watch<CareStore>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          PopupMenuButton<AppLanguage>(
            icon: const Icon(Icons.language, color: PawColors.purple),
            onSelected: (value) =>
                context.read<AppLanguageStore>().language = value,
            itemBuilder: (context) => [
              for (final item in AppLanguage.values)
                PopupMenuItem(value: item, child: Text(item.label)),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          const PetScreenBackground(),
          SafeArea(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _headerCard(),
                    const SizedBox(height: 22),
                    PetCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SegmentedButton<_Mode>(
                            segments: [
                              ButtonSegment(
                                value: _Mode.create,
                                label: Text(L10n.text(language, 'Create a home',
                                    '家を作る', '创建家庭', '집 만들기')),
                              ),
                              ButtonSegment(
                                value: _Mode.join,
                                label: Text(L10n.text(
                                    language, 'Join a home', '家に参加', '加入家庭', '집 참여')),
                              ),
                            ],
                            selected: {_mode},
                            onSelectionChanged: (selection) =>
                                setState(() => _mode = selection.first),
                          ),
                          const SizedBox(height: 18),
                          _fieldLabel(
                              L10n.text(language, 'Your name', 'あなたの名前',
                                  '你的名字', '이름'),
                              Icons.person),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _caregiverName,
                            onChanged: (_) => setState(() {}),
                            decoration: petFieldDecoration(
                              hintText: L10n.text(
                                  language,
                                  'How should your family see you?',
                                  '家族に表示する名前',
                                  '家人会怎么称呼你？',
                                  '가족에게 어떻게 보일까요?'),
                            ),
                          ),
                          if (_mode == _Mode.create) ...[
                            const SizedBox(height: 16),
                            _fieldLabel(
                                L10n.text(language, 'Household', '家の名前',
                                    '家庭', '가족 이름'),
                                Icons.home),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _householdName,
                              onChanged: (_) => setState(() {}),
                              decoration: petFieldDecoration(
                                hintText: L10n.text(language, 'Household name',
                                    '家族の名前', '家庭名称', '가족 이름'),
                              ),
                            ),
                            const SizedBox(height: 16),
                            _fieldLabel(
                                L10n.text(language, 'Your pet', 'ペット',
                                    '你的宠物', '반려동물'),
                                Icons.pets),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _petName,
                              onChanged: (_) => setState(() {}),
                              decoration: petFieldDecoration(
                                hintText: L10n.text(language, 'Pet name',
                                    'ペットの名前', '宠物名字', '반려동물 이름'),
                              ),
                            ),
                            const SizedBox(height: 16),
                            _fieldLabel(
                                L10n.text(language, 'Pet type', 'ペットの種類',
                                    '宠物类型', '반려동물 종류'),
                                Icons.category),
                            const SizedBox(height: 8),
                            _petTypeSelector(language),
                          ] else ...[
                            const SizedBox(height: 16),
                            _fieldLabel(
                                L10n.text(language, 'Invite code', '招待コード',
                                    '邀请码', '초대 코드'),
                                Icons.group),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _inviteCode,
                              onChanged: (_) => setState(() {}),
                              textCapitalization:
                                  TextCapitalization.characters,
                              autocorrect: false,
                              decoration: petFieldDecoration(
                                hintText: L10n.text(language,
                                    'Enter the six-character code',
                                    '6文字のコードを入力', '输入六位代码', '6자리 코드 입력'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              L10n.text(
                                language,
                                'Ask a caregiver in your household for their six-character code.',
                                '家族から6文字の招待コードをもらってください。',
                                '请向家里的家人索取六位邀请码。',
                                '가족에게 6자리 초대 코드를 받으세요.',
                              ),
                              style: const TextStyle(
                                  fontSize: 12, color: PawColors.muted),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      style: pawPrimaryButtonStyle(),
                      onPressed:
                          (!_canSubmit || store.isLoading) ? null : () => _submit(store),
                      child: store.isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(_mode == _Mode.create
                                    ? L10n.text(language, 'Create household',
                                        '家を作成', '创建家庭', '가족 만들기')
                                    : L10n.text(language, 'Join household',
                                        '家に参加', '加入家庭', '가족 참여')),
                                const SizedBox(width: 9),
                                const Icon(Icons.arrow_forward, size: 18),
                              ],
                            ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      L10n.text(
                        language,
                        'One shared place for meals, walks, medicine, and handoffs.',
                        '食事、散歩、薬、引き継ぎをひとつに。',
                        '喂食、散步、用药、交接，都在这一个地方。',
                        '식사, 산책, 약, 인수인계를 한곳에.',
                      ),
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(fontSize: 12, color: PawColors.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: PawColors.purpleDark.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const PetArtwork(height: 230),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: PawColors.lavender,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.pets,
                          size: 18, color: PawColors.purple),
                    ),
                    const SizedBox(width: 9),
                    Text(
                      'copaw',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(
                            color: PawColors.ink,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Text(
                  _t(context, 'Shared care, without the guesswork.',
                      '迷わない、みんなのケア。', '共同照护，不再猜测。',
                      '망설임 없는 함께하는 케어.'),
                  style: const TextStyle(color: PawColors.muted),
                ),
                const SizedBox(height: 9),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.auto_awesome,
                        size: 15, color: PawColors.purple),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        _t(context, 'A happier routine for every pet parent',
                            'すべての飼い主に、もっと楽しい毎日を',
                            '让每位宠物家长都更轻松', '모든 반려인에게 더 행복한 일상을'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: PawColors.purple,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 15, color: PawColors.purpleDark),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
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

  String _t(BuildContext context, String en, String ja, String zh, String ko) {
    return L10n.text(
        context.watch<AppLanguageStore>().language, en, ja, zh, ko);
  }
}
