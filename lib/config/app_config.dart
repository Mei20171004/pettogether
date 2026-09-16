import 'package:flutter/foundation.dart';

/// Build-time configuration switches.
abstract final class AppConfig {
  /// When true, `main.dart` initializes Firebase and uses
  /// [FirebaseCareService]. This requires a `GoogleService-Info.plist` (iOS)
  /// and `google-services.json` (Android) in the platform runners, plus the
  /// Security Rules deployed from the original repo.
  ///
  /// When false, the app runs fully offline against [MockCareService] with
  /// seeded demo data, so it works immediately.
  static const bool useFirebase = true;

  // ---------------------------------------------------------------- RevenueCat

  /// RevenueCat Test Store key. Debug and profile builds only: the Test Store
  /// serves offerings and accepts purchases without any App Store product.
  static const String revenueCatTestKey = 'test_fHYSeznSzgNjiuhggsTEJiEvtxF';

  /// Production public SDK keys, injected at build time so a release build
  /// never depends on someone remembering to edit this file:
  ///
  ///   flutter build ios --dart-define=REVENUECAT_IOS_KEY=appl_xxxxxxxx
  ///
  /// Find the value in the RevenueCat dashboard under the App Store app you
  /// created for this bundle id (Apps -> your iOS app -> public SDK key).
  static const String revenueCatIosKey = String.fromEnvironment(
    'REVENUECAT_IOS_KEY',
  );
  static const String revenueCatAndroidKey = String.fromEnvironment(
    'REVENUECAT_ANDROID_KEY',
  );

  /// RevenueCat entitlement identifier that unlocks pettogether Pro.
  static const String proEntitlementId = 'pro';

  /// Picks the key this build is allowed to use, or null when there is none.
  ///
  /// RevenueCat deliberately crashes a release build that is configured with a
  /// `test_` key, so a release build either gets a real store key or the SDK is
  /// left unconfigured and every paid feature simply stays locked.
  static String? resolveRevenueCatKey({required bool isIOS}) {
    if (kReleaseMode) {
      final key = isIOS ? revenueCatIosKey : revenueCatAndroidKey;
      if (key.isEmpty || key.startsWith('test_')) return null;
      return key;
    }
    return revenueCatTestKey.isEmpty ? null : revenueCatTestKey;
  }
}

/// Where the free tier stops and Pro begins.
///
/// Counting limits (medication courses, pets) cannot be expressed in Firestore
/// Security Rules, so they are enforced here and in the UI. The limits that can
/// be enforced server-side — photo attachments — are also mirrored in
/// `firestore.rules` and `storage.rules`.
abstract final class ProLimits {
  /// AI parses per calendar month. Free users get a real taste; Pro gets a
  /// fair-use ceiling so one account cannot run up the Gemini bill.
  static const int freeAiParsesPerMonth = 3;
  static const int proAiParsesPerMonth = 100;

  /// Medication courses that may be running at the same time.
  static const int freeActiveMedicationCourses = 1;

  /// Pets and caregivers are left unlimited on the free tier until the team
  /// decides whether to charge for them (see the plan's open decisions).
  static const int? freePets = null;
}
