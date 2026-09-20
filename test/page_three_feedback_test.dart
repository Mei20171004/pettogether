import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pettogether/l10n/l10n.dart';
import 'package:pettogether/models/models.dart';
import 'package:pettogether/services/mock_care_service.dart';
import 'package:pettogether/store/care_store.dart';
import 'package:pettogether/views/health/health_view.dart';
import 'package:pettogether/views/widgets/task_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('zh');
  });

  Future<CareStore> readyStore() async {
    SharedPreferences.setMockInitialValues({});
    final store = CareStore(MockCareService());
    await store.createHousehold(
      name: 'Pet Family',
      pets: const [Pet(id: 'cat', name: 'Mochi', type: PetType.cat)],
      caregiverName: 'Sam',
    );
    return store;
  }

  Widget testApp(CareStore store, Widget home) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CareStore>.value(value: store),
        ChangeNotifierProvider<AppLanguageStore>(
          create: (_) => AppLanguageStore(AppLanguage.chinese),
        ),
      ],
      child: MaterialApp(home: home),
    );
  }

  test('a one-off task can be skipped and restored', () async {
    final store = await readyStore();
    addTearDown(store.dispose);
    await store.addOneOffTask(
      title: 'Dinner',
      category: CareCategory.feeding,
      dueTime: DateTime.now(),
    );

    final task = store.todayTasks.firstWhere((task) => task.title == 'Dinner');
    expect(await store.skipTaskOccurrence(task), isTrue);

    final skipped = store.todayTasks.firstWhere(
      (task) => task.title == 'Dinner',
    );
    expect(skipped.status, CareTaskStatus.skipped);
    expect(await store.restoreTaskOccurrence(skipped), isTrue);
    expect(
      store.todayTasks.firstWhere((task) => task.title == 'Dinner').status,
      CareTaskStatus.unclaimed,
    );
  });

  testWidgets('an unclaimed one-off task offers skip', (tester) async {
    final store = await readyStore();
    addTearDown(store.dispose);
    final task = CareTask(
      id: 'one-off',
      title: 'Dinner',
      category: CareCategory.feeding,
      dueTime: DateTime.now(),
      createdBy: 'Sam',
    );

    await tester.pumpWidget(
      testApp(store, Scaffold(body: TaskCard(task: task))),
    );

    expect(find.text('今天跳过'), findsOneWidget);
  });

  testWidgets(
    'course-generated medication is not repeated in medical history',
    (tester) async {
      final store = await readyStore();
      addTearDown(store.dispose);

      await tester.pumpWidget(testApp(store, const HealthView()));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ChoiceChip, '用药'), findsNothing);
      expect(find.text('Vomiting and off food'), findsOneWidget);
    },
  );
}
