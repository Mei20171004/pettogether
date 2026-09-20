import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pettogether/l10n/l10n.dart';
import 'package:pettogether/models/models.dart';
import 'package:pettogether/services/mock_care_service.dart';
import 'package:pettogether/store/care_store.dart';
import 'package:pettogether/theme/app_theme.dart';
import 'package:pettogether/views/health/health_record_editor_view.dart';
import 'package:pettogether/views/widgets/task_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('zh');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('an unclaimed task does not show question mark icons', (
    tester,
  ) async {
    final store = CareStore(MockCareService());
    addTearDown(store.dispose);
    final task = CareTask(
      id: 'task-1',
      title: 'Medication',
      category: CareCategory.medication,
      dueTime: DateTime(2026, 9, 20, 23),
      createdBy: 'Mingze',
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CareStore>.value(value: store),
          ChangeNotifierProvider(
            create: (_) => AppLanguageStore(AppLanguage.chinese),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: TaskCard(task: task)),
        ),
      ),
    );

    expect(find.byIcon(Icons.help_outline), findsNothing);
    expect(find.text('还没有人认领'), findsOneWidget);
  });

  testWidgets('the record editor uses a white system bar with dark controls', (
    tester,
  ) async {
    final store = CareStore(MockCareService());
    addTearDown(store.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CareStore>.value(value: store),
          ChangeNotifierProvider(
            create: (_) => AppLanguageStore(AppLanguage.chinese),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => const HealthRecordEditorView(),
                  ),
                ),
                child: const Text('Open editor'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.backgroundColor, Colors.white);
    expect(appBar.foregroundColor, PawColors.ink);
    expect(appBar.systemOverlayStyle?.statusBarColor, Colors.white);
    expect(appBar.systemOverlayStyle?.statusBarIconBrightness, Brightness.dark);
    expect(appBar.systemOverlayStyle?.statusBarBrightness, Brightness.light);

    final close = tester.widget<Icon>(find.byIcon(Icons.close));
    expect(close.color, isNull);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('Open editor'), findsOneWidget);
  });
}
