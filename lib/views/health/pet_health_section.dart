import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/health.dart';
import '../../models/models.dart';
import '../../services/pro_menu_service.dart';
import '../../store/care_store.dart';
import '../../store/pro_access.dart';
import '../../theme/app_theme.dart';
import '../add_task_view.dart';
import '../pro_view.dart';
import '../widgets/common.dart';
import '../widgets/medication_adherence_chart.dart';
import '../widgets/task_card.dart';
import '../widgets/weight_chart.dart';
import 'health_record_detail_view.dart';
import 'health_record_editor_view.dart';
import 'medication_plan_detail_view.dart';
import 'medical_history_view.dart';
import 'pro_menu_web_view.dart';
import 'vet_visit_pack_view.dart';

/// A single pet's health file and its available Pro menu actions.
class PetHealthSection extends StatefulWidget {
  const PetHealthSection({super.key, required this.pet});

  final Pet pet;

  @override
  State<PetHealthSection> createState() => _PetHealthSectionState();
}

class _PetHealthSectionState extends State<PetHealthSection> {
  HealthRecordType? _typeFilter;
  bool _showPastCourses = false;
  Stream<List<ProMenuItem>>? _menuStream;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CareStore>();
    final language = context.watch<AppLanguageStore>().language;
    final hasProAccess = context.watch<ProAccess>().isPro;
    final pet = widget.pet;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 2, 18, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PetSectionTitle(
            title: L10n.text(language, 'Health overview', '健康サマリー',
                '健康概览', '건강 요약'),
          ),
          const SizedBox(height: 12),
          _summaryCard(store, pet, language),
          const SizedBox(height: 20),
          _medicalRecords(store, pet, language),
          const SizedBox(height: 20),
          _healthTools(pet, language, hasProAccess),
          const SizedBox(height: 20),
          PetSectionTitle(
            title: L10n.text(language, 'Health trends', '健康の推移',
                '健康趋势', '건강 추이'),
            detail: L10n.text(language, 'From recorded data', '記録データ',
                '基于已记录数据', '기록 데이터'),
          ),
          const SizedBox(height: 12),
          MedicationAdherenceChart(
            store: store,
            petId: pet.id,
            language: language,
          ),
          const SizedBox(height: 12),
          PetSectionTitle(
            title: L10n.text(language, 'Weight trend', '体重の推移',
                '体重趋势', '체중 추이'),
            detail: pet.weightKg == null
                ? null
                : '${pet.weightKg!.toStringAsFixed(1)} kg',
          ),
          const SizedBox(height: 10),
          WeightChart(pet: pet, months: 6, language: language, height: 190),
          const SizedBox(height: 20),
          _medicationSection(context, store, pet, language),
          const SizedBox(height: 20),
          _historySection(context, store, pet, language),
          if (hasProAccess) ...[
            const SizedBox(height: 22),
            _proMenuButtons(language, store, pet),
          ],
        ],
      ),
    );
  }

  Widget _medicalRecords(CareStore store, Pet pet, AppLanguage language) {
    final count = store.recordsForPet(pet.id)
        .where((record) => !record.type.isCourseGenerated).length;
    return PetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(L10n.text(language, 'Medical records', '医療記録', '医疗记录', '진료 기록'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('medical_record_new'),
            icon: const Icon(Icons.add),
            label: Text(L10n.text(language, 'New record', '記録を追加', '新增记录', '기록 추가')),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              fullscreenDialog: true,
              builder: (_) => HealthRecordEditorView(initialPetId: pet.id),
            )),
          ),
          OutlinedButton.icon(
            key: const ValueKey('medical_record_history'),
            icon: const Icon(Icons.history),
            label: Text('${L10n.text(language, 'View history', '過去の記録を見る', '查看历史记录', '지난 기록 보기')} ($count)'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => MedicalHistoryView(petId: pet.id),
            )),
          ),
        ],
      ),
    );
  }

  Widget _healthTools(Pet pet, AppLanguage language, bool unlocked) {
    final status = L10n.text(
      language,
      unlocked ? 'Unlocked' : 'Health Pro',
      unlocked ? '利用可能' : '健康Pro',
      unlocked ? '已解锁' : '健康 Pro',
      unlocked ? '활성화됨' : '건강 Pro',
    );
    return PetCard(
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(
                  L10n.text(language, 'Health Pro tools', '健康Proの機能',
                      '健康 Pro 工具', '건강 Pro 도구'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                )),
                TextButton(
                  key: const ValueKey('health_pro_details'),
                  onPressed: () => showProPaywall(context),
                  child: Text(L10n.text(language, 'View Health Pro', '健康Proを見る',
                      '查看健康 Pro', '건강 Pro 보기')),
                ),
              ],
            ),
            Text(
              L10n.text(language,
                  'Overview, text records and one active course are free. Pro adds photos, PDF export and concurrent courses.',
                  '健康サマリー・文字の記録・1つの投薬コースは無料。Proで写真添付・PDF書き出し・複数コースを利用できます。',
                  '健康概览、文字记录和一个进行中疗程免费。Pro 增加照片、PDF 导出和多个同时进行的疗程。',
                  '건강 요약, 텍스트 기록, 진행 중인 투약 코스 1개는 무료입니다. Pro는 사진, PDF 내보내기, 여러 코스를 제공합니다.'),
              style: const TextStyle(color: PawColors.muted, fontSize: 12),
            ),
            ListTile(
              key: const ValueKey('health_tool_photos'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.add_photo_alternate_outlined),
              title: Text(
                L10n.text(
                  language,
                  'Medical record photos',
                  '医療記録の写真',
                  '医疗记录照片',
                  '진료 기록 사진',
                ),
              ),
              subtitle: Text(status),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  _openProTool(HealthRecordEditorView(initialPetId: pet.id)),
            ),
            ListTile(
              key: const ValueKey('health_tool_pdf'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: Text(
                L10n.text(
                  language,
                  'Vet visit PDF',
                  '受診PDF',
                  '兽医就诊 PDF',
                  '진료 PDF',
                ),
              ),
              subtitle: Text(
                L10n.text(
                  language,
                  'Free preview · PDF export: $status',
                  'プレビューは無料・PDF書き出し：$status',
                  '免费预览 · PDF 导出：$status',
                  '무료 미리보기 · PDF 내보내기: $status',
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => VetVisitPackView(pet: pet),
                ),
              ),
            ),
            ListTile(
              key: const ValueKey('health_tool_courses'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.medication_outlined),
              title: Text(
                L10n.text(
                  language,
                  'Multiple medication courses',
                  '複数の投薬コース',
                  '多个用药疗程',
                  '여러 투약 코스',
                ),
              ),
              subtitle: Text(status),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openProTool(
                AddTaskView(
                  initialCategory: CareCategory.medication,
                  initialPetId: pet.id,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openProTool(Widget page) async {
    if (!context.read<ProAccess>().isPro) {
      await showProPaywall(context);
      if (!mounted || !context.read<ProAccess>().isPro) return;
    }
    if (!mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Widget _proMenuButtons(AppLanguage language, CareStore store, Pet pet) {
    _menuStream ??= ProMenuService().watchItems();
    return StreamBuilder<List<ProMenuItem>>(
      stream: _menuStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text(
            L10n.text(language, 'Could not load Pro menu',
                'Proメニューを読み込めませんでした', '无法加载 Pro 菜单', 'Pro 메뉴를 불러올 수 없습니다'),
            style: const TextStyle(color: PawColors.muted),
            textAlign: TextAlign.center,
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in snapshot.data!) ...[
              ElevatedButton.icon(
                style: pawPrimaryButtonStyle(),
                onPressed: () {
                  if (!context.read<ProAccess>().isPro) return;
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ProMenuWebView(
                        title: item.title(language),
                        url: item.url,
                        householdId: store.household!.id,
                        petId: pet.id,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.open_in_browser, size: 20),
                label: Text(item.title(language)),
              ),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }

  /// The four things you actually want to know at a glance.
  Widget _summaryCard(CareStore store, Pet pet, AppLanguage language) {
    final doses = store.doseTasksOn(DateTime.now(), petId: pet.id);
    final given =
        doses.where((d) => d.status == CareTaskStatus.completed).length;
    final running = store.plansForPet(pet.id, active: true).length;
    final lastVisit = store.lastVetVisitForPet(pet.id);
    final due = store.upcomingHealthDue(petId: pet.id).firstOrNull;

    return PetCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _metric(
                  icon: Icons.medication,
                  label: L10n.text(
                      language, 'Today’s doses', '今日の薬', '今日用药', '오늘의 약'),
                  value: doses.isEmpty ? '—' : '$given/${doses.length}',
                  color: PawColors.rose,
                ),
              ),
              Expanded(
                child: _metric(
                  icon: Icons.event_repeat,
                  label: L10n.text(
                      language, 'Courses running', '服用中', '进行中疗程', '복용 중'),
                  value: '$running',
                  color: PawColors.purple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _metric(
                  icon: Icons.local_hospital,
                  label: L10n.text(
                      language, 'Last vet visit', '前回の通院', '最近就诊', '최근 진료'),
                  value: lastVisit == null
                      ? '—'
                      : DateFormat.MMMd(language.rawValue)
                          .format(lastVisit.occurredAt),
                  color: PawColors.blue,
                ),
              ),
              Expanded(
                child: _metric(
                  icon: Icons.vaccines,
                  label: L10n.text(
                      language, 'Next due', '次回の予定', '下次到期', '다음 예정'),
                  value: due == null
                      ? '—'
                      : due.isOverdue
                          ? L10n.text(language, 'Overdue', '超過', '已过期', '지남')
                          : due.isDueToday
                              ? L10n.text(language, 'Today', '今日', '今天', '오늘')
                              : L10n.text(
                                  language,
                                  '${due.daysUntilDue}d',
                                  'あと${due.daysUntilDue}日',
                                  '${due.daysUntilDue}天',
                                  '${due.daysUntilDue}일'),
                  // Turns red once the shot is close, so it stops being a
                  // number and starts being a nudge.
                  color: due == null
                      ? PawColors.muted
                      : (due.daysUntilDue <= 7
                          ? PawColors.rose
                          : PawColors.green),
                  onTap: due == null
                      ? null
                      : () => _openRecord(context, due.record.id),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    VoidCallback? onTap,
  }) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: PawColors.muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color == PawColors.muted ? PawColors.ink : color,
          ),
        ),
      ],
    );
    if (onTap == null) return content;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: content,
    );
  }

  Widget _medicationSection(
    BuildContext context,
    CareStore store,
    Pet pet,
    AppLanguage language,
  ) {
    final running = store.plansForPet(pet.id, active: true);
    final past = store.plansForPet(pet.id, active: false);
    final doses = store.doseTasksOn(DateTime.now(), petId: pet.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: PetSectionTitle(
                title: L10n.text(
                    language, 'Medication', '服薬', '用药', '복약'),
              ),
            ),
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => AddTaskView(
                      initialCategory: CareCategory.medication,
                      initialPetId: pet.id),
                ),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: Text(L10n.text(
                  language, 'New course', '追加', '新疗程', '추가')),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (running.isEmpty && past.isEmpty)
          PetCard(
            child: Text(
              L10n.text(
                language,
                'No medication recorded. Add a course when the vet prescribes something.',
                '服薬の記録はありません。処方されたら追加しましょう。',
                '还没有用药记录。医生开药后可以在这里添加疗程。',
                '복약 기록이 없습니다. 처방을 받으면 추가하세요.',
              ),
              style: const TextStyle(fontSize: 13, color: PawColors.muted),
            ),
          )
        else ...[
          for (final plan in running)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _planCard(context, store, plan, language, running: true),
            ),
          if (doses.isNotEmpty) ...[
            const SizedBox(height: 4),
            for (final dose in doses)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TaskCard(task: dose),
              ),
          ],
          if (past.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () =>
                    setState(() => _showPastCourses = !_showPastCourses),
                child: Text(
                  _showPastCourses
                      ? L10n.text(language, 'Hide past courses', '過去の服薬を隠す',
                          '收起已结束的疗程', '지난 복약 숨기기')
                      : '${L10n.text(language, 'Past courses', '過去の服薬', '已结束的疗程', '지난 복약')} (${past.length})',
                ),
              ),
            ),
          if (_showPastCourses)
            for (final plan in past)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _planCard(context, store, plan, language, running: false),
              ),
        ],
      ],
    );
  }

  Widget _planCard(
    BuildContext context,
    CareStore store,
    MedicationPlan plan,
    AppLanguage language, {
    required bool running,
  }) {
    final stats = store.adherence(planId: plan.id, days: 7);
    final dayNumber = store.courseDayNumber(plan.id, DateTime.now());
    final totalDays = store.courseLengthDays(plan.id);
    final routines = store.routinesForPlan(plan.id);

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MedicationPlanDetailView(planId: plan.id),
        ),
      ),
      child: PetCard(
        padding: 15,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CareIcon(
                  icon: medicationFormIcon(plan.form),
                  color: running ? PawColors.rose : PawColors.muted,
                  size: 42,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: PawColors.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${routines.isEmpty ? '' : L10n.weekdaySummary(language, routines.first.weekdays)} · '
                        '${routines.length}× ${L10n.text(language, 'a day', '/日', '每天', '/일')}',
                        style: const TextStyle(
                            fontSize: 12, color: PawColors.muted),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: PawColors.muted),
              ],
            ),
            if (running && dayNumber != null && totalDays != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: dayNumber / totalDays,
                  minHeight: 6,
                  backgroundColor: PawColors.lavender,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(PawColors.rose),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                L10n.text(
                  language,
                  'Day $dayNumber of $totalDays',
                  '$totalDays日中 $dayNumber日目',
                  '第 $dayNumber/$totalDays 天',
                  '$totalDays일 중 $dayNumber일째',
                ),
                style: const TextStyle(fontSize: 11, color: PawColors.muted),
              ),
            ],
            if (!stats.isEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${L10n.text(language, 'Last 7 days', '直近7日', '最近 7 天', '최근 7일')}: '
                '${stats.given}/${stats.planned} · ${stats.percent}%',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: PawColors.ink,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _historySection(
    BuildContext context,
    CareStore store,
    Pet pet,
    AppLanguage language,
  ) {
    final historyRecords = store
        .recordsForPet(pet.id)
        .where((record) => !record.type.isCourseGenerated)
        .toList();
    final records = _typeFilter == null
        ? historyRecords
        : historyRecords.where((record) => record.type == _typeFilter).toList();
    final present = historyRecords
        .map((r) => r.type)
        .toSet()
        .toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: PetSectionTitle(
                title: L10n.text(language, 'Medical history', '病歴', '病历',
                    '진료 기록'),
              ),
            ),
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => HealthRecordEditorView(initialPetId: pet.id),
                ),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: Text(
                  L10n.text(language, 'New record', '追加', '新记录', '추가')),
            ),
          ],
        ),
        if (present.length > 1) ...[
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  selected: _typeFilter == null,
                  onSelected: (_) => setState(() => _typeFilter = null),
                  label: Text(L10n.text(language, 'All', 'すべて', '全部', '전체')),
                ),
                for (final type in present) ...[
                  const SizedBox(width: 8),
                  ChoiceChip(
                    selected: _typeFilter == type,
                    onSelected: (_) => setState(() => _typeFilter = type),
                    label:
                        Text(L10n.healthRecordTypeTitle(language, type)),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (records.isEmpty)
          PetCard(
            child: Text(
              L10n.text(
                language,
                'Nothing recorded yet. Add a visit, a vaccination or a symptom you noticed.',
                'まだ記録がありません。通院やワクチン、気になる症状を追加しましょう。',
                '还没有记录。可以添加就诊、疫苗，或你注意到的症状。',
                '아직 기록이 없습니다. 진료, 예방접종, 관찰한 증상을 추가해 보세요.',
              ),
              style: const TextStyle(fontSize: 13, color: PawColors.muted),
            ),
          )
        else
          for (final record in records)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _recordRow(context, record, language),
            ),
      ],
    );
  }

  Widget _recordRow(
    BuildContext context,
    HealthRecord record,
    AppLanguage language,
  ) {
    final accent = healthRecordAccent(record.type);
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => _openRecord(context, record.id),
      child: PetCard(
        padding: 14,
        child: Row(
          children: [
            CareIcon(
                icon: healthRecordIcon(record.type), color: accent, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: PawColors.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _subtitle(record, language),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: PawColors.muted),
                  ),
                ],
              ),
            ),
            if (record.attachments.isNotEmpty) ...[
              const Icon(Icons.photo_outlined,
                  size: 14, color: PawColors.muted),
              const SizedBox(width: 3),
              Text(
                '${record.attachments.length}',
                style: const TextStyle(fontSize: 12, color: PawColors.muted),
              ),
              const SizedBox(width: 6),
            ],
            const Icon(Icons.chevron_right, color: PawColors.muted),
          ],
        ),
      ),
    );
  }

  String _subtitle(HealthRecord record, AppLanguage language) {
    final parts = <String>[
      DateFormat.yMMMd(language.rawValue).format(record.occurredAt),
      L10n.healthRecordTypeTitle(language, record.type),
    ];
    if (record.clinicName != null && record.clinicName!.isNotEmpty) {
      parts.add(record.clinicName!);
    }
    if (record.weightKg != null) parts.add('${record.weightKg} kg');
    return parts.join(' · ');
  }

  void _openRecord(BuildContext context, String recordId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HealthRecordDetailView(recordId: recordId),
      ),
    );
  }
}
