import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../l10n/l10n.dart';
import '../../models/health.dart';
import '../../theme/app_theme.dart';
import '../../utils/care_calendar.dart';
import '../widgets/common.dart';

/// Everything a medication course needs beyond an ordinary task: what the
/// medicine is, when each dose is given, and how long the course runs.
///
/// Shared by the add-task screen (creating a course) and the course editor
/// (changing one), so the two can never ask for different things.
class MedicationDetails {
  const MedicationDetails({
    required this.name,
    required this.form,
    this.purpose,
    this.sideEffects,
    this.remainingDoses,
    required this.times,
    required this.startDate,
    this.endDate,
  });

  final String name;
  final MedicationForm form;
  final String? purpose;
  final String? sideEffects;
  final int? remainingDoses;
  final List<MedicationDoseTime> times;
  final DateTime startDate;
  final DateTime? endDate;

  bool get isValid =>
      name.trim().isNotEmpty &&
      times.isNotEmpty &&
      times.length <= MedicationPlan.maxDoseTimes &&
      times.every((t) => t.isValid) &&
      (endDate == null || !startOfDay(endDate!).isBefore(startOfDay(startDate)));
}

/// The editable state behind [MedicationDetailsForm].
///
/// Held by the parent screen so it survives rebuilds and the parent can read
/// the result on save; it owns the text controllers and must be disposed.
class MedicationDetailsController extends ChangeNotifier {
  MedicationDetailsController({
    String name = '',
    this.form = MedicationForm.oral,
    String? purpose,
    String? sideEffects,
    int? remainingDoses,
    List<MedicationDoseTime>? times,
    DateTime? startDate,
    this.endDate,
    this.ongoing = false,
  }) : startDate = startOfDay(startDate ?? DateTime.now()) {
    nameController = TextEditingController(text: name);
    purposeController = TextEditingController(text: purpose ?? '');
    sideEffectsController = TextEditingController(text: sideEffects ?? '');
    remainingController =
        TextEditingController(text: remainingDoses?.toString() ?? '');
    _times = [...?times];
    if (_times.isEmpty) {
      _times = [_defaultTime()];
    }
    _doseControllers = _times
        .map((t) => TextEditingController(text: t.doseText))
        .toList();
    _instructionControllers = _times
        .map((t) => TextEditingController(text: t.instructions ?? ''))
        .toList();
    // Most courses are finite and a week is the common case, so an end date is
    // pre-filled rather than left for the user to discover.
    if (!ongoing && endDate == null) {
      endDate = this.startDate.add(const Duration(days: 6));
    }
  }

  late final TextEditingController nameController;
  late final TextEditingController purposeController;
  late final TextEditingController sideEffectsController;
  late final TextEditingController remainingController;

  MedicationForm form;
  DateTime startDate;
  DateTime? endDate;
  bool ongoing;

  List<MedicationDoseTime> _times = [];
  List<TextEditingController> _doseControllers = [];
  List<TextEditingController> _instructionControllers = [];

  List<MedicationDoseTime> get times => List.unmodifiable(_times);
  int get timeCount => _times.length;

  TextEditingController doseControllerAt(int index) => _doseControllers[index];
  TextEditingController instructionControllerAt(int index) =>
      _instructionControllers[index];
  MedicationDoseTime timeAt(int index) => _times[index];

  static MedicationDoseTime _defaultTime() =>
      const MedicationDoseTime(hour: 8, minute: 0, doseText: '');

  void setForm(MedicationForm value) {
    form = value;
    notifyListeners();
  }

  void setTimeOfDay(int index, int hour, int minute) {
    _times[index] = _times[index].copyWith(hour: hour, minute: minute);
    notifyListeners();
  }

  /// A second dose usually lands in the evening; later ones step forward from
  /// the last, and carry its dose text so the common case needs no retyping.
  void addTime() {
    if (_times.length >= MedicationPlan.maxDoseTimes) return;
    final last = _times.last;
    final next = _times.length == 1
        ? MedicationDoseTime(
            hour: 20, minute: 0, doseText: _doseControllers.last.text)
        : MedicationDoseTime(
            hour: (last.hour + 4) % 24,
            minute: last.minute,
            doseText: _doseControllers.last.text);
    _times.add(next);
    _doseControllers.add(TextEditingController(text: next.doseText));
    _instructionControllers.add(TextEditingController());
    notifyListeners();
  }

  void removeTime(int index) {
    if (_times.length <= 1) return;
    _times.removeAt(index);
    _doseControllers.removeAt(index).dispose();
    _instructionControllers.removeAt(index).dispose();
    notifyListeners();
  }

  void setStartDate(DateTime value) {
    startDate = startOfDay(value);
    final end = endDate;
    if (end != null && end.isBefore(startDate)) endDate = startDate;
    notifyListeners();
  }

  void setEndDate(DateTime value) {
    endDate = startOfDay(value);
    notifyListeners();
  }

  void setOngoing(bool value) {
    ongoing = value;
    if (!value && endDate == null) {
      endDate = startDate.add(const Duration(days: 6));
    }
    notifyListeners();
  }

  /// Course length and total doses, or null when the course is open-ended.
  /// Powers the "7 days · 14 doses" readout.
  ({int days, int doses})? summarise(List<int> weekdays) {
    if (ongoing || endDate == null) return null;
    final start = startOfDay(startDate);
    final last = startOfDay(endDate!);
    if (last.isBefore(start)) return null;
    var runningDays = 0;
    for (var day = start;
        !day.isAfter(last);
        day = day.add(const Duration(days: 1))) {
      if (weekdays.contains(swiftWeekday(day))) runningDays += 1;
    }
    return (
      days: last.difference(start).inDays + 1,
      doses: runningDays * _times.length,
    );
  }

  MedicationDetails read() {
    String? trimmed(TextEditingController c) {
      final value = c.text.trim();
      return value.isEmpty ? null : value;
    }

    return MedicationDetails(
      name: nameController.text.trim(),
      form: form,
      purpose: trimmed(purposeController),
      sideEffects: trimmed(sideEffectsController),
      remainingDoses: int.tryParse(remainingController.text.trim()),
      times: [
        for (var i = 0; i < _times.length; i++)
          _times[i].copyWith(
            doseText: _doseControllers[i].text.trim(),
            instructions: _instructionControllers[i].text.trim().isEmpty
                ? null
                : _instructionControllers[i].text.trim(),
            clearInstructions: _instructionControllers[i].text.trim().isEmpty,
          ),
      ],
      startDate: startDate,
      endDate: ongoing ? null : endDate,
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    purposeController.dispose();
    sideEffectsController.dispose();
    remainingController.dispose();
    for (final c in _doseControllers) {
      c.dispose();
    }
    for (final c in _instructionControllers) {
      c.dispose();
    }
    super.dispose();
  }
}

/// The medicine card, dose-time list and course card, rendered as loose
/// children so the host screen keeps control of spacing and ordering.
class MedicationDetailsForm extends StatelessWidget {
  const MedicationDetailsForm({
    super.key,
    required this.controller,
    required this.weekdays,
    required this.language,
    this.editingNotice = false,
  });

  final MedicationDetailsController controller;
  final List<int> weekdays;
  final AppLanguage language;

  /// Shown when changing an existing course, so nobody fears their recorded
  /// history is about to be rewritten.
  final bool editingNotice;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (editingNotice) ...[
            _notice(),
            const SizedBox(height: 20),
          ],
          _medicineCard(context),
          const SizedBox(height: 20),
          _timesCard(context),
          const SizedBox(height: 20),
          _courseCard(context),
        ],
      ),
    );
  }

  Widget _notice() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PawColors.lavender.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: PawColors.purpleDark),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              L10n.text(
                language,
                'Changes apply from today onwards. Doses already given or skipped keep what actually happened.',
                '変更は今日以降に適用されます。記録済みの投与はそのまま残ります。',
                '修改只影响今天之后的用药，已记录的历史不会改变。',
                '변경은 오늘 이후부터 적용됩니다. 이미 기록된 투여는 그대로 남습니다.',
              ),
              style: const TextStyle(
                  fontSize: 12, color: PawColors.purpleDark, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _medicineCard(BuildContext context) {
    return PetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          fieldLabel(
              L10n.text(language, 'Medicine', '薬', '药物', '약'), Icons.medication),
          const SizedBox(height: 10),
          TextField(
            controller: controller.nameController,
            maxLength: MedicationPlan.maxNameLength,
            decoration: petFieldDecoration(
              hintText: L10n.text(
                  language, 'Name on the box', '薬の名前', '药盒上的名称', '약 이름'),
            ).copyWith(counterText: ''),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final form in MedicationForm.values)
                ChoiceChip(
                  selected: controller.form == form,
                  onSelected: (_) => controller.setForm(form),
                  avatar: Icon(medicationFormIcon(form), size: 16),
                  label: Text(L10n.medicationFormTitle(language, form)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          fieldLabel(
              L10n.text(language, 'What is it for', '目的', '用来治什么', '복용 목적'),
              Icons.help_outline),
          const SizedBox(height: 8),
          TextField(
            controller: controller.purposeController,
            maxLines: 2,
            maxLength: MedicationPlan.maxPurposeLength,
            // Three months later nobody remembers why this box is in the
            // cupboard, and the next caregiver never knew.
            decoration: petFieldDecoration(
              hintText: L10n.text(
                language,
                'e.g. gut infection — 7-day course from the vet',
                '例：胃腸炎のため7日間',
                '例：肠胃炎，医生开的 7 天疗程',
                '예: 장염 — 7일 처방',
              ),
            ).copyWith(counterText: ''),
          ),
        ],
      ),
    );
  }

  Widget _timesCard(BuildContext context) {
    return PetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          fieldLabel(
              L10n.text(language, 'Dose times', '服用時間', '服药时间', '복용 시간'),
              Icons.access_time),
          const SizedBox(height: 10),
          for (var index = 0; index < controller.timeCount; index++)
            _timeRow(context, index),
          if (controller.timeCount < MedicationPlan.maxDoseTimes)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: controller.addTime,
                icon: const Icon(Icons.add, size: 18),
                label: Text(L10n.text(
                    language, 'Add a dose time', '時間を追加', '添加时间', '시간 추가')),
              ),
            ),
        ],
      ),
    );
  }

  Widget _timeRow(BuildContext context, int index) {
    final time = controller.timeAt(index);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: PawColors.lavender.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          children: [
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _pickTime(context, index),
                  icon: const Icon(Icons.access_time, size: 16),
                  label: Text(time.label),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: controller.doseControllerAt(index),
                    maxLength: MedicationDoseTime.maxDoseTextLength,
                    decoration: petFieldDecoration(
                      hintText:
                          L10n.text(language, 'Dose', '量', '剂量', '용량'),
                    ).copyWith(counterText: ''),
                  ),
                ),
                if (controller.timeCount > 1)
                  IconButton(
                    onPressed: () => controller.removeTime(index),
                    icon: const Icon(Icons.close,
                        size: 18, color: PawColors.muted),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller.instructionControllerAt(index),
              maxLength: MedicationDoseTime.maxInstructionsLength,
              decoration: petFieldDecoration(
                hintText: L10n.text(language, 'How to give it (optional)',
                    'あげ方（任意）', '怎么喂（可选）', '먹이는 방법 (선택)'),
              ).copyWith(counterText: ''),
            ),
          ],
        ),
      ),
    );
  }

  Widget _courseCard(BuildContext context) {
    final summary = controller.summarise(weekdays);
    return PetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          fieldLabel(
              L10n.text(language, 'Course length', '期間', '疗程', '기간'),
              Icons.event_repeat),
          const SizedBox(height: 10),
          _dateTile(
            context,
            label: L10n.text(language, 'Starts', '開始', '开始', '시작'),
            value: controller.startDate,
            onTap: () => _pickDate(context, isStart: true),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        L10n.text(language, 'Ongoing medication', '継続して服用',
                            '长期用药', '장기 복용'),
                        style: const TextStyle(
                            fontSize: 14, color: PawColors.ink),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        L10n.text(language, 'No end date', '終了日なし',
                            '没有结束日期', '종료일 없음'),
                        style: const TextStyle(
                            fontSize: 12, color: PawColors.muted),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: controller.ongoing,
                  onChanged: controller.setOngoing,
                  activeThumbColor: PawColors.purple,
                ),
              ],
            ),
          ),
          if (!controller.ongoing)
            _dateTile(
              context,
              label: L10n.text(language, 'Ends', '終了', '结束', '종료'),
              value: controller.endDate ?? controller.startDate,
              onTap: () => _pickDate(context, isStart: false),
            ),
          if (summary != null) ...[
            const SizedBox(height: 10),
            // You can see the whole course before committing to it, instead of
            // discovering its length a dose at a time.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: PawColors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.checklist, size: 16, color: PawColors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${summary.days} ${L10n.text(language, 'days', '日間', '天', '일')} · '
                      '${summary.doses} ${L10n.text(language, 'doses', '回', '次', '회')}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: PawColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          fieldLabel(
              L10n.text(language, 'Good to know', '補足', '补充信息', '참고 사항'),
              Icons.notes),
          const SizedBox(height: 10),
          TextField(
            controller: controller.remainingController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: petFieldDecoration(
              hintText: L10n.text(language, 'Doses left in the box (optional)',
                  '残りの回数（任意）', '盒里还剩几次（可选）', '남은 횟수 (선택)'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller.sideEffectsController,
            maxLines: 2,
            maxLength: MedicationPlan.maxSideEffectsLength,
            // So a caregiver who never spoke to the vet still knows what
            // "not normal" looks like.
            decoration: petFieldDecoration(
              hintText: L10n.text(
                language,
                'Side effects to watch for (optional)',
                '注意する副作用（任意）',
                '需要留意的副作用（可选）',
                '주의할 부작용 (선택)',
              ),
            ).copyWith(counterText: ''),
          ),
        ],
      ),
    );
  }

  Widget _dateTile(
    BuildContext context, {
    required String label,
    required DateTime value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Text(label,
                style: const TextStyle(fontSize: 14, color: PawColors.ink)),
            const Spacer(),
            Text(
              DateFormat.yMMMd(language.rawValue).format(value),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: PawColors.purple,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: PawColors.muted),
          ],
        ),
      ),
    );
  }

  Future<void> _pickTime(BuildContext context, int index) async {
    final time = controller.timeAt(index);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: time.hour, minute: time.minute),
    );
    if (picked == null) return;
    controller.setTimeOfDay(index, picked.hour, picked.minute);
  }

  Future<void> _pickDate(BuildContext context, {required bool isStart}) async {
    final initial = isStart
        ? controller.startDate
        : (controller.endDate ?? controller.startDate);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: isStart
          ? DateTime.now().subtract(const Duration(days: 365))
          : controller.startDate,
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked == null) return;
    if (isStart) {
      controller.setStartDate(picked);
    } else {
      controller.setEndDate(picked);
    }
  }
}
