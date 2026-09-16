import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'config/app_config.dart';
import 'l10n/l10n.dart';
import 'services/care_service.dart';
import 'services/firebase_care_service.dart';
import 'services/mock_care_service.dart';
import 'services/notification_service.dart';
import 'store/purchase_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Date symbols for the English/Japanese/Chinese/Korean date formatting used by intl.
  await initializeDateFormatting('en');
  await initializeDateFormatting('ja');
  await initializeDateFormatting('zh');
  await initializeDateFormatting('ko');

  final language = await AppLanguageStore.load();
  final purchases = PurchaseStore();
  final services = await _createServices(purchases);

  runApp(
    PetTogetherApp(
      language: language,
      service: services.service,
      notifications: services.notifications,
      purchases: purchases,
    ),
  );
}

/// App Check attests that requests come from a genuine build of this app.
/// It is what stops a repackaged client from spending the project's Gemini
/// quota through Firebase AI Logic, so the AI feature can be sold.
///
/// Failure is not fatal: enforcement happens server-side, so an unattested
/// client simply gets its AI requests rejected while the rest of the app works.
Future<void> _activateAppCheck() async {
  try {
    await FirebaseAppCheck.instance.activate(
      providerApple: kDebugMode
          ? const AppleDebugProvider()
          // App Attest with a DeviceCheck fallback, so devices older than
          // iOS 14 still attest instead of failing every request.
          : const AppleAppAttestWithDeviceCheckFallbackProvider(),
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
    );
  } catch (_) {
    // Missing App Attest capability or an unregistered app; keep going.
  }
}

typedef _AppServices = ({
  CareService service,
  NotificationService? notifications,
});

Future<_AppServices> _createServices(PurchaseStore purchases) async {
  if (AppConfig.useFirebase) {
    try {
      await Firebase.initializeApp();
      await _activateAppCheck();
      final service = FirebaseCareService();
      final notifications = NotificationService(service);
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      unawaited(notifications.initialize());
      // RevenueCat: configure, then keep its app user ID in step with the
      // signed-in Firebase account so Pro follows the user across devices.
      unawaited(
        purchases.initialize().then((_) {
          FirebaseAuth.instance.authStateChanges().listen(
            (user) => purchases.syncUser(user?.uid),
          );
        }),
      );
      return (service: service, notifications: notifications);
    } catch (_) {
      // Configuration files are missing or invalid — fall back to the mock so
      // the app still opens with seeded demo data.
    }
  }
  unawaited(purchases.initialize());
  return (service: MockCareService(), notifications: null);
}
