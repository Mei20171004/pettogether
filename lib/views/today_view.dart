import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/care_catalog.dart';
import '../models/models.dart';
import '../store/care_store.dart';
import '../store/pro_access.dart';
import '../theme/app_theme.dart';
import 'add_task_view.dart';
import 'pet_detail_view.dart';
import 'pro_view.dart';
import 'profile_edit_view.dart';
import 'widgets/common.dart';
import 'widgets/pet_time_picker.dart';
import 'widgets/task_card.dart';

class TodayView extends StatefulWidget {
  const TodayView({super.key, this.photoPicker});

  /// Test seam for the platform photo picker. Production uses [ImagePicker].
  final Future<Uint8List?> Function()? photoPicker;

  @override
  State<TodayView> createState() => _TodayViewState();
}

class _TodayViewState extends State<TodayView> {
  /// Pet the task lists are filtered to. Null means every pet ("All").
  String? _selectedPetId;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CareStore>();
    final language = context.watch<AppLanguageStore>().language;

    // Drop a stale filter if the pet was removed from the household.
    final pets = store.household?.pets ?? const <Pet>[];
    if (_selectedPetId != null && !pets.any((p) => p.id == _selectedPetId)) {
      _selectedPetId = null;
    }

    final unclaimed = _filtered(store.unclaimedTasks);
    final claimed = _filtered(store.claimedTasks);
    final completed = _filtered(store.completedTasks);
    final skipped = _filtered(store.skippedTasks);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(L10n.text(language, 'Today', '今日', '今天', '오늘')),
        actions: [
          PopupMenuButton<AppLanguage>(
            icon: const Icon(Icons.language, color: PawColors.purple),
            onSelected: (value) =>
                context.read<AppLanguageStore>().language = value,
            itemBuilder: (context) => [
              for (final item in AppLanguage.values)
                PopupMenuItem(
                  value: item,
                  child: Row(
                    children: [
                      if (language == item) ...[
                        const Icon(Icons.check, size: 18),
                        const SizedBox(width: 6),
                      ],
                      Text(item.label),
                    ],
                  ),
                ),
            ],
          ),
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) => const AddTaskView(),
              ),
            ),
            icon: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: PawColors.purple,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, size: 20, color: Colors.white),
            ),
          ),
        ],
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
                    _greetingHeader(context, store, language),
                    const SizedBox(height: 20),
                    _petHeroCard(context, store, language),
                    const SizedBox(height: 20),
                    _progressCard(
                      context,
                      language,
                      completed: completed.length,
                      total:
                          unclaimed.length + claimed.length + completed.length,
                    ),
                    if (pets.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      PetSectionTitle(
                        title: L10n.text(
                          language,
                          'My pets',
                          'うちの子',
                          '我的宠物',
                          '우리 아이들',
                        ),
                        detail:
                            '${pets.length} ${L10n.text(language, pets.length == 1 ? 'PET' : 'PETS', '匹', '只宠物', '마리')}',
                      ),
                      const SizedBox(height: 12),
                      _petFilterChips(context, store, pets, language),
                    ],
                    ..._healthDueBanner(context, store, language),
                    const SizedBox(height: 20),
                    _section(
                      title: L10n.text(
                        language,
                        'Needs a person',
                        '担当が必要',
                        '需要人照顾',
                        '담당자 필요',
                      ),
                      detail: unclaimed.isEmpty
                          ? L10n.text(language, 'CLEAR', 'なし', '无', '없음')
                          : '${unclaimed.length} ${L10n.text(language, 'UNCLAIMED', '未担当', '未认领', '미담당')}',
                      child: unclaimed.isEmpty
                          ? _emptyState(context, language)
                          : Column(
                              children: [
                                for (final task in unclaimed)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: TaskCard(
                                      task: task,
                                      onEdit:
                                          task.assignmentRequest == null &&
                                              store.planForTask(task) == null
                                          ? () => _showTaskEditor(
                                              context,
                                              store,
                                              task,
                                              language,
                                            )
                                          : null,
                                      onDelete:
                                          task.assignmentRequest == null &&
                                              store.planForTask(task) == null
                                          ? () => _confirmDeleteTask(
                                              context,
                                              store,
                                              task,
                                              language,
                                            )
                                          : null,
                                    ),
                                  ),
                              ],
                            ),
                    ),
                    if (claimed.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _section(
                        title: L10n.text(
                          language,
                          'In progress',
                          '進行中',
                          '进行中',
                          '진행 중',
                        ),
                        detail:
                            '${claimed.length} ${L10n.text(language, 'CLAIMED', '担当者あり', '已认领', '담당자 있음')}',
                        child: Column(
                          children: [
                            for (final task in claimed)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: TaskCard(task: task),
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (completed.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _section(
                        title: L10n.text(
                          language,
                          'Done today',
                          '今日の完了',
                          '今日已完成',
                          '오늘 완료',
                        ),
                        detail: L10n.text(
                          language,
                          'SHARED CARE',
                          'みんなのケア',
                          '共同照护',
                          '함께하는 케어',
                        ),
                        child: Column(
                          children: [
                            for (final task in completed.take(3))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: TaskCard(task: task),
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (skipped.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _section(
                        title: L10n.text(
                          language,
                          'Skipped today',
                          '今日スキップ',
                          '今日已跳过',
                          '오늘 건너뜀',
                        ),
                        detail:
                            '${skipped.length} ${L10n.text(language, 'SKIPPED', 'スキップ', '已跳过', '건너뜀')}',
                        child: Column(
                          children: [
                            for (final task in skipped)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: TaskCard(task: task),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Tasks narrowed to the selected pet chip; everything when "All" is active.
  List<CareTask> _filtered(List<CareTask> tasks) {
    final petId = _selectedPetId;
    if (petId == null) return tasks;
    return tasks
        .where((t) => t.effectivePetIds.contains(petId) || t.petID == petId)
        .toList();
  }

  Widget _greetingHeader(
    BuildContext context,
    CareStore store,
    AppLanguage language,
  ) {
    final now = DateTime.now();
    final hour = now.hour;
    final greeting = hour < 12
        ? L10n.text(language, 'Good morning', 'おはよう', '早上好', '좋은 아침')
        : hour < 18
        ? L10n.text(language, 'Good afternoon', 'こんにちは', '下午好', '좋은 오후')
        : L10n.text(language, 'Good evening', 'こんばんは', '晚上好', '좋은 저녁');
    final name =
        store.currentCaregiver?.displayName ??
        L10n.text(language, 'pet parent', '飼い主さん', '铲屎官', '집사님');
    final dateLine = DateFormat.MMMMEEEEd(language.rawValue).format(now);
    final comma = switch (language) {
      AppLanguage.japanese => '、',
      AppLanguage.chinese => '，',
      _ => ', ',
    };

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$greeting$comma$name 👋',
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                  color: PawColors.ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                dateLine,
                style: const TextStyle(fontSize: 14, color: PawColors.muted),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => const ProfileEditView(),
            ),
          ),
          style: IconButton.styleFrom(
            backgroundColor: Colors.white,
            fixedSize: const Size(44, 44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
          icon: const Icon(Icons.person, color: PawColors.purple),
        ),
      ],
    );
  }

  /// Copaw-style progress card: big done/total line, percent badge, bar.
  Widget _progressCard(
    BuildContext context,
    AppLanguage language, {
    required int completed,
    required int total,
  }) {
    final percent = total == 0 ? 0 : (completed / total * 100).round();
    final tip = completed == 0
        ? L10n.text(
            language,
            '🐾 A fresh day of care starts here.',
            '🐾 今日のケアはここから。',
            '🐾 新的一天照护从这里开始。',
            '🐾 오늘의 케어는 여기서 시작해요.',
          )
        : completed == total
        ? L10n.text(
            language,
            '✨ All wrapped up — time for cuddles!',
            '✨ 全部おわり。なでなでの時間！',
            '✨ 全部完成，该抱抱了！',
            '✨ 다 끝났어요. 안아줄 시간!',
          )
        : L10n.text(
            language,
            '✨ Great teamwork — keep it up!',
            '✨ いいチームワーク、この調子！',
            '✨ 大家配合得很棒，继续保持！',
            '✨ 팀워크 최고예요, 계속 가요!',
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
          boxShadow: [
            BoxShadow(
              color: PawColors.purpleDark.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, 9),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Soft sky orb peeking in from the corner, like the Copaw card.
            Positioned(
              top: -46,
              right: -36,
              child: Container(
                width: 130,
                height: 130,
                decoration: const BoxDecoration(
                  color: PawColors.lavender,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              L10n.text(
                                language,
                                "Today's care progress",
                                '今日のケア進捗',
                                '今日照护进度',
                                '오늘의 케어 진행',
                              ),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: PawColors.muted,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text.rich(
                              TextSpan(
                                text:
                                    '${L10n.text(language, 'Done', '完了', '已完成', '완료')} $completed',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: PawColors.purpleDark,
                                ),
                                children: [
                                  TextSpan(
                                    text:
                                        ' / $total ${L10n.text(language, 'tasks', '件', '项', '건')}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: PawColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 54,
                        height: 54,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: PawColors.skyTint,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$percent%',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: PawColors.purple,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : completed / total,
                      minHeight: 8,
                      backgroundColor: PawColors.lavender,
                      valueColor: const AlwaysStoppedAnimation(
                        PawColors.purple,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tip,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: PawColors.ink,
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

  /// Horizontal "All / each pet" chip strip that filters the task lists.
  Widget _petFilterChips(
    BuildContext context,
    CareStore store,
    List<Pet> pets,
    AppLanguage language,
  ) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _petChip(
            key: const ValueKey('today-pet-filter-all'),
            label: L10n.text(language, 'All', 'すべて', '全部', '전체'),
            emoji: '🏠',
            selected: _selectedPetId == null,
            onTap: () => setState(() => _selectedPetId = null),
          ),
          for (final pet in pets)
            _petChip(
              key: ValueKey('today-pet-filter-${pet.id}'),
              label: pet.name,
              emoji: petTypeEmoji(pet.type),
              selected: _selectedPetId == pet.id,
              onTap: () => setState(() => _selectedPetId = pet.id),
            ),
          TextButton.icon(
            key: const ValueKey('today-add-pet-button'),
            onPressed: pets.length >= 20
                ? null
                : () => _showAddPetDialog(context, store, language),
            icon: const Icon(Icons.add, size: 18),
            label: Text(
              L10n.text(language, 'Add pet', 'ペットを追加', '添加宠物', '반려동물 추가'),
            ),
            style: TextButton.styleFrom(foregroundColor: PawColors.purple),
          ),
        ],
      ),
    );
  }

  Widget _petChip({
    required Key key,
    required String label,
    required String emoji,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 9),
      child: Material(
        key: key,
        color: selected
            ? PawColors.purple
            : Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected
                    ? PawColors.purple
                    : PawColors.purple.withValues(alpha: 0.14),
              ),
            ),
            child: Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 15)),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : PawColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _petHeroCard(
    BuildContext context,
    CareStore store,
    AppLanguage language,
  ) {
    final remaining =
        _filtered(store.unclaimedTasks).length +
        _filtered(store.claimedTasks).length;
    final summary = remaining == 0
        ? L10n.text(
            language,
            'Everything is handled. Time for cuddles.',
            '全部おわり。なでなでの時間。',
            '一切都处理好了，该抱抱了。',
            '다 끝났어요. 이제 안아줄 시간이에요.',
          )
        : '$remaining ${L10n.text(language, 'care moments left for today.', '件のケアが残っています。', '个护理待完成。', '건의 케어가 남았습니다.')}';

    return _PetHeroCarousel(
      pets: store.household?.pets ?? const <Pet>[],
      selectedPetId: _selectedPetId,
      summary: summary,
      householdName: store.household?.name ?? '',
      language: language,
      onChoosePhoto: (pet) => _choosePetPhoto(context, store, pet, language),
      onSelectedPet: (petId) => setState(() => _selectedPetId = petId),
      onEditPet: (pet) => _showPetEditor(context, store, pet, language),
      onDeletePet: (pet) => _confirmDeletePet(context, store, pet, language),
    );
  }

  Future<void> _choosePetPhoto(
    BuildContext context,
    CareStore store,
    Pet pet,
    AppLanguage language,
  ) async {
    try {
      final bytes =
          await (widget.photoPicker?.call() ?? _pickPhotoFromGallery());
      if (bytes == null) return;
      await store.savePetPhoto(pet, bytes);
    } on PlatformException catch (error) {
      if (!context.mounted) return;
      final detail = '${error.code} ${error.message ?? ''}'.toLowerCase();
      final permissionDenied =
          detail.contains('denied') ||
          detail.contains('permission') ||
          detail.contains('access');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            permissionDenied
                ? L10n.text(
                    language,
                    'Photos access is off. Allow pettogether to access Photos in Settings, then try again.',
                    '写真へのアクセスがオフです。設定で pettogether の写真アクセスを許可して、もう一度お試しください。',
                    '照片权限已关闭。请在系统设置中允许 pettogether 访问照片，然后重试。',
                    '사진 접근이 꺼져 있습니다. 설정에서 pettogether의 사진 접근을 허용한 뒤 다시 시도하세요.',
                  )
                : L10n.text(
                    language,
                    "Couldn't open Photos. Please try again.",
                    '写真を開けませんでした。もう一度お試しください。',
                    '无法打开相册，请重试。',
                    '사진을 열 수 없습니다. 다시 시도하세요.',
                  ),
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            L10n.text(
              language,
              "Couldn't use that photo. Please try another one.",
              'その写真を使用できませんでした。別の写真をお試しください。',
              '无法使用这张照片，请换一张重试。',
              '이 사진을 사용할 수 없습니다. 다른 사진으로 다시 시도하세요.',
            ),
          ),
        ),
      );
    }
  }

  Future<Uint8List?> _pickPhotoFromGallery() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 82,
    );
    return image?.readAsBytes();
  }

  Future<void> _showAddPetDialog(
    BuildContext context,
    CareStore store,
    AppLanguage language,
  ) async {
    if (!context.read<ProAccess>().canAddPet) {
      await showProPaywall(
        context,
        feature: ProFeature.multiPet,
        reason: L10n.text(
          language,
          'Your first pet is free. Adding a second pet requires the multi-pet plan.',
          '1匹目は無料です。2匹目の追加には複数ペットプランが必要です。',
          '第 1 只宠物免费；添加第 2 只需要开通多宠物功能。',
          '첫 반려동물은 무료이며, 두 번째 반려동물부터 다중 반려동물 플랜이 필요합니다.',
        ),
      );
      return;
    }

    var name = '';
    var type = PetType.cat;
    String? nameError;
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            L10n.text(language, 'Add pet', 'ペットを追加', '添加宠物', '반려동물 추가'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('today-add-pet-name'),
                autofocus: true,
                onChanged: (value) => name = value,
                decoration: petFieldDecoration(
                  hintText: L10n.text(
                    language,
                    'Pet name · Required',
                    'ペットの名前・必須',
                    '宠物名字 · 必填',
                    '반려동물 이름 · 필수',
                  ),
                ).copyWith(errorText: nameError),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in PetType.values)
                    ChoiceChip(
                      avatar: Text(petTypeEmoji(item)),
                      label: Text(petTypeName(language, item)),
                      selected: type == item,
                      onSelected: (_) => setDialogState(() => type = item),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(L10n.text(language, 'Cancel', 'キャンセル', '取消', '취소')),
            ),
            FilledButton(
              key: const ValueKey('today-add-pet-save'),
              onPressed: () {
                if (name.trim().isEmpty) {
                  setDialogState(() {
                    nameError = L10n.text(
                      language,
                      'Enter a pet name.',
                      'ペットの名前を入力してください。',
                      '请输入宠物名字。',
                      '반려동물 이름을 입력하세요.',
                    );
                  });
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: Text(L10n.text(language, 'Save', '保存', '保存', '저장')),
            ),
          ],
        ),
      ),
    );

    final petName = name.trim();
    if (shouldSave != true) return;
    final added = await store.addPet(name: petName, type: type);
    if (!added && context.mounted) _showStoreError(context, store);
  }

  Future<void> _showPetEditor(
    BuildContext context,
    CareStore store,
    Pet pet,
    AppLanguage language,
  ) async {
    var name = pet.name;
    var age = pet.ageYears?.toString() ?? '';
    var weight = pet.weightKg?.toString() ?? '';
    var habits = pet.habits ?? '';
    var type = pet.type;

    final updated = await showDialog<Pet>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            L10n.text(language, 'Edit pet', 'ペットを編集', '编辑宠物', '반려동물 편집'),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const ValueKey('today-pet-name-field'),
                  initialValue: name,
                  onChanged: (value) => name = value,
                  autofocus: true,
                  decoration: petFieldDecoration(
                    hintText: L10n.text(
                      language,
                      'Pet name',
                      'ペットの名前',
                      '宠物名字',
                      '반려동물 이름',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in PetType.values)
                      ChoiceChip(
                        avatar: Text(petTypeEmoji(item)),
                        label: Text(petTypeName(language, item)),
                        selected: type == item,
                        onSelected: (_) => setDialogState(() => type = item),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: age,
                  onChanged: (value) => age = value,
                  keyboardType: TextInputType.number,
                  decoration: petFieldDecoration(
                    hintText: L10n.text(
                      language,
                      'Age (years)',
                      '年齢（歳）',
                      '年龄（岁）',
                      '나이(세)',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: weight,
                  onChanged: (value) => weight = value,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: petFieldDecoration(
                    hintText: L10n.text(
                      language,
                      'Weight (kg)',
                      '体重（kg）',
                      '体重（公斤）',
                      '몸무게(kg)',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: habits,
                  onChanged: (value) => habits = value,
                  decoration: petFieldDecoration(
                    hintText: L10n.text(
                      language,
                      'Habits & notes',
                      '習性・メモ',
                      '习性和备注',
                      '습성 및 메모',
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
              onPressed: () {
                final trimmedName = name.trim();
                if (trimmedName.isEmpty) return;
                final ageText = age.trim();
                final weightText = weight.trim();
                final habitsText = habits.trim();
                Navigator.pop(
                  dialogContext,
                  pet.copyWith(
                    name: trimmedName,
                    type: type,
                    ageYears: int.tryParse(ageText),
                    weightKg: double.tryParse(weightText),
                    habits: habitsText.isEmpty ? null : habitsText,
                    clearAge: ageText.isEmpty,
                    clearWeightKg: weightText.isEmpty,
                    clearHabits: habitsText.isEmpty,
                  ),
                );
              },
              child: Text(L10n.text(language, 'Save', '保存', '保存', '저장')),
            ),
          ],
        ),
      ),
    );

    if (updated == null) return;
    final saved = await store.updatePet(updated);
    if (!saved && context.mounted) _showStoreError(context, store);
  }

  Future<void> _confirmDeletePet(
    BuildContext context,
    CareStore store,
    Pet pet,
    AppLanguage language,
  ) async {
    final pets = store.household?.pets ?? const <Pet>[];
    if (pets.length <= 1) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            L10n.text(
              language,
              'Keep one pet',
              'ペットを1匹残してください',
              '请至少保留一只宠物',
              '반려동물을 한 마리 이상 남겨주세요',
            ),
          ),
          content: Text(
            L10n.text(
              language,
              'Add another pet before deleting ${pet.name}.',
              '${pet.name}を削除する前に、別のペットを追加してください。',
              '请先添加另一只宠物，再删除 ${pet.name}。',
              '${pet.name}을(를) 삭제하기 전에 다른 반려동물을 추가하세요.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(L10n.text(language, 'OK', 'OK', '知道了', '확인')),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          L10n.text(
            language,
            'Delete ${pet.name}?',
            '${pet.name}を削除しますか？',
            '删除 ${pet.name}？',
            '${pet.name}을(를) 삭제할까요?',
          ),
        ),
        content: Text(
          L10n.text(
            language,
            'This removes the pet profile. Existing care history is kept.',
            'ペット情報を削除します。これまでのケア履歴は残ります。',
            '这会删除宠物资料，但会保留已有的照护记录。',
            '반려동물 프로필은 삭제되지만 기존 돌봄 기록은 유지됩니다.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(L10n.text(language, 'Cancel', 'キャンセル', '取消', '취소')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(L10n.text(language, 'Delete', '削除', '删除', '삭제')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final deleted = await store.removePet(pet.id);
    if (!deleted && context.mounted) _showStoreError(context, store);
  }

  Future<void> _showTaskEditor(
    BuildContext context,
    CareStore store,
    CareTask task,
    AppLanguage language,
  ) async {
    var title = task.title;
    var dueTime = task.dueTime;
    final selectedPetIds = task.effectivePetIds.toSet();
    final pets = store.household?.pets ?? const <Pet>[];

    final draft =
        await showDialog<
          ({String title, DateTime dueTime, List<String> petIds})
        >(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: Text(
                L10n.text(
                  language,
                  task.kind == CareTaskKind.routine
                      ? 'Edit repeating task'
                      : 'Edit task',
                  task.kind == CareTaskKind.routine ? '繰り返しを編集' : 'タスクを編集',
                  task.kind == CareTaskKind.routine ? '编辑重复任务' : '编辑任务',
                  task.kind == CareTaskKind.routine ? '반복 작업 편집' : '작업 편집',
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      key: const ValueKey('today-task-title-field'),
                      initialValue: title,
                      onChanged: (value) => title = value,
                      autofocus: true,
                      decoration: petFieldDecoration(
                        hintText: L10n.text(
                          language,
                          'Task name',
                          'タスク名',
                          '任务名称',
                          '작업 이름',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule),
                      title: Text(
                        DateFormat.jm(language.rawValue).format(dueTime),
                      ),
                      subtitle: Text(
                        task.kind == CareTaskKind.routine
                            ? L10n.text(
                                language,
                                'Applies to future occurrences',
                                '今後の予定に適用',
                                '应用于之后的任务',
                                '향후 일정에 적용',
                              )
                            : DateFormat.yMMMd(language.rawValue)
                                  .format(dueTime),
                      ),
                      onTap: () async {
                        final picked = await showPetTimePicker(
                          context: dialogContext,
                          initialTime: TimeOfDay.fromDateTime(dueTime),
                          language: language,
                        );
                        if (picked == null) return;
                        setDialogState(() {
                          dueTime = DateTime(
                            dueTime.year,
                            dueTime.month,
                            dueTime.day,
                            picked.hour,
                            picked.minute,
                          );
                        });
                      },
                    ),
                    if (task.kind == CareTaskKind.oneOff)
                      TextButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: dialogContext,
                            firstDate: DateTime.now().subtract(
                              const Duration(days: 365),
                            ),
                            lastDate: DateTime.now().add(
                              const Duration(days: 3650),
                            ),
                            initialDate: dueTime,
                          );
                          if (picked == null) return;
                          setDialogState(() {
                            dueTime = DateTime(
                              picked.year,
                              picked.month,
                              picked.day,
                              dueTime.hour,
                              dueTime.minute,
                            );
                          });
                        },
                        icon: const Icon(Icons.calendar_today_outlined),
                        label: Text(
                          L10n.text(
                            language,
                            'Change date',
                            '日付を変更',
                            '修改日期',
                            '날짜 변경',
                          ),
                        ),
                      ),
                    if (pets.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        L10n.text(language, 'Pet', 'ペット', '宠物', '반려동물'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilterChip(
                            label: Text(
                              L10n.text(
                                language,
                                'All pets',
                                'すべて',
                                '全部宠物',
                                '모든 반려동물',
                              ),
                            ),
                            selected: selectedPetIds.isEmpty,
                            onSelected: (_) =>
                                setDialogState(selectedPetIds.clear),
                          ),
                          for (final pet in pets)
                            FilterChip(
                              label: Text(
                                '${petTypeEmoji(pet.type)} ${pet.name}',
                              ),
                              selected: selectedPetIds.contains(pet.id),
                              onSelected: (selected) => setDialogState(() {
                                if (selected) {
                                  selectedPetIds.add(pet.id);
                                } else {
                                  selectedPetIds.remove(pet.id);
                                }
                              }),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(
                    L10n.text(language, 'Cancel', 'キャンセル', '取消', '취소'),
                  ),
                ),
                FilledButton(
                  onPressed: () {
                    final trimmedTitle = title.trim();
                    if (trimmedTitle.isEmpty) return;
                    Navigator.pop(dialogContext, (
                      title: trimmedTitle,
                      dueTime: dueTime,
                      petIds: selectedPetIds.toList(),
                    ));
                  },
                  child: Text(L10n.text(language, 'Save', '保存', '保存', '저장')),
                ),
              ],
            ),
          ),
        );
    if (draft == null) return;
    final saved = await store.updateTaskDetails(
      task,
      title: draft.title,
      dueTime: draft.dueTime,
      petIds: draft.petIds,
    );
    if (!saved && context.mounted) _showStoreError(context, store);
  }

  Future<void> _confirmDeleteTask(
    BuildContext context,
    CareStore store,
    CareTask task,
    AppLanguage language,
  ) async {
    final isRoutine = task.kind == CareTaskKind.routine;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          L10n.text(
            language,
            'Delete ${task.title}?',
            '${task.title}を削除しますか？',
            '删除 ${task.title}？',
            '${task.title}을(를) 삭제할까요?',
          ),
        ),
        content: Text(
          isRoutine
              ? L10n.text(
                  language,
                  'This deletes the repeating schedule. Completed history is kept.',
                  '繰り返し予定を削除します。完了履歴は残ります。',
                  '这会删除整条重复计划，但保留已完成记录。',
                  '반복 일정을 삭제하지만 완료 기록은 유지됩니다.',
                )
              : L10n.text(
                  language,
                  'This task will be permanently deleted.',
                  'このタスクは完全に削除されます。',
                  '这个任务将被永久删除。',
                  '이 작업은 영구적으로 삭제됩니다.',
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(L10n.text(language, 'Cancel', 'キャンセル', '取消', '취소')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(L10n.text(language, 'Delete', '削除', '删除', '삭제')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final deleted = await store.deleteTask(task);
    if (!deleted && context.mounted) _showStoreError(context, store);
  }

  void _showStoreError(BuildContext context, CareStore store) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(store.errorMessage ?? 'Something went wrong.')),
    );
  }

  /// Vaccinations and dewormings coming due. Small and quiet until something
  /// is actually close, then impossible to miss.
  List<Widget> _healthDueBanner(
    BuildContext context,
    CareStore store,
    AppLanguage language,
  ) {
    final due = store.upcomingHealthDue();
    if (due.isEmpty) return const [];
    final soonest = due.first;
    final pet = store.household?.pets
        .where((p) => p.id == soonest.record.petId)
        .firstOrNull;
    if (pet == null) return const [];

    final urgent = soonest.daysUntilDue <= 0;
    final color = urgent ? PawColors.rose : PawColors.yellow;
    final when = soonest.isOverdue
        ? L10n.text(
            language,
            'was due ${-soonest.daysUntilDue} days ago',
            '${-soonest.daysUntilDue}日前が期限',
            '已过期 ${-soonest.daysUntilDue} 天',
            '${-soonest.daysUntilDue}일 지남',
          )
        : soonest.isDueToday
        ? L10n.text(language, 'is due today', '今日が期限', '今天到期', '오늘 마감')
        : L10n.text(
            language,
            'is due in ${soonest.daysUntilDue} days',
            'あと${soonest.daysUntilDue}日',
            '还有 ${soonest.daysUntilDue} 天到期',
            '${soonest.daysUntilDue}일 남음',
          );

    return [
      const SizedBox(height: 20),
      InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => PetDetailView(pet: pet))),
        child: PetCard(
          padding: 14,
          child: Row(
            children: [
              EmojiCareIcon(emoji: '💉', color: color, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${pet.name} · ${soonest.record.title}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: PawColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      when,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: PawColors.muted),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _section({
    required String title,
    required String? detail,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PetSectionTitle(title: title, detail: detail),
        const SizedBox(height: 12),
        child,
      ],
    );
  }

  Widget _emptyState(BuildContext context, AppLanguage language) {
    return PetCard(
      child: Column(
        children: [
          const EmojiCareIcon(emoji: '🎉', color: PawColors.green, size: 56),
          const SizedBox(height: 10),
          Text(
            L10n.text(
              language,
              'Everything is handled',
              '全部おわり',
              '一切都处理好了',
              '다 끝났어요',
            ),
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: PawColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            L10n.text(
              language,
              'Add another task when your pet needs care.',
              'ケアが必要になったらタスクを追加しましょう。',
              '宠物需要照顾时，再添加一个任务。',
              '반려동물에게 케어가 필요할 때 할 일을 추가하세요.',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: PawColors.muted),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) => const AddTaskView(),
              ),
            ),
            child: Text(
              L10n.text(language, 'Add a task', 'タスクを追加', '添加任务', '할 일 추가'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PetHeroCarousel extends StatefulWidget {
  const _PetHeroCarousel({
    required this.pets,
    required this.selectedPetId,
    required this.summary,
    required this.householdName,
    required this.language,
    required this.onChoosePhoto,
    required this.onSelectedPet,
    required this.onEditPet,
    required this.onDeletePet,
  });

  final List<Pet> pets;
  final String? selectedPetId;
  final String summary;
  final String householdName;
  final AppLanguage language;
  final void Function(Pet pet) onChoosePhoto;
  final ValueChanged<String> onSelectedPet;
  final void Function(Pet pet) onEditPet;
  final void Function(Pet pet) onDeletePet;

  @override
  State<_PetHeroCarousel> createState() => _PetHeroCarouselState();
}

class _PetHeroCarouselState extends State<_PetHeroCarousel> {
  late final PageController _controller;
  late int _index;
  bool _isSyncingToSelection = false;

  @override
  void initState() {
    super.initState();
    _index = _selectedIndex();
    _controller = PageController(initialPage: _index);
  }

  @override
  void didUpdateWidget(covariant _PetHeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectedIndex = _selectedIndex();
    if (selectedIndex == _index) return;
    _index = selectedIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      _isSyncingToSelection = true;
      _controller
          .animateToPage(
            selectedIndex,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          )
          .whenComplete(() {
            if (mounted) _isSyncingToSelection = false;
          });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int _selectedIndex() {
    final selectedPetId = widget.selectedPetId;
    if (selectedPetId == null) return 0;
    final index = widget.pets.indexWhere((pet) => pet.id == selectedPetId);
    return index < 0 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    final pets = widget.pets;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [PawColors.lavender, PawColors.peach.withValues(alpha: 0.72)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: PawColors.purpleDark.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            height: 170,
            child: PageView.builder(
              controller: _controller,
              itemCount: pets.isEmpty ? 1 : pets.length,
              onPageChanged: (i) {
                setState(() => _index = i);
                if (pets.isNotEmpty && !_isSyncingToSelection) {
                  widget.onSelectedPet(pets[i].id);
                }
              },
              itemBuilder: (context, i) =>
                  _slide(context, pets.isEmpty ? null : pets[i]),
            ),
          ),
          if (pets.length > 1) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < pets.length; i++) _dot(i == _index),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _slide(BuildContext context, Pet? pet) {
    final language = widget.language;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.auto_awesome,
                    size: 14,
                    color: PawColors.purple,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    L10n.text(
                      language,
                      "TODAY'S PETTOGETHER",
                      '今日のペットゥギャザー',
                      '今日的 PETTOGETHER',
                      '오늘의 펫투게더',
                    ),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: PawColors.purple,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      pet?.name ??
                          L10n.text(
                            language,
                            'Your pet',
                            'あなたのペット',
                            '你的宠物',
                            '반려동물',
                          ),
                      key: ValueKey('today-hero-pet-${pet?.id ?? 'empty'}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: PawColors.ink,
                      ),
                    ),
                  ),
                  if (pet != null)
                    PopupMenuButton<_PetMenuAction>(
                      key: ValueKey('today-pet-menu-${pet.id}'),
                      tooltip: L10n.text(
                        language,
                        'Manage pet',
                        'ペットを管理',
                        '管理宠物',
                        '반려동물 관리',
                      ),
                      onSelected: (action) {
                        switch (action) {
                          case _PetMenuAction.edit:
                            widget.onEditPet(pet);
                          case _PetMenuAction.delete:
                            widget.onDeletePet(pet);
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: _PetMenuAction.edit,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.edit_outlined),
                            title: Text(
                              L10n.text(
                                language,
                                'Edit pet',
                                'ペットを編集',
                                '编辑宠物',
                                '반려동물 편집',
                              ),
                            ),
                          ),
                        ),
                        PopupMenuItem(
                          value: _PetMenuAction.delete,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.delete_outline,
                              color: Colors.red,
                            ),
                            title: Text(
                              L10n.text(
                                language,
                                'Delete pet',
                                'ペットを削除',
                                '删除宠物',
                                '반려동물 삭제',
                              ),
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              if (pet != null) ...[
                const SizedBox(height: 3),
                Text(
                  [
                    '${petTypeEmoji(pet.type)} ${petTypeName(language, pet.type)}',
                    if (pet.ageYears != null)
                      '${pet.ageYears} ${L10n.text(language, 'years old', '歳', '岁', '살')}',
                  ].join(' · '),
                  style: const TextStyle(
                    fontSize: 12,
                    color: PawColors.purpleDark,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                widget.summary,
                key: ValueKey('today-hero-summary-${pet?.id ?? 'empty'}'),
                style: const TextStyle(fontSize: 13, color: PawColors.muted),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.home, size: 15, color: PawColors.purpleDark),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      widget.householdName.isEmpty
                          ? L10n.text(
                              language,
                              'Your household',
                              'あなたの家族',
                              '你的家庭',
                              '가족',
                            )
                          : widget.householdName,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: PawColors.purpleDark,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        InkWell(
          key: ValueKey('today-hero-photo-action-${pet?.id ?? 'empty'}'),
          onTap: pet == null ? null : () => widget.onChoosePhoto(pet),
          borderRadius: BorderRadius.circular(21),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(21),
            child: SizedBox(width: 138, height: 156, child: _petPhoto(pet)),
          ),
        ),
      ],
    );
  }

  Widget _petPhoto(Pet? pet) {
    final photoURL = pet?.photoURL;
    if (photoURL == null || photoURL.isEmpty) {
      return _addPhotoPlaceholder(pet);
    }
    return Image.network(
      photoURL,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _addPhotoPlaceholder(pet),
    );
  }

  Widget _addPhotoPlaceholder(Pet? pet) {
    return Container(
      key: ValueKey('today-hero-add-photo-${pet?.id ?? 'empty'}'),
      color: Colors.white.withValues(alpha: 0.72),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.add_a_photo_outlined,
            size: 38,
            color: PawColors.purple,
          ),
          const SizedBox(height: 8),
          Text(
            L10n.text(widget.language, 'Add photo', '写真を追加', '添加照片', '사진 추가'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: PawColors.purpleDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(bool active) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 3),
      width: active ? 20 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: active
            ? PawColors.purple
            : PawColors.purple.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

enum _PetMenuAction { edit, delete }
