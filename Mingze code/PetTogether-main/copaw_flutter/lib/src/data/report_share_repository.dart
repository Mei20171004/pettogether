import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/report_models.dart';
import '../localization/app_locale.dart';

abstract interface class ReportShareRepository {
  Future<void> sharePdf({
    required PetCareReport report,
    required AppLocale locale,
    required Rect sharePositionOrigin,
  });
}

final reportShareRepositoryProvider = Provider<ReportShareRepository>((ref) {
  throw StateError(
    'ReportShareRepository must be provided at the app boundary.',
  );
});
