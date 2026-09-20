import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pettogether/l10n/l10n.dart';
import 'package:pettogether/models/models.dart';
import 'package:pettogether/services/mock_care_service.dart';
import 'package:pettogether/store/care_store.dart';
import 'package:pettogether/views/today_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('en');
  });

  Future<CareStore> readyStore() async {
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

  test('a one-off task can be edited and deleted from Today', () async {
    final store = await readyStore();
    addTearDown(store.dispose);
    final due = DateTime.now().add(const Duration(hours: 1));
    await store.addTask(
      title: 'Brush teeth',
      category: CareCategory.grooming,
      kind: CareTaskKind.oneOff,
      priority: CarePriority.normal,
      date: due,
      petIds: const ['cat'],
    );
    final task = store.todayTasks.firstWhere((t) => t.title == 'Brush teeth');
    final changedTime = due.add(const Duration(hours: 2));

    expect(
      await store.updateTaskDetails(
        task,
        title: 'Brush Mochi teeth',
        dueTime: changedTime,
        petIds: const ['dog'],
      ),
      isTrue,
    );
    final edited = store.todayTasks.firstWhere(
      (t) => t.title == 'Brush Mochi teeth',
    );
    expect(edited.dueTime, changedTime);
    expect(edited.effectivePetIds, const ['dog']);

    expect(await store.deleteTask(edited), isTrue);
    expect(store.tasks.where((t) => t.id == edited.id), isEmpty);
  });

  test(
    'a pet can be edited and deleted while the final pet is protected',
    () async {
      final store = await readyStore();
      addTearDown(store.dispose);
      final mochi = store.household!.pets.firstWhere((pet) => pet.id == 'cat');

      expect(await store.updatePet(mochi.copyWith(name: 'Mochi II')), isTrue);
      expect(
        store.household!.pets.firstWhere((pet) => pet.id == 'cat').name,
        'Mochi II',
      );

      expect(await store.removePet('dog'), isTrue);
      expect(store.household!.pets.map((pet) => pet.id), const ['cat']);
      expect(await store.removePet('cat'), isFalse);
      expect(store.household!.pets, hasLength(1));
    },
  );

  test(
    'editing a routine changes its future schedule and delete removes it',
    () async {
      final store = await readyStore();
      addTearDown(store.dispose);
      final due = DateTime.now().add(const Duration(minutes: 30));
      await store.addTask(
        title: 'Brush teeth',
        category: CareCategory.grooming,
        kind: CareTaskKind.routine,
        priority: CarePriority.normal,
        date: due,
        petIds: const ['cat'],
      );
      final task = store.todayTasks.firstWhere((t) => t.title == 'Brush teeth');
      final changedTime = DateTime(
        due.year,
        due.month,
        due.day,
        (due.hour + 2) % 24,
        due.minute,
      );

      expect(
        await store.updateTaskDetails(
          task,
          title: 'Evening teeth',
          dueTime: changedTime,
          petIds: const ['cat', 'dog'],
        ),
        isTrue,
      );
      final routine = store.routines.firstWhere((r) => r.id == task.routineID);
      expect(routine.title, 'Evening teeth');
      expect(routine.hour, changedTime.hour);
      expect(routine.minute, changedTime.minute);
      expect(routine.petIds, const ['cat', 'dog']);

      final editedOccurrence = store.todayTasks.firstWhere(
        (t) => t.routineID == routine.id,
      );
      expect(await store.deleteTask(editedOccurrence), isTrue);
      expect(store.routines.where((r) => r.id == routine.id), isEmpty);
    },
  );

  testWidgets('Today exposes pet and task management menus', (tester) async {
    final store = await readyStore();
    addTearDown(store.dispose);
    await store.addTask(
      title: 'Brush teeth',
      category: CareCategory.grooming,
      kind: CareTaskKind.oneOff,
      priority: CarePriority.normal,
      date: DateTime.now().add(const Duration(minutes: 30)),
      petIds: const ['cat'],
    );
    final task = store.todayTasks.firstWhere((t) => t.title == 'Brush teeth');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CareStore>.value(value: store),
          ChangeNotifierProvider(
            create: (_) => AppLanguageStore(AppLanguage.english),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: const TodayView(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('today-pet-menu-cat')), findsOneWidget);
    expect(find.byKey(ValueKey('today-task-menu-${task.id}')), findsOneWidget);
  });

  testWidgets('Today editors save pet and task changes', (tester) async {
    final store = await readyStore();
    addTearDown(store.dispose);
    await store.addTask(
      title: 'Brush teeth',
      category: CareCategory.grooming,
      kind: CareTaskKind.oneOff,
      priority: CarePriority.normal,
      date: DateTime.now().add(const Duration(minutes: 30)),
      petIds: const ['cat'],
    );
    final task = store.todayTasks.firstWhere((t) => t.title == 'Brush teeth');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CareStore>.value(value: store),
          ChangeNotifierProvider(
            create: (_) => AppLanguageStore(AppLanguage.english),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: const TodayView(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('today-pet-menu-cat')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit pet'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('today-pet-name-field')),
      'Mochi II',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(
      store.household!.pets.firstWhere((pet) => pet.id == 'cat').name,
      'Mochi II',
    );

    final taskMenu = find.byKey(ValueKey('today-task-menu-${task.id}'));
    await tester.ensureVisible(taskMenu);
    await tester.pumpAndSettle();
    await tester.tap(taskMenu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit task'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('today-task-title-field')),
      'Brush teeth gently',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(
      store.todayTasks.any((item) => item.title == 'Brush teeth gently'),
      isTrue,
    );
  });
}
