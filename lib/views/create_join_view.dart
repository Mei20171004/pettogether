import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/care_catalog.dart';
import '../models/models.dart';
import '../store/care_store.dart';
import '../theme/app_theme.dart';
import 'invitation_scanner_view.dart';
import 'widgets/common.dart';
import 'widgets/pet_species_icon.dart';

enum _Mode { create, join }

/// Welcome screen: create a household (with one or more pets) or join one
/// through a one-time invitation link/QR code that the owner must approve.
class CreateJoinView extends StatefulWidget {
  const CreateJoinView({super.key});

  @override
  State<CreateJoinView> createState() => _CreateJoinViewState();
}

class _CreateJoinViewState extends State<CreateJoinView> {
  _Mode _mode = _Mode.create;
  final _caregiverName = TextEditingController(text: '');
  final _householdName = TextEditingController(text: 'Mochi Family');
  final _invite = TextEditingController(text: '');
  final List<_PetEntry> _pets = [_PetEntry(id: 'pet-1')];
  int _nextPetId = 2;
  String? _shownInvitationId;

  bool get _joining =>
      _mode == _Mode.join ||
      context.read<CareStore>().invitationPreview != null;

  @override
  void dispose() {
    _caregiverName.dispose();
    _householdName.dispose();
    _invite.dispose();
    for (final pet in _pets) {
      pet.dispose();
    }
    super.dispose();
  }

  bool get _canSubmit {
    if (_caregiverName.text.trim().isEmpty) return false;
    if (_joining) return _invite.text.trim().isNotEmpty;
    return _householdName.text.trim().isNotEmpty &&
        _pets.isNotEmpty &&
        _pets.every((pet) => pet.name.text.trim().isNotEmpty && pet.type != null);
  }

  Future<void> _submit(CareStore store) async {
    if (_joining) {
      if (store.invitationPreview == null) {
        await store.previewInvitation(_invite.text);
      } else {
        await store.requestToJoin(caregiverName: _caregiverName.text);
      }
    } else {
      await store.createHousehold(
        name: _householdName.text,
        pets: _pets.map((pet) => pet.toPet()).toList(),
        caregiverName: _caregiverName.text,
      );
    }
  }

  Future<void> _scanInvitation(CareStore store) async {
    final value = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const InvitationScannerView()),
    );
    if (value == null || !mounted) return;
    _invite.text = value;
    setState(() => _mode = _Mode.join);
    await store.previewInvitation(value);
  }

  @override
  Widget build(BuildContext context) {
    final language = context.watch<AppLanguageStore>().language;
    final store = context.watch<CareStore>();

    final preview = store.invitationPreview;
    if (preview != null && preview.id != _shownInvitationId) {
      _shownInvitationId = preview.id;
      _invite.text = preview.deepLink;
    }
    final pendingRequest = store.pendingJoinRequest;

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
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _headerCard(language),
                      const SizedBox(height: 22),
                      if (pendingRequest != null) ...[
                        _pendingRequestCard(context, pendingRequest, store),
                        if (store.errorMessage != null) ...[
                          const SizedBox(height: 12),
                          _errorBanner(store.errorMessage!),
                        ],
                      ] else ...[
                        PetCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SegmentedButton<_Mode>(
                                segments: [
                                  ButtonSegment(
                                    value: _Mode.create,
                                    label: Text(L10n.text(
                                        language, 'Create a home', '家を作る',
                                        '创建家庭', '집 만들기')),
                                  ),
                                  ButtonSegment(
                                    value: _Mode.join,
                                    label: Text(L10n.text(
                                        language, 'Join a home', '家に参加',
                                        '加入家庭', '집 참여')),
                                  ),
                                ],
                                selected: {_mode},
                                onSelectionChanged: (selection) {
                                  setState(() {
                                    _mode = selection.first;
                                    _shownInvitationId = null;
                                    store.clearInvitationPreview();
                                  });
                                },
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
                              const SizedBox(height: 16),
                              if (_joining)
                                _joinFields(context, store, language)
                              else
                                _createFields(context, language),
                            ],
                          ),
                        ),
                        if (preview != null) ...[
                          const SizedBox(height: 14),
                          _invitationPreview(context, preview, store, language),
                        ],
                        if (store.errorMessage != null) ...[
                          const SizedBox(height: 12),
                          _errorBanner(store.errorMessage!),
                        ],
                        const SizedBox(height: 20),
                        ElevatedButton(
                          style: pawPrimaryButtonStyle(),
                          onPressed: (!_canSubmit || store.isLoading)
                              ? null
                              : () => _submit(store),
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
                                    Text(_submitLabel(language)),
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
                          style: const TextStyle(
                              fontSize: 12, color: PawColors.muted),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _submitLabel(AppLanguage language) {
    if (_joining) {
      final previewing = context.read<CareStore>().invitationPreview != null;
      return L10n.text(
        language,
        previewing ? 'Request to join' : 'Preview invitation',
        previewing ? '参加をリクエスト' : '招待をプレビュー',
        previewing ? '请求加入' : '预览邀请',
        previewing ? '참여 요청' : '초대 미리보기',
      );
    }
    return L10n.text(language, 'Create household', '家を作成', '创建家庭',
        '가족 만들기');
  }

  Widget _joinFields(
      BuildContext context, CareStore store, AppLanguage language) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldLabel(
            L10n.text(language, 'Invitation link', '招待リンク', '邀请链接',
                '초대 링크'),
            Icons.link),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _invite,
                onChanged: (_) {
                  if (store.invitationPreview != null) {
                    _shownInvitationId = null;
                    store.clearInvitationPreview();
                  }
                  setState(() {});
                },
                autocorrect: false,
                enableSuggestions: false,
                decoration: petFieldDecoration(
                  hintText: L10n.text(
                      language,
                      'Paste a pettogether invitation link',
                      'pettogether の招待リンクを貼り付け',
                      '粘贴 pettogether 邀请链接',
                      'pettogether 초대 링크 붙여넣기'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: L10n.text(
                  language, 'Scan QR code', 'QRコードをスキャン', '扫描二维码',
                  'QR 코드 스캔'),
              onPressed:
                  store.isCloudBacked && !store.isLoading
                      ? () => _scanInvitation(store)
                      : null,
              icon: const Icon(Icons.qr_code_scanner_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          store.isCloudBacked
              ? L10n.text(
                  language,
                  'Invitations expire after 24 hours and can only be claimed once.',
                  '招待は24時間で期限切れになり、一度しか利用できません。',
                  '邀请在 24 小时后过期，且只能使用一次。',
                  '초대장은 24시간 후 만료되며 한 번만 사용할 수 있습니다.')
              : L10n.text(language, 'Local demo code: PAW123',
                  'ローカルデモコード: PAW123', '本地演示码: PAW123',
                  '로컬 데모 코드: PAW123'),
          style: const TextStyle(fontSize: 12, color: PawColors.muted),
        ),
      ],
    );
  }

  Widget _createFields(BuildContext context, AppLanguage language) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldLabel(L10n.text(language, 'Household', '家の名前', '家庭', '가족 이름'),
            Icons.home),
        const SizedBox(height: 8),
        TextField(
          controller: _householdName,
          onChanged: (_) => setState(() {}),
          decoration: petFieldDecoration(
            hintText: L10n.text(language, 'Household name', '家族の名前',
                '家庭名称', '가족 이름'),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                L10n.text(language, 'Pets', 'ペット', '宠物', '반려동물'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: PawColors.purpleDark,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _pets.length >= 20
                  ? null
                  : () => setState(() {
                        _pets.add(_PetEntry(id: 'pet-${_nextPetId++}'));
                      }),
              icon: const Icon(Icons.add, size: 18),
              label: Text(L10n.text(
                  language, 'Add pet', 'ペットを追加', '添加宠物', '반려동물 추가')),
              style: TextButton.styleFrom(foregroundColor: PawColors.purple),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ...List.generate(_pets.length, (index) => _petFields(index, language)),
      ],
    );
  }

  Widget _petFields(int index, AppLanguage language) {
    final pet = _pets[index];
    return Container(
      key: ValueKey(pet.id),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF8FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PawColors.purple.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: PawColors.lavender,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: PawColors.purpleDark,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  L10n.text(language, 'Pet ${index + 1}', 'ペット ${index + 1}',
                      '宠物 ${index + 1}', '반려동물 ${index + 1}'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: PawColors.ink,
                  ),
                ),
              ),
              if (_pets.length > 1)
                IconButton(
                  tooltip: L10n.text(language, 'Remove pet ${index + 1}',
                      'ペット${index + 1}を削除', '移除宠物 ${index + 1}',
                      '반려동물 ${index + 1} 제거'),
                  onPressed: () => setState(() {
                    final removed = _pets.removeAt(index);
                    removed.dispose();
                  }),
                  icon: const Icon(Icons.delete_outline_rounded,
                      size: 20, color: PawColors.rose),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            L10n.text(language, 'Type', '種類', '类型', '종류'),
            style: const TextStyle(fontSize: 11, color: PawColors.muted),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final type in PetType.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _speciesOption(
                        pet: pet, type: type, language: language),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: pet.name,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: petFieldDecoration(
              hintText: L10n.text(
                  language, 'Pet name', 'ペットの名前', '宠物名字', '반려동물 이름'),
            ).copyWith(
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _speciesOption(
      {required _PetEntry pet, required PetType type, required AppLanguage language}) {
    final selected = pet.type == type;
    return Semantics(
      button: true,
      selected: selected,
      label: '${petTypeName(language, type)} pet type',
      child: InkWell(
        key: ValueKey('pet-type-${pet.id}-${type.name}'),
        onTap: () => setState(() => pet.type = type),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 66,
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? PawColors.purpleDark : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? PawColors.purpleDark
                  : PawColors.purple.withValues(alpha: 0.18),
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: PawColors.purple.withValues(alpha: 0.18),
                      blurRadius: 9,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PetTypeIcon(
                type: type,
                color: selected ? Colors.white : PawColors.purpleDark,
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                petTypeName(language, type),
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : PawColors.ink,
                  fontSize: 10,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _invitationPreview(BuildContext context, HouseholdInvitation invitation,
      CareStore store, AppLanguage language) {
    return PetCard(
      padding: 16,
      color: PawColors.lavender.withValues(alpha: 0.62),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_rounded,
                  color: PawColors.purple, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  L10n.text(language, 'Check before requesting',
                      'リクエスト前に確認', '请求前先确认', '요청 전에 확인하세요'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: PawColors.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            invitation.householdName,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: PawColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${L10n.text(language, 'Invited by', '招待者', '邀请人', '초대한 사람')}: ${invitation.inviterName}',
            style: const TextStyle(fontSize: 13, color: PawColors.muted),
          ),
          const SizedBox(height: 8),
          Text(
            '${L10n.text(language, 'Pets', 'ペット', '宠物', '반려동물')}: ${invitation.petNames.join(', ')}',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: PawColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            L10n.text(
              language,
              'No household tasks or history are visible until the owner approves you.',
              'オーナーの承認までは、家族のタスクや履歴は表示されません。',
              '在房主批准之前，看不到任何家庭任务或历史记录。',
              '소유자 승인 전에는 가족의 작업이나 기록이 표시되지 않습니다.',
            ),
            style: const TextStyle(fontSize: 12, color: PawColors.muted),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                _invite.clear();
                _shownInvitationId = null;
                store.clearInvitationPreview();
                setState(() {});
              },
              child: Text(L10n.text(language, 'This is not my household',
                  'この家族ではありません', '这不是我的家庭', '제 가족이 아닙니다')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pendingRequestCard(
      BuildContext context, HouseholdJoinRequest request, CareStore store) {
    final language = context.watch<AppLanguageStore>().language;
    final rejected = request.status == JoinRequestStatus.rejected;
    return PetCard(
      padding: 24,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: (rejected ? PawColors.rose : PawColors.purple)
                  .withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              rejected ? Icons.close_rounded : Icons.hourglass_top_rounded,
              color: rejected ? PawColors.rose : PawColors.purple,
              size: 30,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            rejected
                ? L10n.text(language, 'Request declined', 'リクエストが拒否されました',
                    '请求被拒绝', '요청이 거절되었습니다')
                : L10n.text(language, 'Waiting for owner approval',
                    'オーナーの承認待ち', '等待房主批准', '소유자 승인 대기 중'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: PawColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            rejected
                ? L10n.text(
                    language,
                    'Ask the household owner for a new invitation if this was unexpected.',
                    '心当たりがない場合は、新しい招待をオーナーに依頼してください。',
                    '如果这是意外情况，请向房主索取新的邀请。',
                    '예상하지 못한 거절이라면 소유자에게 새 초대장을 요청하세요.')
                : L10n.text(
                    language,
                    'Your request was sent as ${request.name}. The household will open automatically after approval.',
                    '${request.name} としてリクエストを送信しました。承認後、自動的に家族が開きます。',
                    '你已以 ${request.name} 的身份发送请求。批准后将自动进入家庭。',
                    '${request.name}(으)로 요청을 보냈습니다. 승인 후 자동으로 가족이 열립니다.'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: PawColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _headerCard(AppLanguage language) {
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
                      'pettogether',
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
                  L10n.text(language, 'Shared care, without the guesswork.',
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
                        L10n.text(language, 'A happier routine for every pet parent',
                            'すべての飼い主に、もっと楽しい毎日を', '让每位宠物家长都更轻松',
                            '모든 반려인에게 더 행복한 일상을'),
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

  Widget _errorBanner(String error) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: PawColors.rose.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: PawColors.rose.withValues(alpha: 0.3)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, color: PawColors.rose, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            error,
            style: const TextStyle(fontSize: 13, color: PawColors.ink),
          ),
        ),
      ],
    ),
  );
}

class _PetEntry {
  _PetEntry({required this.id}) : name = TextEditingController();

  final String id;
  final TextEditingController name;
  PetType? type;

  Pet toPet() =>
      Pet(id: id, name: name.text.trim(), type: type ?? PetType.cat);

  void dispose() => name.dispose();
}
