import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/care_catalog.dart';
import '../models/models.dart';
import '../store/care_store.dart';
import '../theme/app_theme.dart';
import 'add_task_view.dart';
import 'pet_detail_view.dart';
import 'profile_edit_view.dart';
import 'widgets/common.dart';
import 'widgets/task_card.dart';

class TodayView extends StatefulWidget {
  const TodayView({super.key});

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
                    _progressCard(context, language,
                        completed: completed.length,
                        total: unclaimed.length +
                            claimed.length +
                            completed.length),
                    if (pets.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      PetSectionTitle(
                        title: L10n.text(
                            language, 'My pets', 'うちの子', '我的宠物', '우리 아이들'),
                        detail:
                            '${pets.length} ${L10n.text(language, pets.length == 1 ? 'PET' : 'PETS', '匹', '只宠物', '마리')}',
                      ),
                      const SizedBox(height: 12),
                      _petFilterChips(pets, language),
                    ],
                    ..._healthDueBanner(context, store, language),
                    const SizedBox(height: 20),
                    _section(
                      title: L10n.text(
                          language, 'Needs a person', '担当が必要', '需要人照顾', '담당자 필요'),
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
                                    child: TaskCard(task: task),
                                  ),
                              ],
                            ),
                    ),
                    if (claimed.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _section(
                        title: L10n.text(
                            language, 'In progress', '進行中', '进行中', '진행 중'),
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
                            language, 'Done today', '今日の完了', '今日已完成', '오늘 완료'),
                        detail: L10n.text(language, 'SHARED CARE', 'みんなのケア',
                            '共同照护', '함께하는 케어'),
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
                        title: L10n.text(language, 'Skipped today',
                            '今日スキップ', '今日已跳过', '오늘 건너뜀'),
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
      BuildContext context, CareStore store, AppLanguage language) {
    final now = DateTime.now();
    final hour = now.hour;
    final greeting = hour < 12
        ? L10n.text(language, 'Good morning', 'おはよう', '早上好', '좋은 아침')
        : hour < 18
            ? L10n.text(language, 'Good afternoon', 'こんにちは', '下午好', '좋은 오후')
            : L10n.text(language, 'Good evening', 'こんばんは', '晚上好', '좋은 저녁');
    final name = store.currentCaregiver?.displayName ??
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
  Widget _progressCard(BuildContext context, AppLanguage language,
      {required int completed, required int total}) {
    final percent = total == 0 ? 0 : (completed / total * 100).round();
    final tip = completed == 0
        ? L10n.text(language, '🐾 A fresh day of care starts here.',
            '🐾 今日のケアはここから。', '🐾 新的一天照护从这里开始。', '🐾 오늘의 케어는 여기서 시작해요.')
        : completed == total
            ? L10n.text(language, '✨ All wrapped up — time for cuddles!',
                '✨ 全部おわり。なでなでの時間！', '✨ 全部完成，该抱抱了！', '✨ 다 끝났어요. 안아줄 시간!')
            : L10n.text(language, '✨ Great teamwork — keep it up!',
                '✨ いいチームワーク、この調子！', '✨ 大家配合得很棒，继续保持！',
                '✨ 팀워크 최고예요, 계속 가요!');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [PawColors.purple, PawColors.purpleDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: PawColors.purpleDark.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
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
                      L10n.text(language, "Today's care progress",
                          '今日のケア進捗', '今日照护进度', '오늘의 케어 진행'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.78),
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
                          color: Colors.white,
                        ),
                        children: [
                          TextSpan(
                            text:
                                ' / $total ${L10n.text(language, 'tasks', '件', '项', '건')}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.72),
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
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  '$percent%',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
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
              backgroundColor: Colors.white.withValues(alpha: 0.22),
              valueColor: const AlwaysStoppedAnimation(PawColors.yellow),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            tip,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.88),
            ),
          ),
        ],
      ),
    );
  }

  /// Horizontal "All / each pet" chip strip that filters the task lists.
  Widget _petFilterChips(List<Pet> pets, AppLanguage language) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _petChip(
            label: L10n.text(language, 'All', 'すべて', '全部', '전체'),
            emoji: '🏠',
            selected: _selectedPetId == null,
            onTap: () => setState(() => _selectedPetId = null),
          ),
          for (final pet in pets)
            _petChip(
              label: pet.name,
              emoji: petTypeEmoji(pet.type),
              selected: _selectedPetId == pet.id,
              onTap: () => setState(() => _selectedPetId = pet.id),
            ),
        ],
      ),
    );
  }

  Widget _petChip({
    required String label,
    required String emoji,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 9),
      child: Material(
        color: selected ? PawColors.purple : Colors.white.withValues(alpha: 0.92),
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
      BuildContext context, CareStore store, AppLanguage language) {
    final remaining = store.unclaimedTasks.length + store.claimedTasks.length;
    final summary = remaining == 0
        ? L10n.text(language, 'Everything is handled. Time for cuddles.',
            '全部おわり。なでなでの時間。', '一切都处理好了，该抱抱了。',
            '다 끝났어요. 이제 안아줄 시간이에요.')
        : '$remaining ${L10n.text(language, 'care moments left for today.', '件のケアが残っています。', '个护理待完成。', '건의 케어가 남았습니다.')}';

    return _PetHeroCarousel(
      pets: store.household?.pets ?? const <Pet>[],
      summary: summary,
      householdName: store.household?.name ?? '',
      language: language,
      onTapPet: (pet) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PetDetailView(pet: pet)),
      ),
    );
  }

  /// Vaccinations and dewormings coming due. Small and quiet until something
  /// is actually close, then impossible to miss.
  List<Widget> _healthDueBanner(
      BuildContext context, CareStore store, AppLanguage language) {
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
        ? L10n.text(language, 'was due ${-soonest.daysUntilDue} days ago',
            '${-soonest.daysUntilDue}日前が期限', '已过期 ${-soonest.daysUntilDue} 天',
            '${-soonest.daysUntilDue}일 지남')
        : soonest.isDueToday
            ? L10n.text(language, 'is due today', '今日が期限', '今天到期', '오늘 마감')
            : L10n.text(
                language,
                'is due in ${soonest.daysUntilDue} days',
                'あと${soonest.daysUntilDue}日',
                '还有 ${soonest.daysUntilDue} 天到期',
                '${soonest.daysUntilDue}일 남음');

    return [
      const SizedBox(height: 20),
      InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PetDetailView(pet: pet)),
        ),
        child: PetCard(
          padding: 14,
          child: Row(
            children: [
              CareIcon(icon: Icons.vaccines, color: color, size: 40),
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
          const CareIcon(icon: Icons.check, color: PawColors.green, size: 56),
          const SizedBox(height: 10),
          Text(
            L10n.text(language, 'Everything is handled', '全部おわり',
                '一切都处理好了', '다 끝났어요'),
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: PawColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            L10n.text(language, 'Add another task when your pet needs care.',
                'ケアが必要になったらタスクを追加しましょう。',
                '宠物需要照顾时，再添加一个任务。',
                '반려동물에게 케어가 필요할 때 할 일을 추가하세요.'),
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
            child: Text(L10n.text(
                language, 'Add a task', 'タスクを追加', '添加任务', '할 일 추가')),
          ),
        ],
      ),
    );
  }
}

class _PetHeroCarousel extends StatefulWidget {
  const _PetHeroCarousel({
    required this.pets,
    required this.summary,
    required this.householdName,
    required this.language,
    required this.onTapPet,
  });

  final List<Pet> pets;
  final String summary;
  final String householdName;
  final AppLanguage language;
  final void Function(Pet pet) onTapPet;

  @override
  State<_PetHeroCarousel> createState() => _PetHeroCarouselState();
}

class _PetHeroCarouselState extends State<_PetHeroCarousel> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pets = widget.pets;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            PawColors.lavender,
            PawColors.peach.withValues(alpha: 0.72),
          ],
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
              itemCount: pets.isEmpty ? 1 : pets.length,
              onPageChanged: (i) => setState(() => _index = i),
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
                  const Icon(Icons.auto_awesome,
                      size: 14, color: PawColors.purple),
                  const SizedBox(width: 5),
                  Text(
                    L10n.text(language, "TODAY'S PETTOGETHER", '今日のペットゥギャザー',
                        '今日的 PETTOGETHER', '오늘의 펫투게더'),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: PawColors.purple,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                pet?.name ??
                    L10n.text(language, 'Your pet', 'あなたのペット', '你的宠物',
                        '반려동물'),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: PawColors.ink,
                ),
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
                      fontSize: 12, color: PawColors.purpleDark),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                widget.summary,
                style: const TextStyle(fontSize: 13, color: PawColors.muted),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.home,
                      size: 15, color: PawColors.purpleDark),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      widget.householdName.isEmpty
                          ? L10n.text(language, 'Your household', 'あなたの家族',
                              '你的家庭', '가족')
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
          onTap: pet == null ? null : () => widget.onTapPet(pet),
          borderRadius: BorderRadius.circular(21),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(21),
            child: SizedBox(
              width: 138,
              height: 156,
              child: PetPhotoView(photoURL: pet?.photoURL),
            ),
          ),
        ),
      ],
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
