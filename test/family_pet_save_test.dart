import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pettogether/l10n/l10n.dart';
import 'package:pettogether/models/models.dart';
import 'package:pettogether/services/care_service.dart';
import 'package:pettogether/services/mock_care_service.dart';
import 'package:pettogether/store/care_store.dart';
import 'package:pettogether/store/pro_access.dart';
import 'package:pettogether/store/purchase_store.dart';
import 'package:pettogether/views/manage_household_view.dart';

class _Purchases extends PurchaseStore {
  _Purchases() : super(apiKey: '');
  @override
  bool get hasMultiPet => true;
}

class _PetService extends MockCareService {
  bool fail = false;
  int attempts = 0;
  Completer<void>? pending;

  @override
  Future<void> addPet(String householdID, Pet pet) async {
    attempts++;
    await pending?.future;
    if (fail) {
      throw const CareServiceError(CareServiceErrorType.permissionDenied);
    }
    await super.addPet(householdID, pet);
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('zh'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<CareStore> openForm(WidgetTester tester, _PetService service) async {
    final care = CareStore(service);
    await care.createHousehold(
      name: 'Test family',
      pets: const [Pet(id: 'cat', name: 'Mochi')],
      caregiverName: 'Tester',
    );
    final purchases = _Purchases();
    final access = ProAccess(
      purchases: purchases,
      care: care,
      currentUid: () => null,
    );
    addTearDown(() {
      access.dispose();
      purchases.dispose();
      care.dispose();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CareStore>.value(value: care),
          ChangeNotifierProvider<PurchaseStore>.value(value: purchases),
          ChangeNotifierProvider<ProAccess>.value(value: access),
          ChangeNotifierProvider(
            create: (_) => AppLanguageStore(AppLanguage.chinese),
          ),
        ],
        child: const MaterialApp(home: ManageHouseholdView()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('添加宠物'));
    await tester.tap(find.text('添加宠物'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '狗'));
    await tester.pump();
    return care;
  }

  testWidgets(
    'selecting Dog without a name explains the requirement and keeps the form',
    (tester) async {
      final service = _PetService();
      final care = await openForm(tester, service);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('请输入宠物名字。'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '取消'), findsOneWidget);
      expect(service.attempts, 0);
      expect(care.household!.pets, hasLength(1));
    },
  );

  testWidgets(
    'a failed paid second-pet save retains the name and Dog selection for retry',
    (tester) async {
      final service = _PetService()..fail = true;
      final care = await openForm(tester, service);
      await tester.enterText(find.byType(TextField).first, 'Luna');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('保存失败'), findsOneWidget);
      expect(find.textContaining("You don't have permission"), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '狗'))
            .selected,
        isTrue,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Luna',
      );
      expect(care.household!.pets, hasLength(1));
      service.fail = false;
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(care.household!.pets, hasLength(2));
      expect(care.household!.pets.last.type, PetType.dog);
      expect(find.text('Luna'), findsOneWidget);
    },
  );

  testWidgets(
    'saving waits for the backend and repeated taps create only one Dog',
    (tester) async {
      final service = _PetService()..pending = Completer<void>();
      final care = await openForm(tester, service);
      await tester.enterText(find.byType(TextField).first, 'Luna');
      await tester.tap(find.text('保存'));
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('正在保存…'));
      await tester.pump();
      expect(service.attempts, 1);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      service.pending!.complete();
      await tester.pumpAndSettle();
      expect(care.household!.pets, hasLength(2));
      expect(care.household!.pets.last.type, PetType.dog);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
}
