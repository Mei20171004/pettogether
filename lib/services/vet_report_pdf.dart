import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../l10n/l10n.dart';
import '../models/vet_visit_pack.dart';

/// Renders a [VetVisitPack] as a PDF and hands it to the system share sheet.
///
/// Nothing is uploaded anywhere — the file is built on the device and goes
/// wherever the owner sends it.
abstract final class VetReportPdf {
  static const _fontAsset = 'assets/fonts/NotoSansJP-VF.ttf';

  static Future<void> share({
    required VetVisitPack pack,
    required AppLanguage language,
  }) async {
    final bytes = await render(pack: pack, language: language);
    final safeName = pack.pet.name.replaceAll(RegExp(r'[^\w\-]'), '_');
    final stamp = DateFormat('yyyyMMdd').format(DateTime.now());

    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            bytes,
            name: 'pettogether-$safeName-$stamp.pdf',
            mimeType: 'application/pdf',
          ),
        ],
        subject: '${pack.pet.name} — pettogether',
      ),
    );
  }

  static Future<Uint8List> render({
    required VetVisitPack pack,
    required AppLanguage language,
  }) async {
    // Noto Sans JP carries Latin, kana and the Han characters the Japanese and
    // Chinese labels need. It has no Hangul, so Korean falls back to English
    // rather than printing rows of empty boxes.
    final effective =
        language == AppLanguage.korean ? AppLanguage.english : language;
    final fontData = await rootBundle.load(_fontAsset);
    final font = pw.Font.ttf(fontData);
    final theme = pw.ThemeData.withFont(base: font, bold: font);

    final document = pw.Document(theme: theme);
    final dateFormat = DateFormat.yMMMd(effective.rawValue);

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '${context.pageNumber} / ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ),
        build: (context) => [
          _header(pack, effective, dateFormat),
          pw.SizedBox(height: 14),
          _disclaimer(effective),
          pw.SizedBox(height: 18),
          for (final section in pack.sections) ...[
            _section(section, effective, dateFormat),
            pw.SizedBox(height: 16),
          ],
          if (pack.missingSections.isNotEmpty) _missing(pack, effective),
          pw.SizedBox(height: 18),
          _footerNote(pack, effective, dateFormat),
        ],
      ),
    );

    return document.save();
  }

  static pw.Widget _header(
    VetVisitPack pack,
    AppLanguage language,
    DateFormat dateFormat,
  ) {
    final subtitle = [
      if (pack.pet.ageYears != null)
        '${pack.pet.ageYears} ${L10n.text(language, 'years old', '歳', '岁', 'years old')}',
      if (pack.pet.weightKg != null) '${pack.pet.weightKg} kg',
    ].join(' · ');

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          L10n.text(language, 'Vet visit pack', '通院用まとめ', '就诊资料包',
              'Vet visit pack'),
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          pack.pet.name + (subtitle.isEmpty ? '' : '  ·  $subtitle'),
          style: const pw.TextStyle(fontSize: 13),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          '${dateFormat.format(pack.from)} — ${dateFormat.format(pack.to)}',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
      ],
    );
  }

  static pw.Widget _disclaimer(AppLanguage language) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.orange50,
        border: pw.Border.all(color: PdfColors.orange200),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Text(
        L10n.text(
          language,
          'Compiled by the owner from their own records. Not a diagnosis and not a clinical document.',
          '飼い主の記録をまとめたものです。診断書ではありません。',
          '本资料由主人根据自己的记录整理，不构成诊断，也不是病历文书。',
          'Compiled by the owner from their own records. Not a diagnosis and not a clinical document.',
        ),
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.orange900),
      ),
    );
  }

  static pw.Widget _section(
    VetVisitSection section,
    AppLanguage language,
    DateFormat dateFormat,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          section.titleFor(language),
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.symmetric(
            inside: const pw.BorderSide(color: PdfColors.grey300, width: 0.5),
          ),
          columnWidths: const {
            0: pw.FlexColumnWidth(1.6),
            1: pw.FlexColumnWidth(3.4),
            2: pw.FlexColumnWidth(1.2),
          },
          children: [
            for (final entry in section.entries)
              pw.TableRow(
                children: [
                  _cell(entry.label, bold: true),
                  _cell(entry.value),
                  _cell(
                    entry.occurredAt == null
                        ? ''
                        : dateFormat.format(entry.occurredAt!),
                    muted: true,
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _cell(String text, {bool bold = false, bool muted = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9.5,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: muted ? PdfColors.grey700 : PdfColors.black,
        ),
      ),
    );
  }

  /// "Nothing recorded" and "left out of the pack" are different facts, so the
  /// empty sections are named rather than silently dropped.
  static pw.Widget _missing(VetVisitPack pack, AppLanguage language) {
    final names =
        pack.missingSections.map((s) => s.titleFor(language)).join(' · ');
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Text(
        '${L10n.text(language, 'Nothing recorded in this period', 'この期間に記録なし', '本期间无记录', 'Nothing recorded in this period')}: $names',
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
      ),
    );
  }

  static pw.Widget _footerNote(
    VetVisitPack pack,
    AppLanguage language,
    DateFormat dateFormat,
  ) {
    return pw.Text(
      '${L10n.text(language, 'Generated by pettogether on', 'pettogether で作成', 'pettogether 生成于', 'Generated by pettogether on')} '
      '${dateFormat.format(DateTime.now())} · ${pack.householdName}',
      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
    );
  }
}
