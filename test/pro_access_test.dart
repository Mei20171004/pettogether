import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pettogether/config/app_config.dart';
import 'package:pettogether/models/models.dart';
import 'package:pettogether/services/mock_care_service.dart';
import 'package:pettogether/services/entitlement_service.dart';
import 'package:pettogether/store/care_store.dart';
import 'package:pettogether/store/pro_access.dart';
import 'package:pettogether/store/purchase_store.dart';

class _EntitlementPurchaseStore extends PurchaseStore {
  _EntitlementPurchaseStore(this.entitlements) : super(apiKey: '');

  final Set<String> entitlements;

  @override
  bool get isPro => entitlements.contains(AppConfig.proEntitlementId);

  @override
  bool get hasMultiPet =>
      entitlements.contains(AppConfig.multiPetEntitlementId);

  @override
  bool get hasAi => entitlements.contains(AppConfig.aiEntitlementId);
}

class _CouponEntitlementService extends Fake implements EntitlementService {
  DateTime? expiresAt;
  bool redeemed = false;

  @override
  Stream<HouseholdPro> watchHouseholdPro(String householdId) =>
      Stream.value(HouseholdPro.none);

  @override
  Stream<AiUsage> watchAiUsage(String uid) => Stream.value(AiUsage.empty);

  @override
  Future<DateTime?> checkFreeCoupon(String uid) async =>
      redeemed ? expiresAt : null;

  @override
  Future<DateTime?> redeemFreeCoupon(String uid, String code) async {
    if (code != 'petlove2026') return null;
    redeemed = true;
    return expiresAt;
  }
}

/// A ProAccess with no RevenueCat key and no Firestore behind it, which is the
/// state a free user starts in.
Future<({ProAccess access, CareStore care})> _freeUser() async {
  SharedPreferences.setMockInitialValues({});
  final care = CareStore(MockCareService());
  await care.createHousehold(
    name: 'Mochi Family',
    pets: [const Pet(id: 'pet-1', name: 'Mochi')],
    caregiverName: 'Sam',
  );
  await Future<void>.delayed(const Duration(milliseconds: 50));
  final access = ProAccess(
    purchases: PurchaseStore(apiKey: ''),
    care: care,
    entitlements: null,
    currentUid: () => null,
  );
  return (access: access, care: care);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProAccess, for a user who has not paid', () {
    test('starts locked out of the paid health features', () async {
      final (access: access, care: care) = await _freeUser();
      addTearDown(() {
        access.dispose();
        care.dispose();
      });

      expect(access.isPro, isFalse);
      expect(access.canAttachPhotos, isFalse);
      expect(access.canExportVetPack, isFalse);
    });

    test('must subscribe before using AI', () async {
      final (access: access, care: care) = await _freeUser();
      addTearDown(() {
        access.dispose();
        care.dispose();
      });

      expect(access.aiParseLimit, ProLimits.freeAiParsesPerMonth);
      expect(access.aiParsesUsed, 0);
      expect(access.aiParsesLeft, ProLimits.freeAiParsesPerMonth);
      expect(access.canUseAi, isFalse);
    });

    test('may keep one pet but cannot add a second pet', () async {
      final (access: access, care: care) = await _freeUser();
      addTearDown(() {
        access.dispose();
        care.dispose();
      });

      expect(care.household!.pets, hasLength(1));
      expect(ProLimits.freePets, 1);
      expect(access.canAddPet, isFalse);
    });

    test('cannot start a second concurrent medication course', () async {
      final (access: access, care: care) = await _freeUser();
      addTearDown(() {
        access.dispose();
        care.dispose();
      });

      // The seeded household already has one course running, which is exactly
      // the free allowance, so the next one has to be paid for.
      expect(ProLimits.freeActiveMedicationCourses, 1);
      expect(access.activeMedicationCourses, 1);
      expect(access.canStartMedicationCourse, isFalse);
    });

    test('is not treated as a grandfathered household', () async {
      final (access: access, care: care) = await _freeUser();
      addTearDown(() {
        access.dispose();
        care.dispose();
      });

      expect(access.isLegacy, isFalse);
      expect(access.isSharedFromHousehold, isFalse);
    });
  });

  group('independent monthly add-ons', () {
    Future<({ProAccess access, CareStore care, PurchaseStore purchases})>
    accessWith(Set<String> entitlements) async {
      SharedPreferences.setMockInitialValues({});
      final care = CareStore(MockCareService());
      await care.createHousehold(
        name: 'Mochi Family',
        pets: [const Pet(id: 'pet-1', name: 'Mochi')],
        caregiverName: 'Sam',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final purchases = _EntitlementPurchaseStore(entitlements);
      final access = ProAccess(
        purchases: purchases,
        care: care,
        entitlements: null,
        currentUid: () => null,
      );
      return (access: access, care: care, purchases: purchases);
    }

    test('multi-pet unlocks only additional pets', () async {
      final result = await accessWith({AppConfig.multiPetEntitlementId});
      addTearDown(() {
        result.access.dispose();
        result.care.dispose();
        result.purchases.dispose();
      });

      expect(result.access.canAddPet, isTrue);
      expect(result.access.canUseAi, isFalse);
      expect(result.access.isPro, isFalse);
      expect(result.access.canAttachPhotos, isFalse);
    });

    test('AI unlocks only AI', () async {
      final result = await accessWith({AppConfig.aiEntitlementId});
      addTearDown(() {
        result.access.dispose();
        result.care.dispose();
        result.purchases.dispose();
      });

      expect(result.access.canUseAi, isTrue);
      expect(result.access.canAddPet, isFalse);
      expect(result.access.isPro, isFalse);
      expect(result.access.canAttachPhotos, isFalse);
    });

    test('health Pro does not unlock either add-on', () async {
      final result = await accessWith({AppConfig.proEntitlementId});
      addTearDown(() {
        result.access.dispose();
        result.care.dispose();
        result.purchases.dispose();
      });

      expect(result.access.isPro, isTrue);
      expect(result.access.canAddPet, isFalse);
      expect(result.access.canUseAi, isFalse);
    });
  });

  test('coupon unlocks every paid gate and expires automatically', () async {
    SharedPreferences.setMockInitialValues({});
    final care = CareStore(MockCareService());
    await care.createHousehold(
      name: 'Mochi Family',
      pets: [const Pet(id: 'pet-1', name: 'Mochi')],
      caregiverName: 'Sam',
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final service = _CouponEntitlementService()
      ..expiresAt = DateTime.now().add(const Duration(milliseconds: 350));
    final access = ProAccess(
      purchases: PurchaseStore(apiKey: ''),
      care: care,
      entitlements: service,
      currentUid: () => 'user-1',
    );
    addTearDown(() {
      access.dispose();
      care.dispose();
    });

    expect(await access.redeemFreeCoupon('wrong'), isFalse);
    expect(access.isFreeCouponActive, isFalse);
    expect(await access.redeemFreeCoupon('petlove2026'), isTrue);
    expect(access.isPro, isTrue);
    expect(access.canAddPet, isTrue);
    expect(access.canAttachPhotos, isTrue);
    expect(access.canExportVetPack, isTrue);
    expect(access.canStartMedicationCourse, isTrue);
    expect(access.canUseAi, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 420));
    expect(access.isFreeCouponActive, isFalse);
    expect(access.canAddPet, isFalse);
    expect(access.canAttachPhotos, isFalse);
    expect(access.canUseAi, isFalse);
  });

  group('AppConfig.resolveRevenueCatKey', () {
    test('hands debug builds the Test Store key', () {
      // Tests run in debug mode, which is the branch that must never reach a
      // release build: RevenueCat terminates a release build on a test_ key.
      final key = AppConfig.resolveRevenueCatKey(isIOS: true);
      expect(key, isNotNull);
      expect(key, startsWith('test_'));
    });

    test('uses separate products and entitlements for each add-on', () {
      expect(
        AppConfig.multiPetMonthlyProductId,
        'pettogether_multi_pet_monthly',
      );
      expect(AppConfig.aiMonthlyProductId, 'pettogether_ai_monthly');
      expect(AppConfig.multiPetEntitlementId, isNot(AppConfig.aiEntitlementId));
      expect(
        AppConfig.multiPetEntitlementId,
        isNot(AppConfig.proEntitlementId),
      );
    });
  });
}
