import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../services/entitlement_service.dart';
import 'care_store.dart';
import 'purchase_store.dart';

/// The single answer to "may this person use a Pro feature right now?".
///
/// Three inputs are combined:
///  * the RevenueCat entitlement on this device ([PurchaseStore.isPro]),
///  * the household mirror written by the RevenueCat webhook, so a caregiver
///    benefits from the household owner's subscription without paying twice,
///  * the legacy flag, so households that existed before Pro launched keep the
///    features they already had.
///
/// Every gate in the UI reads this class, never `PurchaseStore` directly.
class ProAccess extends ChangeNotifier {
  ProAccess({
    required PurchaseStore purchases,
    required CareStore care,
    EntitlementService? entitlements,
    String? Function()? currentUid,
    // ignore_for_file: prefer_initializing_formals
    // (named parameters cannot be private, so a formal is not an option here)
  }) : _purchases = purchases,
       _care = care,
       _entitlements = entitlements,
       _currentUid = currentUid ?? _firebaseUid {
    _purchases.addListener(_emit);
    _care.addListener(_syncHousehold);
    _syncHousehold();
    _syncUsage();
  }

  final PurchaseStore _purchases;
  final CareStore _care;
  final EntitlementService? _entitlements;
  final String? Function() _currentUid;

  HouseholdPro _householdPro = HouseholdPro.none;
  AiUsage _usage = AiUsage.empty;
  String? _householdId;
  String? _uid;
  StreamSubscription<HouseholdPro>? _proSubscription;
  StreamSubscription<AiUsage>? _usageSubscription;
  String _lastSignature = '';

  static String? _firebaseUid() {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      // Firebase is not initialized (offline mock mode, widget tests).
      return null;
    }
  }

  // ------------------------------------------------------------------ getters

  /// True when any Pro feature should be available.
  bool get isPro => _purchases.isPro || _householdPro.unlocked;

  /// True when access comes from the pre-launch grandfather flag rather than a
  /// live subscription. Useful for copy: these users are not "subscribers".
  bool get isLegacy =>
      !_purchases.isPro && !_householdPro.active && _householdPro.legacy;

  /// True when somebody else in the household is paying.
  bool get isSharedFromHousehold => !_purchases.isPro && _householdPro.active;

  int get aiParseLimit =>
      isPro ? ProLimits.proAiParsesPerMonth : ProLimits.freeAiParsesPerMonth;

  int get aiParsesUsed => _usage.countFor(EntitlementService.currentMonth());

  int get aiParsesLeft {
    final left = aiParseLimit - aiParsesUsed;
    return left < 0 ? 0 : left;
  }

  bool get canUseAi => aiParsesLeft > 0;

  /// The free tier keeps text-only medical records; photos cost storage, so
  /// they are the one health limit that is also enforced by Security Rules.
  bool get canAttachPhotos => isPro;

  /// The vet visit pack can always be previewed. Only the PDF export is paid.
  bool get canExportVetPack => isPro;

  int get activeMedicationCourses =>
      _care.medicationPlans.where(_care.isPlanRunning).length;

  bool get canStartMedicationCourse =>
      isPro || activeMedicationCourses < ProLimits.freeActiveMedicationCourses;

  // ------------------------------------------------------------------ actions

  /// Counts one AI parse against this month's quota. Failures are swallowed:
  /// losing a count is better than blocking a feature the user paid for.
  Future<void> recordAiParse() async {
    final uid = _uid;
    final service = _entitlements;
    if (uid == null || service == null) return;
    try {
      await service.recordAiParse(uid);
    } catch (_) {
      // Offline or rules rejected the write; the local count stays as is.
    }
  }

  // ------------------------------------------------------------- wiring

  void _syncHousehold() {
    final id = _care.household?.id;
    if (id != _householdId) {
      _householdId = id;
      _proSubscription?.cancel();
      _proSubscription = null;
      _householdPro = HouseholdPro.none;
      final service = _entitlements;
      if (id != null && service != null) {
        _proSubscription = service
            .watchHouseholdPro(id)
            .listen(
              (value) {
                _householdPro = value;
                _emit();
              },
              onError: (_) {
                _householdPro = HouseholdPro.none;
                _emit();
              },
            );
      }
    }
    _syncUsage();
    _emit();
  }

  void _syncUsage() {
    final uid = _currentUid();
    if (uid == _uid) return;
    _uid = uid;
    _usageSubscription?.cancel();
    _usageSubscription = null;
    _usage = AiUsage.empty;
    final service = _entitlements;
    if (uid != null && service != null) {
      _usageSubscription = service
          .watchAiUsage(uid)
          .listen(
            (value) {
              _usage = value;
              _emit();
            },
            onError: (_) {
              _usage = AiUsage.empty;
              _emit();
            },
          );
    }
  }

  /// Only notifies when the derived state actually changed, so listening to
  /// [CareStore] cannot turn into a rebuild loop.
  void _emit() {
    final signature =
        '$isPro|$aiParsesUsed|$aiParseLimit|$activeMedicationCourses';
    if (signature == _lastSignature) return;
    _lastSignature = signature;
    notifyListeners();
  }

  @override
  void dispose() {
    _purchases.removeListener(_emit);
    _care.removeListener(_syncHousehold);
    _proSubscription?.cancel();
    _usageSubscription?.cancel();
    super.dispose();
  }
}
