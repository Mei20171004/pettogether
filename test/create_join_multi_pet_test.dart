import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pettogether/l10n/l10n.dart';
import 'package:pettogether/services/mock_care_service.dart';
import 'package:pettogether/store/care_store.dart';
import 'package:pettogether/store/pro_access.dart';
import 'package:pettogether/store/purchase_store.dart';
import 'package:pettogether/theme/app_theme.dart';
import 'package:pettogether/views/create_join_view.dart';

class _TestPurchaseStore extends PurchaseStore {
  _TestPurchaseStore() : super(apiKey: '');

  bool unlocked = false;

  @override
  bool get hasMultiPet => unlocked;

  void unlock() {
    unlocked = true;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('second pet opens paywall and is not added if dismissed', (
    tester,
  ) async {
    final care = CareStore(MockCareService());
    final purchases = _TestPurchaseStore();
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
          ChangeNotifierProvider<AppLanguageStore>(
            create: (_) => AppLanguageStore(AppLanguage.english),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const CreateJoinView(),
        ),
      ),
    );

    await tester.ensureVisible(find.text('Add pet'));
    await tester.tap(find.text('Add pet'));
    await tester.pumpAndSettle();
    expect(find.text('More pets'), findsWidgets);
    expect(find.text('Pet 2'), findsNothing);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(find.text('Pet 2'), findsNothing);
  });

  testWidgets('unlocked user can submit a household with two pets', (
    tester,
  ) async {
    final care = CareStore(MockCareService());
    final purchases = _TestPurchaseStore();
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
          ChangeNotifierProvider<AppLanguageStore>(
            create: (_) => AppLanguageStore(AppLanguage.english),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const CreateJoinView(),
        ),
      ),
    );

    await tester.ensureVisible(find.text('Add pet'));
    await tester.tap(find.text('Add pet'));
    await tester.pumpAndSettle();
    purchases.unlock();
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    expect(find.text('Pet 2'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'Sam');
    await tester.enterText(find.byType(TextField).at(2), 'Mochi');
    await tester.enterText(find.byType(TextField).at(3), 'May');
    await tester.ensureVisible(find.byKey(const ValueKey('pet-type-pet-1-cat')));
    await tester.tap(find.byKey(const ValueKey('pet-type-pet-1-cat')));
    await tester.ensureVisible(find.byKey(const ValueKey('pet-type-pet-2-dog')));
    await tester.tap(find.byKey(const ValueKey('pet-type-pet-2-dog')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Create household'));
    await tester.tap(find.text('Create household'));
    await tester.pumpAndSettle();

    expect(care.household?.pets, hasLength(2));
  });
}
