import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/report_models.dart';
import '../localization/app_locale.dart';
import 'report_pdf_renderer.dart';
import 'report_share_repository.dart';

final class SystemReportShareRepository implements ReportShareRepository {
  SystemReportShareRepository({ReportPdfRenderer? renderer})
    : _renderer = renderer ?? ReportPdfRenderer();

  final ReportPdfRenderer _renderer;

  @override
  Future<void> sharePdf({
    required PetCareReport report,
    required AppLocale locale,
    required Rect sharePositionOrigin,
  }) async {
    final fontData = await rootBundle.load('assets/fonts/NotoSansJP-VF.ttf');
    final bytes = await _renderer.render(
      report: report,
      locale: locale,
      fontBytes: fontData.buffer.asUint8List(
        fontData.offsetInBytes,
        fontData.lengthInBytes,
      ),
    );
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            bytes,
            name: 'copaw-care-report-${report.rangeDays}-days.pdf',
            mimeType: 'application/pdf',
          ),
        ],
        subject: locale == AppLocale.japanese
            ? 'CoPaw ケアレポート'
            : 'CoPaw care report',
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }
}
