import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'config/app_config.dart';
import 'l10n/l10n.dart';
import 'services/care_service.dart';
import 'services/firebase_care_service.dart';
import 'services/mock_care_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Date symbols for the English/Japanese/Chinese/Korean date formatting used by intl.
  await initializeDateFormatting('en');
  await initializeDateFormatting('ja');
  await initializeDateFormatting('zh');
  await initializeDateFormatting('ko');

  final language = await AppLanguageStore.load();
  final service = await _createService();

  runApp(CopawApp(language: language, service: service));
}

Future<CareService> _createService() async {
  if (AppConfig.useFirebase) {
    try {
      await Firebase.initializeApp();
      return FirebaseCareService();
    } catch (_) {
      // Configuration files are missing or invalid — fall back to the mock so
      // the app still opens with seeded demo data.
    }
  }
  return MockCareService();
}
