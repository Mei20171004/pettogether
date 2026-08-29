import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/models.dart';
import '../../services/vet_report_pdf.dart';
import '../../store/care_store.dart';
import '../../theme/app_theme.dart';
import '../widgets/common.dart';
import '../../models/vet_visit_pack.dart';

/// Everything worth telling a vet about one pet, on one screen, with an export
/// button. Built fresh from what the household has recorded — nothing here is
/// stored separately, so it can never go stale.
class VetVisitPackView extends StatefulWidget {
  const VetVisitPackView({super.key, required this.pet});

  final Pet pet;

  @override
  State<VetVisitPackView> createState() => _VetVisitPackViewState();
}

class _VetVisitPackViewState extends State<VetVisitPackView> {
  int _rangeDays = 30;
  bool _exporting = false;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<CareStore>();
    final language = context.watch<AppLanguageStore>().language;
    final pet = store.household?.pets
            .where((p) => p.id == widget.pet.id)
            .firstOrNull ??
        widget.pet;

    final pack = VetVisitPack.build(
      store: store,
      pet: pet,
      language: language,
      rangeDays: _rangeDays,
    );
    final dateFormat = DateFormat.yMMMd(language.rawValue);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(L10n.text(
            language, 'Vet visit pack', '通院用まとめ', '就诊资料包', '진료용 자료')),
      ),
      body: Stack(
        children: [
          const PetScreenBackground(),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                    children: [
                      _rangePicker(language),
                      const SizedBox(height: 14),
                      _disclaimer(language),
                      const SizedBox(height: 16),
                      Text(
                        '${pet.name} · ${dateFormat.format(pack.from)} — ${dateFormat.format(pack.to)}',
                        style: const TextStyle(
                            fontSize: 12, color: PawColors.muted),
                      ),
                      const SizedBox(height: 14),
                      for (final section in pack.sections) ...[
                        _section(section, language, dateFormat),
                        const SizedBox(height: 16),
                      ],
                      if (pack.missingSections.isNotEmpty)
                        _missing(pack, language),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                  child: ElevatedButton.icon(
                    style: pawPrimaryButtonStyle(),
                    onPressed:
                        _exporting ? null : () => _export(pack, language),
                    icon: _exporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.ios_share, size: 20),
                    label: Text(L10n.text(language, 'Export as PDF',
                        'PDFで書き出す', '导出 PDF', 'PDF로 내보내기')),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rangePicker(AppLanguage language) {
    return SegmentedButton<int>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
          value: 7,
          label: Text(L10n.text(language, 'Last 7 days', '直近7日', '最近 7 天',
              '최근 7일')),
        ),
        ButtonSegment(
          value: 30,
          label: Text(L10n.text(language, 'Last 30 days', '直近30日', '最近 30 天',
              '최근 30일')),
        ),
        ButtonSegment(
          value: 90,
          label: Text(L10n.text(language, 'Last 90 days', '直近90日', '最近 90 天',
              '최근 90일')),
        ),
      ],
      selected: {_rangeDays},
      onSelectionChanged: (s) => setState(() => _rangeDays = s.first),
    );
  }

  Widget _disclaimer(AppLanguage language) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PawColors.rose.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: PawColors.rose),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              L10n.text(
                language,
                'Compiled from your own records. It is not a diagnosis.',
                'ご自身の記録をまとめたものです。診断ではありません。',
                '这是根据你自己的记录整理的，不构成诊断。',
                '직접 기록한 내용을 정리한 것으로, 진단이 아닙니다.',
              ),
              style: const TextStyle(fontSize: 12, color: PawColors.ink),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(
    VetVisitSection section,
    AppLanguage language,
    DateFormat dateFormat,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PetSectionTitle(
          title: section.titleFor(language),
          detail: '${section.entries.length}',
        ),
        const SizedBox(height: 10),
        PetCard(
          padding: 14,
          child: Column(
            children: [
              for (var i = 0; i < section.entries.length; i++) ...[
                if (i > 0)
                  Divider(
                      height: 18,
                      color: PawColors.purple.withValues(alpha: 0.08)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        section.entries[i].label,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: PawColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (section.entries[i].value.isNotEmpty)
                            Text(
                              section.entries[i].value,
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: PawColors.ink,
                                  height: 1.4),
                            ),
                          if (section.entries[i].occurredAt != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              dateFormat
                                  .format(section.entries[i].occurredAt!),
                              style: const TextStyle(
                                  fontSize: 11, color: PawColors.muted),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Naming the empty sections matters: a vet reading "nothing recorded" knows
  /// the owner looked, whereas a silently omitted section tells them nothing.
  Widget _missing(VetVisitPack pack, AppLanguage language) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PawColors.lavender.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            L10n.text(language, 'Nothing recorded in this period',
                'この期間に記録なし', '本期间没有记录', '이 기간에 기록 없음'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: PawColors.purpleDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            pack.missingSections
                .map((s) => s.titleFor(language))
                .join(' · '),
            style: const TextStyle(fontSize: 12, color: PawColors.muted),
          ),
        ],
      ),
    );
  }

  Future<void> _export(VetVisitPack pack, AppLanguage language) async {
    setState(() => _exporting = true);
    try {
      await VetReportPdf.share(pack: pack, language: language);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${L10n.text(language, "Couldn't create the PDF", 'PDFを作成できませんでした', '无法生成 PDF', 'PDF를 만들지 못했습니다')}: $error',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}
