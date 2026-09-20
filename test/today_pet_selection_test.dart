import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pettogether/l10n/l10n.dart';
import 'package:pettogether/models/models.dart';
import 'package:pettogether/services/mock_care_service.dart';
import 'package:pettogether/store/care_store.dart';
import 'package:pettogether/store/pro_access.dart';
import 'package:pettogether/store/purchase_store.dart';
import 'package:pettogether/views/today_view.dart';

class _MultiPetAccess extends ProAccess {
  _MultiPetAccess(CareStore care, PurchaseStore purchases)
    : super(purchases: purchases, care: care, currentUid: () => null);

  @override
  bool get canAddPet => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('en');
  });

  Future<CareStore> storeWithTwoPets() async {
    SharedPreferences.setMockInitialValues({});
    final store = CareStore(MockCareService());
    await store.createHousehold(
      name: 'Pet Family',
      pets: const [
        Pet(id: 'cat', name: 'Mochi', type: PetType.cat),
        Pet(id: 'dog', name: 'Rex', type: PetType.dog),
      ],
      caregiverName: 'Sam',
    );
    return store;
  }

  Widget testApp(
    CareStore store, {
    TodayView home = const TodayView(),
    ProAccess? access,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CareStore>.value(value: store),
        if (access != null)
          ChangeNotifierProvider<ProAccess>.value(value: access),
        ChangeNotifierProvider<AppLanguageStore>(
          create: (_) => AppLanguageStore(AppLanguage.english),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: home,
      ),
    );
  }

  testWidgets('a pet without a photo shows an add-photo placeholder', (
    tester,
  ) async {
    final store = await storeWithTwoPets();
    addTearDown(store.dispose);

    await tester.pumpWidget(testApp(store));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('today-hero-add-photo-cat')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byIcon(Icons.add_a_photo_outlined).hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('tapping the hero photo opens the gallery callback in place', (
    tester,
  ) async {
    final store = await storeWithTwoPets();
    addTearDown(store.dispose);
    var pickerCalls = 0;

    await tester.pumpWidget(
      testApp(
        store,
        home: TodayView(
          photoPicker: () async {
            pickerCalls += 1;
            return null;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('today-hero-photo-action-cat')));
    await tester.pumpAndSettle();

    expect(pickerCalls, 1);
    expect(find.byType(TodayView), findsOneWidget);
  });

  testWidgets('photo permission denial explains how to recover', (
    tester,
  ) async {
    final store = await storeWithTwoPets();
    addTearDown(store.dispose);

    await tester.pumpWidget(
      testApp(
        store,
        home: TodayView(
          photoPicker: () async {
            throw PlatformException(code: 'photo_access_denied');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('today-hero-photo-action-cat')));
    await tester.pump();

    expect(
      find.textContaining('Allow pettogether to access Photos in Settings'),
      findsOneWidget,
    );
  });

  testWidgets('Today exposes add pet and saves another pet through CareStore', (
    tester,
  ) async {
    final store = await storeWithTwoPets();
    final purchases = PurchaseStore(apiKey: '');
    final access = _MultiPetAccess(store, purchases);
    addTearDown(access.dispose);
    addTearDown(purchases.dispose);
    addTearDown(store.dispose);

    await tester.pumpWidget(testApp(store, access: access));
    await tester.pumpAndSettle();

    final addButton = find.byKey(const ValueKey('today-add-pet-button'));
    await tester.ensureVisible(addButton);
    await tester.tap(addButton);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('today-add-pet-name')),
      'Luna',
    );
    await tester.tap(find.text('Dog'));
    await tester.tap(find.byKey(const ValueKey('today-add-pet-save')));
    await tester.pumpAndSettle();

    expect(store.household!.pets, hasLength(3));
    expect(
      store.household!.pets.where((pet) => pet.name == 'Luna').single.type,
      PetType.dog,
    );
    expect(find.text('Luna'), findsOneWidget);
  });

  testWidgets('pet chips keep the hero card on the same pet', (tester) async {
    final store = await storeWithTwoPets();
    addTearDown(store.dispose);

    await tester.pumpWidget(testApp(store));
    await tester.pumpAndSettle();

    final dogChip = find.byKey(const ValueKey('today-pet-filter-dog'));
    await tester.ensureVisible(dogChip);
    await tester.pumpAndSettle();
    await tester.tap(dogChip);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('today-hero-pet-dog')), findsOneWidget);

    final allChip = find.byKey(const ValueKey('today-pet-filter-all'));
    await tester.tap(allChip);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('today-hero-pet-cat')), findsOneWidget);
  });

  testWidgets('pet selection updates the hero task summary', (tester) async {
    final store = await storeWithTwoPets();
    addTearDown(store.dispose);
    final due = DateTime.now();
    await store.addTask(
      title: 'Cat care',
      category: CareCategory.feeding,
      kind: CareTaskKind.oneOff,
      priority: CarePriority.normal,
      date: due,
      petIds: const ['cat'],
    );
    for (final title in ['Dog walk', 'Dog dinner']) {
      await store.addTask(
        title: title,
        category: CareCategory.feeding,
        kind: CareTaskKind.oneOff,
        priority: CarePriority.normal,
        date: due,
        petIds: const ['dog'],
      );
    }

    await tester.pumpWidget(testApp(store));
    await tester.pumpAndSettle();
    final allRemaining =
        store.unclaimedTasks.length + store.claimedTasks.length;
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('today-hero-summary-cat')))
          .data,
      '$allRemaining care moments left for today.',
    );

    final dogChip = find.byKey(const ValueKey('today-pet-filter-dog'));
    await tester.ensureVisible(dogChip);
    await tester.tap(dogChip);
    await tester.pumpAndSettle();

    final dogRemaining = [
      ...store.unclaimedTasks,
      ...store.claimedTasks,
    ].where((task) => task.effectivePetIds.contains('dog')).length;
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('today-hero-summary-dog')))
          .data,
      '$dogRemaining care moments left for today.',
    );

    final allChip = find.byKey(const ValueKey('today-pet-filter-all'));
    await tester.tap(allChip);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('today-hero-summary-cat')))
          .data,
      '$allRemaining care moments left for today.',
    );
  });

  testWidgets('swiping the hero keeps the selected pet chip in sync', (
    tester,
  ) async {
    final store = await storeWithTwoPets();
    addTearDown(store.dispose);

    await tester.pumpWidget(testApp(store));
    await tester.pumpAndSettle();

    await tester.fling(find.byType(PageView), const Offset(-600, 0), 1200);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('today-hero-pet-dog')), findsOneWidget);
    final dogChip = tester.widget<Material>(
      find.byKey(const ValueKey('today-pet-filter-dog')),
    );
    expect(dogChip.color, isNot(Colors.white));
  });
}
