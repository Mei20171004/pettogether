import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import '../models/care_catalog.dart';
import '../models/models.dart';
import '../store/care_store.dart';
import '../theme/app_theme.dart';
import 'widgets/common.dart';

class AddTaskView extends StatefulWidget {
  const AddTaskView({super.key, this.initialDate});

  final DateTime? initialDate;

  @override
  State<AddTaskView> createState() => _AddTaskViewState();
}

class _AddTaskViewState extends State<AddTaskView> {
  late DateTime _dueDate;
  final _title = TextEditingController();
  CareCategory _category = CareCategory.feeding;
  CareTaskKind _kind = CareTaskKind.oneOff;
  CarePriority _priority = CarePriority.normal;
  CareRoutineFrequency _frequency = CareRoutineFrequency.daily;
  int _interval = 1;
  String? _petID;
  final List<int> _weekdays = [1, 2, 3, 4, 5, 6, 7];

  @override
  void initState() {
    super.initState();
    final base = widget.initialDate ?? DateTime.now();
    _dueDate = DateTime(base.year, base.month, base.day,
        DateTime.now().hour, DateTime.now().minute);
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  bool get _canSave => _title.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CareStore>();
    final language = context.watch<AppLanguageStore>().language;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
            L10n.text(language, 'Add Task', 'ケアを追加', '添加护理', '케어 추가')),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: (!_canSave || store.isSavingTask)
                ? null
                : () => _save(store),
            child: store.isSavingTask
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    L10n.text(language, 'Save', '保存', '保存', '저장'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
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
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Column(
                      children: [
                        const CareIcon(
                            icon: Icons.add, color: PawColors.purple, size: 58),
                        const SizedBox(height: 8),
                        Text(
                          L10n.text(language, 'A new care moment', '新しいケア',
                              '新的护理时刻', '새로운 케어'),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: PawColors.ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          switch (language) {
                            AppLanguage.japanese =>
                              '${store.household?.petName ?? 'ペット'}に必要なことを追加しましょう。',
                            AppLanguage.chinese =>
                              '添加一个明确的任务，让大家都知道${store.household?.petName ?? '你的宠物'}需要什么。',
                            AppLanguage.korean =>
                              '${store.household?.petName ?? '반려동물'}에게 필요한 일을 모두가 알 수 있도록 명확한 할 일을 추가하세요.',
                            AppLanguage.english =>
                              'Add one clear task so everyone knows what ${store.household?.petName ?? 'your pet'} needs.',
                          },
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 13, color: PawColors.muted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    PetCard(
                      padding: 14,
                      child: Row(
                        children: [
                          const CareIcon(
                              icon: Icons.calendar_today,
                              color: PawColors.purple,
                              size: 46),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  L10n.text(language, 'Scheduled for', '予定日',
                                      '安排于', '예정일'),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: PawColors.muted,
                                  ),
                                ),
                                Text(
                                  _scheduledDateText(language),
                                  style: const TextStyle(
                                    fontSize: 17,
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
                    const SizedBox(height: 20),
                    if (store.household != null &&
                        store.household!.pets.length > 1)
                      PetCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _fieldLabel(
                              L10n.text(
                                  language, 'Pet', 'ペット', '宠物', '반려동물'),
                              Icons.pets,
                            ),
                            const SizedBox(height: 8),
                            _petSelector(language, store),
                          ],
                        ),
                      ),
                    const SizedBox(height: 20),
                    PetCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _fieldLabel(
                            L10n.text(language, 'Frequency', '頻度', '频率', '빈도'),
                            Icons.repeat,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _typeButton(
                                  CareTaskKind.oneOff,
                                  L10n.text(language, 'One-time', '一回のみ',
                                      '一次性', '일회성'),
                                  L10n.text(language, 'A dated need', '指定日のケア',
                                      '有日期的需求', '날짜가 정해진 케어'),
                                  Icons.add_circle_outline,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _typeButton(
                                  CareTaskKind.routine,
                                  L10n.text(language, 'Routine', '繰り返し',
                                      '例行', '루틴'),
                                  L10n.text(language, 'Choose days', '曜日を指定',
                                      '选择星期', '요일 지정'),
                                  Icons.repeat,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _kind == CareTaskKind.routine
                                ? L10n.text(
                                    language,
                                    'Choose the days and time this repeats.',
                                    '繰り返す曜日と時間を選びます。',
                                    '选择重复的星期几和时间。',
                                    '반복할 요일과 시간을 선택하세요.')
                                : L10n.text(
                                    language,
                                    'This will appear only on the date you choose.',
                                    '選んだ日に一度だけ表示されます。',
                                    '这只会出现在你选择的日期。',
                                    '선택한 날짜에만 표시됩니다.'),
                            style: const TextStyle(
                                fontSize: 12, color: PawColors.muted),
                          ),
                          if (_kind == CareTaskKind.routine) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              decoration: BoxDecoration(
                                color:
                                    PawColors.lavender.withValues(alpha: 0.52),
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(
                                    color: PawColors.purple
                                        .withValues(alpha: 0.08)),
                              ),
                              child: DropdownButton<CareRoutineFrequency>(
                                value: _frequency,
                                isExpanded: true,
                                underline: const SizedBox.shrink(),
                                items: [
                                  for (final f in CareRoutineFrequency.values)
                                    DropdownMenuItem(
                                      value: f,
                                      child: Text(_frequencyName(language, f)),
                                    ),
                                ],
                                onChanged: (value) =>
                                    setState(() => _frequency = value!),
                              ),
                            ),
                            if (_needsInterval) ...[
                              const SizedBox(height: 12),
                              _intervalStepper(language),
                            ],
                            if (_needsWeekdays) ...[
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  for (final day in _weekdayOptions(language))
                                    _weekdayChip(
                                      day.$1,
                                      day.$2,
                                      single: _frequency ==
                                          CareRoutineFrequency.nthWeekday,
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    PetCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _fieldLabel(
                            L10n.text(language, 'Care category', 'カテゴリー',
                                '护理分类', '케어 카테고리'),
                            Icons.grid_view,
                          ),
                          const SizedBox(height: 13),
                          GridView.count(
                            crossAxisCount: 3,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 1.25,
                            children: _categoryGrid(language, store),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    PetCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _fieldLabel(
                            L10n.text(language, 'What needs to be done?',
                                '具体的な名前', '需要做什么？', '무엇을 해야 하나요?'),
                            Icons.checklist,
                          ),
                          const SizedBox(height: 9),
                          TextField(
                            controller: _title,
                            onChanged: (_) => setState(() {}),
                            decoration: petFieldDecoration(
                              hintText: L10n.text(language,
                                  'For example: Morning meal',
                                  '例：朝ごはん', '例如：早餐', '예: 아침 식사'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    PetCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _fieldLabel(
                            _kind == CareTaskKind.routine
                                ? L10n.text(language, 'Start date and time',
                                    '開始日と時間', '开始日期和时间', '시작 날짜와 시간')
                                : L10n.text(language, 'Date and time', '日時',
                                    '日期和时间', '날짜와 시간'),
                            Icons.schedule,
                          ),
                          const SizedBox(height: 12),
                          _pickerTile(
                            icon: Icons.calendar_today,
                            label: _kind == CareTaskKind.routine
                                ? L10n.text(
                                    language, 'Starts', '開始', '开始', '시작')
                                : L10n.text(
                                    language, 'Date', '日付', '日期', '날짜'),
                            value: DateFormat.yMMMd(language.rawValue)
                                .format(_dueDate),
                            onTap: _pickDate,
                          ),
                          const SizedBox(height: 10),
                          _pickerTile(
                            icon: Icons.schedule,
                            label: L10n.text(
                                language, 'Time', '時間', '时间', '시간'),
                            value: DateFormat.jm(language.rawValue)
                                .format(_dueDate),
                            onTap: _pickTime,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    PetCard(
                      padding: 15,
                      child: Row(
                        children: [
                          const CareIcon(
                              icon: Icons.error,
                              color: PawColors.rose,
                              size: 48),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  L10n.text(language, 'Urgent care', '緊急ケア',
                                      '紧急护理', '긴급 케어'),
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    color: PawColors.ink,
                                  ),
                                ),
                                Text(
                                  L10n.text(
                                    language,
                                    'Make this stand out for both caregivers.',
                                    '家族全員に目立つようにします。',
                                    '让这条对所有家人都更醒目。',
                                    '모든 가족이 알아보기 쉽게 표시합니다.',
                                  ),
                                  style: const TextStyle(
                                      fontSize: 12, color: PawColors.muted),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _priority == CarePriority.urgent,
                            activeThumbColor: PawColors.rose,
                            onChanged: (value) => setState(() => _priority =
                                value ? CarePriority.urgent : CarePriority.normal),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      style: pawPrimaryButtonStyle(),
                      onPressed: (!_canSave || store.isSavingTask)
                          ? null
                          : () => _save(store),
                      child: store.isSavingTask
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text(L10n.text(
                              language, 'Save', '保存', '保存', '저장')),
                    ),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _dueDate = DateTime(picked.year, picked.month, picked.day,
            _dueDate.hour, _dueDate.minute);
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _dueDate.hour, minute: _dueDate.minute),
    );
    if (picked != null) {
      setState(() {
        _dueDate = DateTime(_dueDate.year, _dueDate.month, _dueDate.day,
            picked.hour, picked.minute);
      });
    }
  }

  Future<void> _save(CareStore store) async {
    final saved = await store.addTask(
      title: _title.text.trim(),
      category: _category,
      kind: _kind,
      priority: _priority,
      date: _dueDate,
      frequency: _kind == CareTaskKind.routine
          ? _frequency
          : CareRoutineFrequency.daily,
      weekdays: _weekdays,
      interval: _interval,
      petID: _petID,
    );
    if (saved && mounted) Navigator.of(context).pop();
  }

  bool get _needsWeekdays =>
      _frequency == CareRoutineFrequency.selectedDays ||
      _frequency == CareRoutineFrequency.nthWeekday;

  bool get _needsInterval =>
      _frequency == CareRoutineFrequency.intervalDays ||
      _frequency == CareRoutineFrequency.intervalWeeks ||
      _frequency == CareRoutineFrequency.intervalMonths ||
      _frequency == CareRoutineFrequency.intervalYears ||
      _frequency == CareRoutineFrequency.nthWeekday;

  String _frequencyName(AppLanguage language, CareRoutineFrequency f) {
    return switch (f) {
      CareRoutineFrequency.daily =>
        L10n.text(language, 'Every day', '毎日', '每天', '매일'),
      CareRoutineFrequency.selectedDays =>
        L10n.text(language, 'On selected days', '指定した曜日', '指定星期', '지정 요일'),
      CareRoutineFrequency.intervalDays =>
        L10n.text(language, 'Every N days', 'N日ごと', '每 N 天', 'N일마다'),
      CareRoutineFrequency.intervalWeeks =>
        L10n.text(language, 'Every N weeks', 'N週間ごと', '每 N 周', 'N주마다'),
      CareRoutineFrequency.intervalMonths =>
        L10n.text(language, 'Every N months', 'Nか月ごと', '每 N 个月', 'N개월마다'),
      CareRoutineFrequency.nthWeekday => L10n.text(
          language, 'Nth weekday of month', '毎月第N週の曜日', '每月第 N 个星期几',
          '매월 N번째 요일'),
      CareRoutineFrequency.intervalYears =>
        L10n.text(language, 'Every N years', 'N年ごと', '每 N 年', 'N년마다'),
    };
  }

  Widget _petSelector(AppLanguage language, CareStore store) {
    final pets = store.household?.pets ?? const <Pet>[];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: Text(L10n.text(language, 'All pets', 'すべてのペット', '所有宠物',
              '모든 반려동물')),
          selected: _petID == null,
          onSelected: (_) => setState(() => _petID = null),
        ),
        for (final pet in pets)
          ChoiceChip(
            avatar: Text(petTypeEmoji(pet.type)),
            label: Text(pet.name),
            selected: _petID == pet.id,
            onSelected: (_) => setState(() => _petID = pet.id),
          ),
      ],
    );
  }

  Widget _intervalStepper(AppLanguage language) {
    final isWeek = _frequency == CareRoutineFrequency.nthWeekday;
    final max = isWeek ? 5 : 999;
    final label = isWeek
        ? L10n.text(language, 'Week of month', '月の第何週', '第几周', '몇 번째 주')
        : L10n.text(language, 'Every N', '間隔 N', '每 N', '간격 N');
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: PawColors.purpleDark),
          ),
        ),
        _stepperButton(Icons.remove, () => _adjustInterval(-1, max)),
        Container(
          width: 48,
          alignment: Alignment.center,
          child: Text(
            '$_interval',
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: PawColors.ink),
          ),
        ),
        _stepperButton(Icons.add, () => _adjustInterval(1, max)),
      ],
    );
  }

  Widget _stepperButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: PawColors.lavender,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: PawColors.purple),
      ),
    );
  }

  void _adjustInterval(int delta, int max) {
    setState(() {
      _interval = (_interval + delta).clamp(1, max);
    });
  }

  Widget _typeButton(
      CareTaskKind kind, String title, String detail, IconData icon) {
    final selected = _kind == kind;
    return InkWell(
      onTap: () => setState(() => _kind = kind),
      borderRadius: BorderRadius.circular(17),
      child: Container(
        height: 92,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? PawColors.lavender : PawColors.cream,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: selected ? PawColors.purple : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 20,
                color: selected ? PawColors.purple : PawColors.ink),
            const SizedBox(height: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: selected ? PawColors.purple : PawColors.ink,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              detail,
              style: TextStyle(
                fontSize: 11,
                color: selected ? PawColors.purpleDark : PawColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _weekdayChip(int value, String label, {bool single = false}) {
    final selected = _weekdays.contains(value);
    return InkWell(
      onTap: () => setState(() {
        if (single) {
          _weekdays
            ..clear()
            ..add(value);
        } else if (selected && _weekdays.length > 1) {
          _weekdays.remove(value);
        } else if (!selected) {
          _weekdays.add(value);
        }
      }),
      customBorder: const CircleBorder(),
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? PawColors.purple : PawColors.lavender,
          shape: BoxShape.circle,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: selected ? Colors.white : PawColors.purple,
          ),
        ),
      ),
    );
  }

  List<Widget> _categoryGrid(AppLanguage language, CareStore store) {
    final petType = store.household?.petType ?? PetType.cat;
    return [
      for (final category in categoriesForPetType(petType))
        _categoryButton(category, language),
      for (final category in store.customCategories)
        _categoryButton(category, language),
      _newCategoryButton(language),
    ];
  }

  Widget _newCategoryButton(AppLanguage language) {
    return InkWell(
      onTap: () => _showNewCategoryDialog(language),
      borderRadius: BorderRadius.circular(17),
      child: Container(
        decoration: BoxDecoration(
          color: PawColors.cream,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: PawColors.purple.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add, color: PawColors.purple, size: 30),
            const SizedBox(height: 4),
            Text(
              L10n.text(language, 'Custom', 'カスタム', '自定义', '사용자 지정'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: PawColors.purple,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showNewCategoryDialog(AppLanguage language) async {
    final store = context.read<CareStore>();
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(L10n.text(language, 'New care module', '新しいケアモジュール',
            '新护理模块', '새 케어 모듈')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: petFieldDecoration(
            hintText: L10n.text(
                language, 'Module name', 'モジュール名', '模块名称', '모듈 이름'),
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
                L10n.text(language, 'Cancel', 'キャンセル', '取消', '취소')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(L10n.text(language, 'Add', '追加', '添加', '추가')),
          ),
        ],
      ),
    );
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    await store.addCustomCategory(trimmed);
  }

  Widget _categoryButton(CareCategory category, AppLanguage language) {
    final selected = _category == category;
    final color = categoryAccent(category);
    return InkWell(
      onTap: () => setState(() => _category = category),
      borderRadius: BorderRadius.circular(17),
      child: Container(
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.13) : PawColors.cream,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: selected ? color : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CareIcon(icon: categoryIcon(category), color: color, size: 42),
            const SizedBox(height: 6),
            Text(
              L10n.categoryTitle(language, category),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: PawColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pickerTile({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: PawColors.lavender.withValues(alpha: 0.52),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: PawColors.purple),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500, color: PawColors.ink),
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: PawColors.ink),
            ),
          ],
        ),
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

  String _scheduledDateText(AppLanguage language) {
    return switch (language) {
      AppLanguage.japanese => DateFormat('M月d日 (E)', 'ja').format(_dueDate),
      AppLanguage.chinese => DateFormat('M月d日 (E)', 'zh').format(_dueDate),
      AppLanguage.korean => DateFormat('M월 d일 (E)', 'ko').format(_dueDate),
      AppLanguage.english => DateFormat('EEEE, MMM d', 'en').format(_dueDate),
    };
  }

  List<(int, String)> _weekdayOptions(AppLanguage language) {
    return switch (language) {
      AppLanguage.japanese => const [
          (1, '日'),
          (2, '月'),
          (3, '火'),
          (4, '水'),
          (5, '木'),
          (6, '金'),
          (7, '土'),
        ],
      AppLanguage.chinese => const [
          (1, '日'),
          (2, '一'),
          (3, '二'),
          (4, '三'),
          (5, '四'),
          (6, '五'),
          (7, '六'),
        ],
      AppLanguage.korean => const [
          (1, '일'),
          (2, '월'),
          (3, '화'),
          (4, '수'),
          (5, '목'),
          (6, '금'),
          (7, '토'),
        ],
      AppLanguage.english => const [
          (1, 'S'),
          (2, 'M'),
          (3, 'T'),
          (4, 'W'),
          (5, 'T'),
          (6, 'F'),
          (7, 'S'),
        ],
    };
  }
}
