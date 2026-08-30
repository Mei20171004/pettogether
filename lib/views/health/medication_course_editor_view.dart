import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/health.dart';
import '../../store/care_store.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import 'medication_details_form.dart';

/// Edits an existing medication course.
///
/// Creating one goes through the ordinary "+" flow in `AddTaskView`; this
/// screen exists only for changes, and reuses the very same form so the two can
/// never ask for different things.
class MedicationCourseEditorView extends StatefulWidget {
  const MedicationCourseEditorView({super.key, required this.planId});

  final String planId;

  @override
  State<MedicationCourseEditorView> createState() =>
      _MedicationCourseEditorViewState();
}

class _MedicationCourseEditorViewState
    extends State<MedicationCourseEditorView> {
  MedicationDetailsController? _controller;
  late List<int> _weekdays;

  @override
  void initState() {
    super.initState();
    final store = context.read<CareStore>();
    final plan = store.medicationPlans
        .where((p) => p.id == widget.planId)
        .firstOrNull;
    final routines = store.routinesForPlan(widget.planId);
    if (plan == null || routines.isEmpty) {
      _weekdays = const [1, 2, 3, 4, 5, 6, 7];
      return;
    }

    final window = store.courseWindow(widget.planId);
    _weekdays = routines.first.weekdays;
    _controller = MedicationDetailsController(
      name: plan.name,
      form: plan.form,
      purpose: plan.purpose,
      sideEffects: plan.sideEffects,
      remainingDoses: plan.remainingDoses,
      times: [
        for (final routine in routines)
          MedicationDoseTime(
            hour: routine.hour,
            minute: routine.minute,
            doseText: routine.doseText ?? '',
            instructions: routine.doseInstructions,
          ),
      ],
      startDate: window?.start ?? routines.first.startDate,
      endDate: window?.end,
      ongoing: window?.end == null,
    )..addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CareStore>();
    final language = context.watch<AppLanguageStore>().language;
    final controller = _controller;
    final plan = store.medicationPlans
        .where((p) => p.id == widget.planId)
        .firstOrNull;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
            L10n.text(language, 'Edit course', '服薬を編集', '编辑疗程', '복약 편집')),
      ),
      body: Stack(
        children: [
          const PetScreenBackground(),
          SafeArea(
            child: controller == null || plan == null
                ? Center(
                    child: Text(
                      L10n.text(
                          language,
                          'This course is no longer available.',
                          'この服薬は見つかりません。',
                          '这个疗程已不存在。',
                          '이 복약 정보를 찾을 수 없습니다.'),
                      style: const TextStyle(color: PawColors.muted),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                    children: [
                      _weekdayCard(language),
                      const SizedBox(height: 20),
                      MedicationDetailsForm(
                        controller: controller,
                        weekdays: _weekdays,
                        language: language,
                        editingNotice: true,
                      ),
                      const SizedBox(height: 22),
                      ElevatedButton(
                        style: pawPrimaryButtonStyle(),
                        onPressed: store.isSavingHealth ||
                                controller.nameController.text.trim().isEmpty
                            ? null
                            : () => _save(store, plan),
                        child: store.isSavingHealth
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Text(L10n.text(language, 'Save changes', '保存',
                                '保存修改', '변경 저장')),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _weekdayCard(AppLanguage language) {
    return PetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          fieldLabel(
              L10n.text(language, 'Which days', '曜日', '哪几天', '요일'),
              Icons.repeat),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var day = 1; day <= 7; day++) _weekdayChip(day, language),
            ],
          ),
        ],
      ),
    );
  }

  Widget _weekdayChip(int day, AppLanguage language) {
    final selected = _weekdays.contains(day);
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: () => setState(() {
        final next = [..._weekdays];
        if (selected) {
          // Never let a course end up scheduled on no days at all.
          if (next.length > 1) next.remove(day);
        } else {
          next.add(day);
        }
        next.sort();
        _weekdays = next;
      }),
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? PawColors.purple : PawColors.lavender,
          shape: BoxShape.circle,
        ),
        child: Text(
          L10n.weekdayShort(language, day),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: selected ? Colors.white : PawColors.purple,
          ),
        ),
      ),
    );
  }

  Future<void> _save(CareStore store, MedicationPlan plan) async {
    final details = _controller!.read();
    final saved = await store.saveMedicationCourse(
      plan: plan.copyWith(
        name: details.name,
        form: details.form,
        purpose: details.purpose,
        sideEffects: details.sideEffects,
        remainingDoses: details.remainingDoses,
        clearPurpose: details.purpose == null,
        clearSideEffects: details.sideEffects == null,
        clearRemainingDoses: details.remainingDoses == null,
        revision: plan.revision + 1,
      ),
      times: details.times,
      weekdays: _weekdays,
      startDate: details.startDate,
      endDate: details.endDate,
    );
    if (saved != null && mounted) Navigator.of(context).pop();
  }
}
