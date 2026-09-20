import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../config/app_config.dart';

/// Wraps the RevenueCat SDK: configures it once, exposes the current Pro
/// entitlement and the packages of the current offering, and performs
/// purchases / restores.
class PurchaseStore extends ChangeNotifier {
  /// Pass an empty [apiKey] to create an inert store (widget tests, unsupported
  /// platforms). Otherwise the key is resolved from the build mode, so a
  /// release build can never come up on the Test Store.
  PurchaseStore({String? apiKey}) : _overrideKey = apiKey;

  final String? _overrideKey;

  bool _configured = false;
  bool _isLoadingOfferings = false;
  bool _isPurchasing = false;
  Set<String> _activeEntitlementIds = const {};
  List<Package> _packages = const [];
  String? _lastError;

  /// True once the SDK is configured. Stays false on unsupported platforms
  /// (web, desktop) so the UI can fall back gracefully.
  bool get isAvailable => _configured;
  bool get isLoadingOfferings => _isLoadingOfferings;
  bool get isPurchasing => _isPurchasing;
  bool get isPro => hasEntitlement(AppConfig.proEntitlementId);
  bool get hasMultiPet => hasEntitlement(AppConfig.multiPetEntitlementId);
  bool get hasAi => hasEntitlement(AppConfig.aiEntitlementId);
  bool hasEntitlement(String entitlementId) =>
      _activeEntitlementIds.contains(entitlementId);
  List<Package> get packages => _packages;
  String? get lastError => _lastError;

  static bool get _platformSupported =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  Future<void> initialize() async {
    if (_configured || !_platformSupported) return;
    final key =
        _overrideKey ?? AppConfig.resolveRevenueCatKey(isIOS: Platform.isIOS);
    if (key == null || key.isEmpty) {
      // A release build with no store key leaves every paid feature locked,
      // which is the safe failure. Configuring with a `test_` key here would
      // make the RevenueCat SDK terminate the app on purpose.
      if (kReleaseMode) {
        _lastError = 'RevenueCat key was not provided to this build.';
        notifyListeners();
      }
      return;
    }
    try {
      await Purchases.setLogLevel(
        kReleaseMode ? LogLevel.warn : LogLevel.debug,
      );
      await Purchases.configure(PurchasesConfiguration(key));
      _configured = true;
      Purchases.addCustomerInfoUpdateListener(_applyCustomerInfo);
      _applyCustomerInfo(await Purchases.getCustomerInfo());
      await refreshOfferings();
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
    }
  }

  /// Ties RevenueCat's app user ID to the signed-in Firebase user so
  /// entitlements follow the account across devices. Pass null on sign-out.
  Future<void> syncUser(String? uid) async {
    if (!_configured) return;
    try {
      if (uid == null) {
        if (!await Purchases.isAnonymous) {
          _applyCustomerInfo(await Purchases.logOut());
        }
        return;
      }
      if (await Purchases.appUserID != uid) {
        final result = await Purchases.logIn(uid);
        _applyCustomerInfo(result.customerInfo);
      }
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
    }
  }

  Future<void> refreshOfferings() async {
    if (!_configured) return;
    _isLoadingOfferings = true;
    notifyListeners();
    try {
      final offerings = await Purchases.getOfferings();
      _packages = offerings.current?.availablePackages ?? const [];
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
    } finally {
      _isLoadingOfferings = false;
      notifyListeners();
    }
  }

  /// Returns true when the purchase completed and unlocked [entitlementId].
  /// Returns false when the user cancelled; rethrows other SDK errors.
  Future<bool> purchase(
    Package package, {
    String entitlementId = AppConfig.proEntitlementId,
  }) async {
    if (!_configured || _isPurchasing) return false;
    _isPurchasing = true;
    notifyListeners();
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      _applyCustomerInfo(result.customerInfo);
      return hasEntitlement(entitlementId);
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) return false;
      _lastError = e.message ?? code.name;
      rethrow;
    } finally {
      _isPurchasing = false;
      notifyListeners();
    }
  }

  /// Returns true when a previous purchase restored [entitlementId].
  Future<bool> restore({
    String entitlementId = AppConfig.proEntitlementId,
  }) async {
    if (!_configured || _isPurchasing) return false;
    _isPurchasing = true;
    notifyListeners();
    try {
      _applyCustomerInfo(await Purchases.restorePurchases());
      return hasEntitlement(entitlementId);
    } on PlatformException catch (e) {
      _lastError = e.message ?? PurchasesErrorHelper.getErrorCode(e).name;
      rethrow;
    } finally {
      _isPurchasing = false;
      notifyListeners();
    }
  }

  void _applyCustomerInfo(CustomerInfo info) {
    final active = info.entitlements.active.keys.toSet();
    if (!setEquals(active, _activeEntitlementIds)) {
      _activeEntitlementIds = active;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_configured) {
      Purchases.removeCustomerInfoUpdateListener(_applyCustomerInfo);
    }
    super.dispose();
  }
}
