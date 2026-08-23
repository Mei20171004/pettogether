/// Build-time configuration switches.
abstract final class AppConfig {
  /// When true, `main.dart` initializes Firebase and uses
  /// [FirebaseCareService]. This requires a `GoogleService-Info.plist` (iOS)
  /// and `google-services.json` (Android) in the platform runners, plus the
  /// Security Rules deployed from the original repo.
  ///
  /// When false (the default), the app runs fully offline against
  /// [MockCareService] with seeded demo data, so it works immediately.
  static const bool useFirebase = true;
}
