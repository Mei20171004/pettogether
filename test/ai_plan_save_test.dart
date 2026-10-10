import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pettogether/l10n/l10n.dart';
import 'package:pettogether/models/ai_plan.dart';
import 'package:pettogether/models/models.dart';
import 'package:pettogether/services/mock_care_service.dart';
import 'package:pettogether/store/care_store.dart';
import 'package:pettogether/store/pro_access.dart';
import 'package:pettogether/store/purchase_store.dart';
import 'package:pettogether/views/ai_result_view.dart';

class AiPurchases extends PurchaseStore {
  AiPurchases() : super(apiKey: '');
  @override
  bool get hasAi => true;
}

class SavingCare extends CareStore {
  SavingCare() : super(MockCareService());
  final List<String> attempts = [];
  final List<String> saved = [];
  bool failSecond = true;
  @override
  Future<bool> addTask({
    required String title,
    required CareCategory category,
    required CareTaskKind kind,
    required CarePriority priority,
    required DateTime date,
    CareRoutineFrequency frequency = CareRoutineFrequency.daily,
    List<int> weekdays = const [1, 2, 3, 4, 5, 6, 7],
    int interval = 1,
    String? petID,
    List<String> petIds = const [],
  }) async {
    attempts.add(title);
    if (title == 'Task two' && failSecond) return false;
    saved.add(title);
    return true;
  }
}

AiParsedTask task(String title) => AiParsedTask(
  title: title,
  category: CareCategory.builtIns.first,
  kind: CareTaskKind.routine,
  frequency: CareRoutineFrequency.daily,
  hour: 20,
  minute: 0,
);

void main() {
  testWidgets(
    'partial save stays open and retry skips successfully saved tasks',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final care = SavingCare();
      await care.createHousehold(
        name: 'Test family',
        pets: [const Pet(id: 'test-pet', name: 'Test pet')],
        caregiverName: 'Tester',
      );
      final purchases = AiPurchases();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CareStore>.value(value: care),
            ChangeNotifierProvider<PurchaseStore>.value(value: purchases),
            ChangeNotifierProvider(
              create: (_) => AppLanguageStore(AppLanguage.chinese),
            ),
            ChangeNotifierProvider(
              create: (_) => ProAccess(
                purchases: purchases,
                care: care,
                entitlements: null,
                currentUid: () => null,
              ),
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AiResultView(
                        result: AiParseResult(
                          tasks: [task('Task one'), task('Task two')],
                          petWeights: const [],
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确定并录入'));
      await tester.pumpAndSettle();
      expect(find.byType(AiResultView), findsOneWidget);
      expect(find.textContaining('还有 1 项未保存'), findsOneWidget);
      expect(care.saved, ['Task one']);
      care.failSecond = false;
      await tester.tap(find.text('重试未保存项目'));
      await tester.pumpAndSettle();
      expect(care.saved, ['Task one', 'Task two']);
      expect(care.attempts, ['Task one', 'Task two', 'Task two']);
      expect(find.byType(AiResultView), findsNothing);
      expect(find.text('护理计划已录入。'), findsOneWidget);
    },
  );
  testWidgets(
    'empty AI results explain what to do and cannot pretend to save',
    (tester) async {
      final care = SavingCare();
      final purchases = AiPurchases();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CareStore>.value(value: care),
            ChangeNotifierProvider(
              create: (_) => AppLanguageStore(AppLanguage.chinese),
            ),
          ],
          child: const MaterialApp(
            home: AiResultView(
              result: AiParseResult(tasks: [], petWeights: []),
            ),
          ),
        ),
      );
      expect(find.textContaining('没有识别到护理任务'), findsOneWidget);
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, '确定并录入'),
            )
            .onPressed,
        isNull,
      );
      purchases.dispose();
    },
  );
}
