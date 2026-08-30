import 'dart:io';

import 'package:copaw_flutter/src/data/report_pdf_renderer.dart';
import 'package:copaw_flutter/src/domain/health_models.dart';
import 'package:copaw_flutter/src/domain/report_models.dart';
import 'package:copaw_flutter/src/localization/app_locale.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as time_zone_data;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(time_zone_data.initializeTimeZones);

  test('renders a local Unicode PDF for the selected pet and range', () async {
    final font = await rootBundle.load('assets/fonts/NotoSansJP-VF.ttf');
    final report = _report();
    final renderer = ReportPdfRenderer();

    final english = await renderer.render(
      report: report,
      locale: AppLocale.english,
      fontBytes: font.buffer.asUint8List(
        font.offsetInBytes,
        font.lengthInBytes,
      ),
    );
    final japanese = await renderer.render(
      report: report,
      locale: AppLocale.japanese,
      fontBytes: font.buffer.asUint8List(
        font.offsetInBytes,
        font.lengthInBytes,
      ),
    );

    expect(String.fromCharCodes(english.take(5)), '%PDF-');
    expect(String.fromCharCodes(japanese.take(5)), '%PDF-');
    expect(english.length, greaterThan(5000));
    expect(japanese.length, greaterThan(5000));
    expect(
      String.fromCharCodes(english.skip(english.length - 6)),
      contains('EOF'),
    );
    expect(
      String.fromCharCodes(japanese.skip(japanese.length - 6)),
      contains('EOF'),
    );
    expect(japanese, isNot(equals(english)));

    final outputPath = Platform.environment['COPAW_REPORT_PDF_OUTPUT'];
    if (outputPath != null) {
      final output = File(outputPath);
      await output.parent.create(recursive: true);
      await output.writeAsBytes(english, flush: true);
      await File('$outputPath.ja.pdf').writeAsBytes(japanese, flush: true);
    }
  });

  test('an excluded section is absent from the rendered PDF', () async {
    final font = await rootBundle.load('assets/fonts/NotoSansJP-VF.ttf');
    final fontBytes = font.buffer.asUint8List(
      font.offsetInBytes,
      font.lengthInBytes,
    );
    final renderer = ReportPdfRenderer();

    final full = await renderer.render(
      report: _report(),
      locale: AppLocale.english,
      fontBytes: fontBytes,
    );
    final careOnly = await renderer.render(
      report: _report(sections: const {ReportSection.care}),
      locale: AppLocale.english,
      fontBytes: fontBytes,
    );

    expect(String.fromCharCodes(careOnly.take(5)), '%PDF-');
    // The care-only document must be materially smaller: the medication,
    // health, and water sections are gone rather than rendered as zeros.
    expect(careOnly.length, lessThan(full.length));
  });
}

PetCareReport _report({
  Set<ReportSection> sections = const {
    ReportSection.care,
    ReportSection.medication,
    ReportSection.health,
    ReportSection.water,
  },
}) => PetCareReport(
  includedSections: sections,
  petId: 'pet-1',
  petNameSnapshot: 'モチ',
  rangeDays: 7,
  startAt: DateTime.utc(2026, 8, 7, 15),
  endAt: DateTime.utc(2026, 8, 13, 3),
  timeZoneIdentifier: 'Asia/Tokyo',
  care: CareReportSummary(
    planned: 3,
    completed: 1,
    unresolved: 2,
    completedEvents: [
      ReportEvent(
        sourceId: 'care-1',
        kind: ReportEventKind.careCompleted,
        label: '朝ごはん',
        dueAt: DateTime.utc(2026, 8, 12, 23),
        recordedAt: DateTime.utc(2026, 8, 12, 23, 5),
        actorNameSnapshot: '明',
      ),
    ],
  ),
  medication: MedicationReportSummary(
    planned: 2,
    administered: 1,
    skipped: 0,
    unresolved: 1,
    late: 0,
    terminalEvents: [
      ReportEvent(
        sourceId: 'medication-1',
        kind: ReportEventKind.medicationAdministered,
        label: 'ハートケア錠 · 1錠',
        dueAt: DateTime.utc(2026, 8, 12, 23),
        recordedAt: DateTime.utc(2026, 8, 12, 23, 10),
        actorNameSnapshot: '明',
      ),
    ],
  ),
  health: HealthReportSummary(
    total: 3,
    countsByType: const {
      HealthRecordType.waterIntake: 1,
      HealthRecordType.dailyCheckIn: 1,
      HealthRecordType.visit: 1,
    },
    records: [
      HealthRecord(
        id: 'water-1',
        petId: 'pet-1',
        petNameSnapshot: 'モチ',
        type: HealthRecordType.waterIntake,
        recordedAt: DateTime.utc(2026, 8, 12, 9),
        recordedLocalDate: '2026-08-12',
        recordedTimeZoneIdentifier: 'Asia/Tokyo',
        detail: '夕食後に計測',
        weightKilograms: null,
        waterMilliliters: 420,
        waterMeasurementBasis: WaterMeasurementBasis.singleIntake,
        createdById: 'user-1',
        createdByNameSnapshot: '明',
        createdAt: DateTime.utc(2026, 8, 12, 9),
      ),
      HealthRecord(
        id: 'daily-water-1',
        petId: 'pet-1',
        petNameSnapshot: 'モチ',
        type: HealthRecordType.dailyCheckIn,
        recordedAt: DateTime.utc(2026, 8, 12, 8),
        recordedLocalDate: '2026-08-12',
        recordedTimeZoneIdentifier: 'Asia/Tokyo',
        detail: null,
        weightKilograms: null,
        waterMilliliters: 180,
        waterMeasurementBasis: WaterMeasurementBasis.localDayToDate,
        dailyCheckIn: const DailyHealthCheckIn(
          water: DailyHealthLevel.usual,
          appetite: DailyHealthLevel.usual,
          urination: DailyHealthLevel.usual,
          stool: DailyHealthStatus.usual,
          energy: DailyHealthLevel.usual,
          mood: DailyHealthStatus.usual,
        ),
        createdById: 'user-1',
        createdByNameSnapshot: '明',
        createdAt: DateTime.utc(2026, 8, 12, 8),
      ),
      HealthRecord(
        id: 'visit-1',
        petId: 'pet-1',
        petNameSnapshot: 'モチ',
        type: HealthRecordType.visit,
        recordedAt: DateTime.utc(2026, 8, 11, 3),
        detail: '診察：左前脚を確認。処方薬なし。獣医師指示：経過観察。',
        weightKilograms: null,
        createdById: 'user-1',
        createdByNameSnapshot: '明',
        createdAt: DateTime.utc(2026, 8, 11, 3),
      ),
    ],
    waterDays: const [
      WaterDaySummary(
        localDate: '2026-08-12',
        milliliters: 180,
        basis: WaterDaySummaryBasis.localDayToDate,
        includedRecordCount: 1,
        excludedRecordCount: 1,
      ),
    ],
    excludedWaterRecordCount: 1,
  ),
);
