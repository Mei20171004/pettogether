import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:timezone/timezone.dart' as tz;

import '../domain/report_models.dart';
import '../domain/health_models.dart';
import '../localization/app_locale.dart';

final class ReportPdfRenderer {
  Future<Uint8List> render({
    required PetCareReport report,
    required AppLocale locale,
    required Uint8List fontBytes,
  }) async {
    final labels = _PdfLabels(locale);
    final font = pw.Font.ttf(fontBytes.buffer.asByteData());
    final theme = pw.ThemeData.withFont(base: font, bold: font);
    final document = pw.Document(theme: theme);
    final events = [
      ...report.care.completedEvents,
      ...report.medication.terminalEvents,
    ]..sort((left, right) => right.recordedAt.compareTo(left.recordedAt));
    final waterRecordCount = report.health.records
        .where((record) => record.waterMilliliters != null)
        .length;

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '${context.pageNumber} / ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ),
        build: (context) => [
          pw.Text(
            labels.title,
            style: pw.TextStyle(
              fontSize: 24,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.deepPurple700,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            report.petNameSnapshot,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            '${_date(report.startAt, report.timeZoneIdentifier)} - '
            '${_date(report.endAt, report.timeZoneIdentifier)} '
            '(${report.rangeDays} ${labels.days})',
            style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 14),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColors.orange50,
              border: pw.Border.all(color: PdfColors.orange200),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Text(labels.nonDiagnostic),
          ),
          pw.SizedBox(height: 18),
          // Only the chosen sections are rendered. The summaries themselves are
          // always computed from the real sources, so an excluded section is
          // absent rather than shown as zero.
          if (report.includes(ReportSection.care))
            _summary(labels.care, [
              _Metric(labels.planned, report.care.planned),
              _Metric(labels.completed, report.care.completed),
              _Metric(labels.unresolved, report.care.unresolved),
            ]),
          if (report.includes(ReportSection.medication))
            _summary(labels.medication, [
              _Metric(labels.planned, report.medication.planned),
              _Metric(labels.administered, report.medication.administered),
              _Metric(labels.skipped, report.medication.skipped),
              _Metric(labels.unresolved, report.medication.unresolved),
              _Metric(labels.late, report.medication.late),
            ]),
          if (report.includes(ReportSection.health))
            _summary(labels.health, [
              _Metric(labels.records, report.health.total),
              _Metric(labels.waterRecords, waterRecordCount),
            ]),
          if (report.includes(ReportSection.water)) ...[
            for (final day in report.health.waterDays)
              pw.Text(labels.waterDaySummary(day)),
            if (report.health.excludedWaterRecordCount > 0)
              pw.Text(
                labels.excludedWaterRecords(
                  report.health.excludedWaterRecordCount,
                ),
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
              ),
            if (report.health.waterDays.isNotEmpty ||
                report.health.excludedWaterRecordCount > 0)
              pw.SizedBox(height: 6),
          ],
          pw.Text(
            labels.capturedOnly,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          if (events.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text(
              labels.events,
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              columnWidths: const {
                0: pw.FlexColumnWidth(2.1),
                1: pw.FlexColumnWidth(1.5),
                2: pw.FlexColumnWidth(1.5),
                3: pw.FlexColumnWidth(2.2),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _cell(labels.event),
                    _cell(labels.outcome),
                    _cell(labels.actor),
                    _cell(labels.recordedAt),
                  ],
                ),
                for (final event in events)
                  pw.TableRow(
                    children: [
                      _cell(event.label),
                      _cell(labels.eventKind(event.kind)),
                      _cell(event.actorNameSnapshot),
                      _cell(
                        _dateTime(event.recordedAt, report.timeZoneIdentifier),
                      ),
                    ],
                  ),
              ],
            ),
          ],
          if (report.includes(ReportSection.health) &&
              report.health.records.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            pw.Text(
              labels.healthDetails,
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              columnWidths: const {
                0: pw.FlexColumnWidth(1.4),
                1: pw.FlexColumnWidth(2.4),
                2: pw.FlexColumnWidth(1.7),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _cell(labels.type),
                    _cell(labels.detail),
                    _cell(labels.recordedAt),
                  ],
                ),
                for (final record in report.health.records.reversed)
                  pw.TableRow(
                    children: [
                      _cell(labels.healthType(record.type)),
                      _cell(
                        [
                          if (record.weightKilograms case final value?)
                            '${value.toStringAsFixed(1)} kg',
                          if (record.waterMilliliters case final value?)
                            '${value.toStringAsFixed(0)} ml',
                          if (record.waterMilliliters != null)
                            labels.waterMeasurementLabel(
                              record.waterMeasurementBasis,
                            ),
                          if (record.dailyCheckIn case final checkIn?)
                            labels.dailyHealthSummary(checkIn),
                          ?record.detail,
                        ].join(' · '),
                      ),
                      _cell(
                        _dateTime(record.recordedAt, report.timeZoneIdentifier),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
    return document.save();
  }

  static pw.Widget _summary(String title, List<_Metric> metrics) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 14),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final metric in metrics)
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: pw.BoxDecoration(
                  color: PdfColors.deepPurple50,
                  borderRadius: pw.BorderRadius.circular(5),
                ),
                child: pw.Text('${metric.label}: ${metric.value}'),
              ),
          ],
        ),
      ],
    ),
  );

  static pw.Widget _cell(String value) => pw.Padding(
    padding: const pw.EdgeInsets.all(6),
    child: pw.Text(value, style: const pw.TextStyle(fontSize: 9)),
  );

  static String _date(DateTime instant, String zone) {
    final local = tz.TZDateTime.from(instant, tz.getLocation(zone));
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  static String _dateTime(DateTime instant, String zone) {
    final local = tz.TZDateTime.from(instant, tz.getLocation(zone));
    return '${_date(instant, zone)} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

final class _Metric {
  const _Metric(this.label, this.value);

  final String label;
  final int value;
}

final class _PdfLabels {
  const _PdfLabels(this.locale);

  final AppLocale locale;

  String text(String english, String japanese) =>
      locale == AppLocale.japanese ? japanese : english;

  String get title => text('CoPaw care report', 'CoPaw ケアレポート');
  String get days => text('days', '日間');
  String get nonDiagnostic => text(
    'Household summary only - not medical advice or a diagnosis.',
    '家族向けの記録サマリーです。医療上の助言や診断ではありません。',
  );
  String get care => text('Care tasks', 'ケアタスク');
  String get medication => text('Medication outcomes', '服薬結果');
  String get health => text('Health observations', '健康観察');
  String get planned => text('Planned', '予定');
  String get completed => text('Completed', '完了');
  String get administered => text('Administered', '投薬済み');
  String get skipped => text('Skipped', 'スキップ');
  String get unresolved => text('Unresolved', '未解決');
  String get late => text('Late', '遅延');
  String get records => text('Records', '記録');
  String get waterRecords => text('Water records', '飲水量記録');
  String waterMeasurementLabel(WaterMeasurementBasis? basis) => switch (basis) {
    WaterMeasurementBasis.singleIntake => text(
      'single recorded intake',
      '1回分の飲水記録',
    ),
    WaterMeasurementBasis.localDayToDate => text(
      'day-to-date through check-in',
      'チェック時点までの当日累計',
    ),
    WaterMeasurementBasis.fullLocalDay => text(
      'reviewed full-day total',
      '確認済みの1日合計',
    ),
    WaterMeasurementBasis.legacyUnknown => text(
      'legacy interval unknown; excluded',
      '旧記録の対象時間が不明・合計対象外',
    ),
    null => text('interval unavailable; excluded', '対象時間が不明・合計対象外'),
  };
  String waterDaySummary(WaterDaySummary summary) {
    final value = summary.milliliters.toStringAsFixed(0);
    return switch (summary.basis) {
      WaterDaySummaryBasis.summedSingleIntakes => text(
        '${summary.localDate}: $value ml from ${summary.includedRecordCount} separate intake records',
        '${summary.localDate}: $value ml (${summary.includedRecordCount}件の1回分記録の合計)',
      ),
      WaterDaySummaryBasis.localDayToDate => text(
        '${summary.localDate}: $value ml through check-in time; not a full-day total',
        '${summary.localDate}: チェック時点まで $value ml (1日合計ではありません)',
      ),
      WaterDaySummaryBasis.fullLocalDay => text(
        '${summary.localDate}: $value ml reviewed full-day total',
        '${summary.localDate}: 確認済みの1日合計 $value ml',
      ),
    };
  }

  String excludedWaterRecords(int count) => text(
    '$count water value${count == 1 ? '' : 's'} remain${count == 1 ? 's' : ''} source-only because ${count == 1 ? 'its interval overlaps or is' : 'their intervals overlap or are'} unknown.',
    '$count件の飲水量は対象時間の重複または不明があるため、元記録のみ表示します。',
  );
  String get capturedOnly => text(
    'Only captured source records are shown; missing values are not inferred.',
    '入力された元記録のみを表示し、未記録の値は推測しません。',
  );
  String get events => text('Confirmed events', '確認済みイベント');
  String get event => text('Event', 'イベント');
  String get outcome => text('Outcome', '結果');
  String get actor => text('Caregiver', '担当者');
  String get recordedAt => text('Recorded at', '記録時刻');
  String get healthDetails => text('Health & medical details', '病歴・健康記録の詳細');
  String get type => text('Type', '種類');
  String get detail => text('Captured detail', '記録内容');

  String healthType(HealthRecordType type) => switch (type) {
    HealthRecordType.dailyCheckIn => text('Daily health check-in', '毎日の健康チェック'),
    HealthRecordType.weight => text('Weight', '体重'),
    HealthRecordType.waterIntake => text('Water intake', '飲水量'),
    HealthRecordType.appetite => text('Appetite', '食欲'),
    HealthRecordType.energy => text('Energy', '元気'),
    HealthRecordType.mood => text('Mood', '気分・様子'),
    HealthRecordType.stoolObservation => text('Stool / observation', '便・観察'),
    HealthRecordType.symptom => text('Symptom', '症状'),
    HealthRecordType.visit => text('Vet visit', '通院'),
    HealthRecordType.vaccine => text('Vaccine', 'ワクチン'),
    HealthRecordType.note => text('Note', 'メモ'),
  };

  String dailyHealthSummary(DailyHealthCheckIn checkIn) => [
    '${text('Water', '飲水')}: ${dailyLevel(checkIn.water)}',
    '${text('Appetite', '食欲')}: ${dailyLevel(checkIn.appetite)}',
    '${text('Urination', '排尿')}: ${dailyLevel(checkIn.urination)}',
    '${text('Stool', '排便')}: ${dailyStatus(checkIn.stool)}',
    '${text('Energy', '元気')}: ${dailyLevel(checkIn.energy)}',
    '${text('Mood', '気分・行動')}: ${dailyStatus(checkIn.mood)}',
  ].join(' · ');

  String dailyLevel(DailyHealthLevel value) => switch (value) {
    DailyHealthLevel.lessThanUsual => text('less than usual', 'いつもより少ない'),
    DailyHealthLevel.usual => text('as usual', 'いつもどおり'),
    DailyHealthLevel.moreThanUsual => text('more than usual', 'いつもより多い'),
    DailyHealthLevel.notObserved => text('not observed', '未確認'),
  };

  String dailyStatus(DailyHealthStatus value) => switch (value) {
    DailyHealthStatus.usual => text('as usual', 'いつもどおり'),
    DailyHealthStatus.changed => text('changed', '変化あり'),
    DailyHealthStatus.notObserved => text('not observed', '未確認'),
  };

  String eventKind(ReportEventKind kind) => switch (kind) {
    ReportEventKind.careCompleted => completed,
    ReportEventKind.medicationAdministered => administered,
    ReportEventKind.medicationSkipped => skipped,
  };
}
