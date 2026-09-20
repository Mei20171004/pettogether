import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pettogether/l10n/l10n.dart';
import 'package:pettogether/models/health.dart';
import 'package:pettogether/models/models.dart';
import 'package:pettogether/services/mock_care_service.dart';
import 'package:pettogether/store/care_store.dart';
import 'package:pettogether/theme/app_theme.dart';
import 'package:pettogether/views/health/health_record_editor_view.dart';

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
      pets: const [
        Pet(id: 'cat', name: 'Mochi', type: PetType.cat),
        Pet(id: 'dog', name: 'Rex', type: PetType.dog),
      ],
      caregiverName: 'Sam',
    );
    return store;
  }

  Widget testApp(CareStore store, HealthRecordType initialType) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CareStore>.value(value: store),
        ChangeNotifierProvider(
          create: (_) => AppLanguageStore(AppLanguage.chinese),
        ),
      ],
      child: MaterialApp(
        theme: buildAppTheme().copyWith(splashFactory: NoSplash.splashFactory),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => HealthRecordEditorView(
                    initialPetId: 'cat',
                    initialType: initialType,
                  ),
                ),
              ),
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openEditor(
    WidgetTester tester,
    CareStore store,
    HealthRecordType type,
  ) async {
    await tester.pumpWidget(testApp(store, type));
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
  }

  Future<void> tapSave(WidgetTester tester) async {
    final save = find.widgetWithText(ElevatedButton, '保存记录');
    await tester.scrollUntilVisible(
      save,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(save);
    await tester.pumpAndSettle();
  }

  final visibleTypes = HealthRecordType.values
      .where((type) => !type.isCourseGenerated)
      .toList();

  for (final type in visibleTypes) {
    testWidgets('${type.rawValue} is valid on first selection', (tester) async {
      final store = await readyStore();
      addTearDown(store.dispose);
      final before = store.healthRecords.length;

      await openEditor(tester, store, type);

      expect(find.text('哪只宠物 · 必填'), findsOneWidget);
      expect(find.text('记录类型 · 必填'), findsOneWidget);
      expect(find.text('发生时间 · 必填'), findsOneWidget);
      if (type.hasNextDue) {
        expect(find.text('下次到期 · 选填'), findsOneWidget);
      }

      if (type == HealthRecordType.weight) {
        await tester.enterText(
          find.widgetWithText(TextField, '体重（kg） · 必填'),
          '4.8',
        );
      }

      await tapSave(tester);

      expect(store.healthRecords, hasLength(before + 1));
      expect(store.healthRecords.last.type, type);
    });
  }

  testWidgets('switching record types keeps the unfinished text draft', (
    tester,
  ) async {
    final store = await readyStore();
    addTearDown(store.dispose);
    await openEditor(tester, store, HealthRecordType.vetVisit);

    final title = find.byType(TextField).first;
    await tester.enterText(title, '晚上开始咳嗽');
    await tester.tap(find.widgetWithText(ChoiceChip, '疫苗'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '就诊'));
    await tester.pumpAndSettle();

    expect(find.text('晚上开始咳嗽'), findsOneWidget);
  });

  testWidgets('photo attachments are explicitly labelled optional', (
    tester,
  ) async {
    final store = await readyStore();
    addTearDown(store.dispose);
    await openEditor(tester, store, HealthRecordType.note);

    await tester.scrollUntilVisible(
      find.text('照片 · 选填'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('照片 · 选填'), findsOneWidget);
  });
}
