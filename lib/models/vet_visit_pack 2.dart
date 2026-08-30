import '../l10n/l10n.dart';
import '../models/health.dart';
import '../models/models.dart';
import '../store/care_store.dart';
import '../utils/care_calendar.dart';

/// The sections a vet visit pack is organised into, in the order a vet would
/// want them.
enum VetVisitSectionKind {
  basics,
  currentMedication,
  doseHistory,
  symptoms,
  weight,
  history,
  vaccinations;

  String titleFor(AppLanguage language) {
    return switch (this) {
      VetVisitSectionKind.basics =>
        L10n.text(language, 'Basics', '基本情報', '基本信息', 'Basics'),
      VetVisitSectionKind.currentMedication => L10n.text(
          language, 'Current medication', '服用中の薬', '当前用药', 'Current medication'),
      VetVisitSectionKind.doseHistory => L10n.text(
          language, 'How the medicine went', '服薬の経過', '服药情况', 'How the medicine went'),
      VetVisitSectionKind.symptoms => L10n.text(
          language, 'Symptoms and observations', '症状・気づいたこと', '症状与观察',
          'Symptoms and observations'),
      VetVisitSectionKind.weight =>
        L10n.text(language, 'Weight', '体重', '体重变化', 'Weight'),
      VetVisitSectionKind.history =>
        L10n.text(language, 'Past visits', '通院歴', '既往病史', 'Past visits'),
      VetVisitSectionKind.vaccinations => L10n.text(
          language, 'Vaccinations and deworming', 'ワクチン・駆虫', '疫苗与驱虫',
          'Vaccinations and deworming'),
    };
  }
}

/// One line in the pack. [occurredAt] is left null rather than filled in with
/// "now" — a line without a real time must not look like it has one.
class VetVisitEntry {
  const VetVisitEntry({
    required this.label,
    required this.value,
    this.occurredAt,
  });

  final String label;
  final String value;
  final DateTime? occurredAt;
}

class VetVisitSection {
  const VetVisitSection({required this.kind, required this.entries});

  final VetVisitSectionKind kind;
  final List<VetVisitEntry> entries;

  String titleFor(AppLanguage language) => kind.titleFor(language);
}

/// Everything worth handing a vet about one pet over a window of days.
class VetVisitPack {
  const VetVisitPack({
    required this.pet,
    required this.householdName,
    required this.from,
    required this.to,
    required this.sections,
    required this.missingSections,
  });

  final Pet pet;
  final String householdName;
  final DateTime from;
  final DateTime to;
  final List<VetVisitSection> sections;

  /// Sections with nothing in them. Named explicitly, because "we recorded no
  /// symptoms" and "symptoms were left out of this pack" are different claims.
  final List<VetVisitSectionKind> missingSections;

  /// Assembles a pack from what the store already holds.
  static VetVisitPack build({
    required CareStore store,
    required Pet pet,
    required AppLanguage language,
    required int rangeDays,
  }) {
    final now = DateTime.now();
    final to = startOfDay(now);
    final from = to.subtract(Duration(days: rangeDays - 1));
    final windowEnd = to.add(const Duration(days: 1));

    final sections = <VetVisitSection>[];
    final missing = <VetVisitSectionKind>[];

    void add(VetVisitSectionKind kind, List<VetVisitEntry> entries) {
      if (entries.isEmpty) {
        missing.add(kind);
      } else {
        sections.add(VetVisitSection(kind: kind, entries: entries));
      }
    }

    // Basics — always present, never "missing".
    sections.add(VetVisitSection(
      kind: VetVisitSectionKind.basics,
      entries: [
        VetVisitEntry(
          label: L10n.text(language, 'Name', '名前', '名字', 'Name'),
          value: pet.name,
        ),
        if (pet.ageYears != null)
          VetVisitEntry(
            label: L10n.text(language, 'Age', '年齢', '年龄', 'Age'),
            value: '${pet.ageYears}',
          ),
        if (pet.weightKg != null)
          VetVisitEntry(
            label: L10n.text(language, 'Weight', '体重', '体重', 'Weight'),
            value: '${pet.weightKg} kg',
          ),
        if (pet.habits != null && pet.habits!.isNotEmpty)
          VetVisitEntry(
            label: L10n.text(language, 'Habits', '習慣', '习惯', 'Habits'),
            value: pet.habits!,
          ),
      ],
    ));

    // Current medication. The plans carry no single "recorded at" moment, so
    // these entries deliberately have no timestamp.
    add(
      VetVisitSectionKind.currentMedication,
      [
        for (final plan in store.plansForPet(pet.id, active: true))
          VetVisitEntry(
            label: plan.name,
            value: () {
              final routines = store.routinesForPlan(plan.id);
              return [
                routines
                    .map((r) =>
                        '${r.hour.toString().padLeft(2, '0')}:${r.minute.toString().padLeft(2, '0')} ${r.doseText ?? ''}'
                            .trim())
                    .join(', '),
                if (routines.isNotEmpty)
                  L10n.weekdaySummary(language, routines.first.weekdays),
                if (plan.purpose != null) plan.purpose!,
              ].where((part) => part.isNotEmpty).join(' · ');
            }(),
          ),
      ],
    );

    // How the medicine actually went, per course, over the window.
    final doseEntries = <VetVisitEntry>[];
    for (final plan in store.plansForPet(pet.id)) {
      final stats = store.adherence(planId: plan.id, days: rangeDays);
      if (stats.isEmpty) continue;
      final routineIds =
          store.routinesForPlan(plan.id).map((r) => r.id).toSet();
      final reasons = store.tasks
          .where((t) =>
              t.routineID != null &&
              routineIds.contains(t.routineID) &&
              t.status == CareTaskStatus.skipped &&
              !t.dueTime.isBefore(from) &&
              t.dueTime.isBefore(windowEnd))
          .map((t) => t.skipReason)
          .whereType<MedicationSkipReason>()
          .toList();
      final reasonSummary = <String>[];
      for (final reason in reasons.toSet()) {
        final count = reasons.where((r) => r == reason).length;
        reasonSummary
            .add('${L10n.skipReasonTitle(language, reason)} ×$count');
      }

      doseEntries.add(VetVisitEntry(
        label: plan.name,
        value: [
          '${L10n.text(language, 'given', '投与', '已喂', 'given')} ${stats.given}/${stats.planned}'
              '${stats.percent == null ? '' : ' (${stats.percent}%)'}',
          if (stats.skipped > 0)
            '${L10n.text(language, 'skipped', 'スキップ', '跳过', 'skipped')} ${stats.skipped}',
          if (stats.missed > 0)
            '${L10n.text(language, 'not recorded', '未記録', '未记录', 'not recorded')} ${stats.missed}',
          if (reasonSummary.isNotEmpty) reasonSummary.join(', '),
        ].join(' · '),
      ));
    }
    add(VetVisitSectionKind.doseHistory, doseEntries);

    bool inWindow(DateTime when) =>
        !when.isBefore(from) && when.isBefore(windowEnd);

    // Symptoms and free-form notes from the window — the things an owner
    // notices between visits and then forgets in the consulting room.
    add(
      VetVisitSectionKind.symptoms,
      [
        for (final record in store.recordsForPet(pet.id).where((r) =>
            (r.type == HealthRecordType.symptom ||
                r.type == HealthRecordType.note) &&
            inWindow(r.occurredAt)))
          VetVisitEntry(
            label: record.title,
            value: [
              if (record.temperatureC != null) '${record.temperatureC} °C',
              if (record.notes != null) record.notes!,
            ].join(' · '),
            occurredAt: record.occurredAt,
          ),
      ],
    );

    add(
      VetVisitSectionKind.weight,
      [
        for (final entry in pet.weightHistory.where((e) => inWindow(e.date)))
          VetVisitEntry(
            label: L10n.text(language, 'Weight', '体重', '体重', 'Weight'),
            value: '${entry.weightKg} kg',
            occurredAt: entry.date,
          ),
      ],
    );

    // Past visits are not window-limited: a diagnosis from last year is still
    // the most useful thing in the room.
    add(
      VetVisitSectionKind.history,
      [
        for (final record in store.recordsForPet(pet.id).where((r) =>
            r.type == HealthRecordType.vetVisit ||
            r.type == HealthRecordType.surgery ||
            r.type == HealthRecordType.labResult))
          VetVisitEntry(
            label: record.title,
            value: [
              if (record.clinicName != null) record.clinicName!,
              if (record.diagnosis != null) record.diagnosis!,
              if (record.treatment != null) record.treatment!,
            ].join(' · '),
            occurredAt: record.occurredAt,
          ),
      ],
    );

    add(
      VetVisitSectionKind.vaccinations,
      [
        for (final record in store.recordsForPet(pet.id).where((r) =>
            r.type == HealthRecordType.vaccination ||
            r.type == HealthRecordType.deworming))
          VetVisitEntry(
            label: record.productName ?? record.title,
            value: [
              if (record.lotNumber != null)
                '${L10n.text(language, 'lot', 'ロット', '批号', 'lot')} ${record.lotNumber}',
              if (record.nextDueAt != null)
                '${L10n.text(language, 'next due', '次回', '下次到期', 'next due')} '
                    '${record.nextDueAt!.year}-${record.nextDueAt!.month.toString().padLeft(2, '0')}-${record.nextDueAt!.day.toString().padLeft(2, '0')}',
            ].join(' · '),
            occurredAt: record.occurredAt,
          ),
      ],
    );

    return VetVisitPack(
      pet: pet,
      householdName: store.household?.name ?? '',
      from: from,
      to: to,
      sections: sections,
      missingSections: missing,
    );
  }
}
