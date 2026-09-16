import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pettogether/config/app_config.dart';
import 'package:pettogether/models/models.dart';
import 'package:pettogether/services/mock_care_service.dart';
import 'package:pettogether/store/care_store.dart';
import 'package:pettogether/store/pro_access.dart';
import 'package:pettogether/store/purchase_store.dart';

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

    test('may try the AI parser a few times a month', () async {
      final (access: access, care: care) = await _freeUser();
      addTearDown(() {
        access.dispose();
        care.dispose();
      });

      expect(access.aiParseLimit, ProLimits.freeAiParsesPerMonth);
      expect(access.aiParsesUsed, 0);
      expect(access.aiParsesLeft, ProLimits.freeAiParsesPerMonth);
      expect(access.canUseAi, isTrue);
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

  group('AppConfig.resolveRevenueCatKey', () {
    test('hands debug builds the Test Store key', () {
      // Tests run in debug mode, which is the branch that must never reach a
      // release build: RevenueCat terminates a release build on a test_ key.
      final key = AppConfig.resolveRevenueCatKey(isIOS: true);
      expect(key, isNotNull);
      expect(key, startsWith('test_'));
    });
  });
}
