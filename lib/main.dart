import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'config/app_config.dart';
import 'l10n/l10n.dart';
import 'services/care_service.dart';
import 'services/firebase_care_service.dart';
import 'services/mock_care_service.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Date symbols for the English/Japanese/Chinese/Korean date formatting used by intl.
  await initializeDateFormatting('en');
  await initializeDateFormatting('ja');
  await initializeDateFormatting('zh');
  await initializeDateFormatting('ko');

  final language = await AppLanguageStore.load();
  final services = await _createServices();

  runApp(PetTogetherApp(
    language: language,
    service: services.service,
    notifications: services.notifications,
  ));
}

typedef _AppServices = ({CareService service, NotificationService? notifications});

Future<_AppServices> _createServices() async {
  if (AppConfig.useFirebase) {
    try {
      await Firebase.initializeApp();
      final service = FirebaseCareService();
      final notifications = NotificationService(service);
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      unawaited(notifications.initialize());
      return (service: service, notifications: notifications);
    } catch (_) {
      // Configuration files are missing or invalid — fall back to the mock so
      // the app still opens with seeded demo data.
    }
  }
  return (service: MockCareService(), notifications: null);
}
