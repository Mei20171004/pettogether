import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pettogether/l10n/l10n.dart';
import 'package:pettogether/models/models.dart';
import 'package:pettogether/models/vet_visit_pack.dart';
import 'package:pettogether/services/mock_care_service.dart';
import 'package:pettogether/services/vet_report_pdf.dart';
import 'package:pettogether/store/care_store.dart';
import 'package:pettogether/store/pro_access.dart';
import 'package:pettogether/store/purchase_store.dart';
import 'package:pettogether/views/add_task_view.dart';
import 'package:pettogether/views/health/pet_health_section.dart';
import 'package:pettogether/views/health/vet_visit_pack_view.dart';
import 'package:pettogether/views/pro_view.dart';

class _PaidHealth extends PurchaseStore {
  _PaidHealth() : super(apiKey: '');
  @override
  bool get isPro => true;
}

void main() {
  setUpAll(() => initializeDateFormatting('zh'));
  setUp(() => SharedPreferences.setMockInitialValues({}));
  const dog = Pet(id: 'dog', name: 'Luna', type: PetType.dog);

  Future<CareStore> mount(WidgetTester tester, Widget page, {bool paid = false}) async {
    final care = CareStore(MockCareService());
    await care.createHousehold(name: 'Fixture family',
      pets: const [Pet(id: 'cat', name: 'Mochi'), dog], caregiverName: 'Tester');
    final purchases = paid ? _PaidHealth() : PurchaseStore(apiKey: '');
    final access = ProAccess(purchases: purchases, care: care, currentUid: () => null);
    addTearDown(() { access.dispose(); care.dispose(); purchases.dispose(); });
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<CareStore>.value(value: care),
        ChangeNotifierProvider<PurchaseStore>.value(value: purchases),
        ChangeNotifierProvider<ProAccess>.value(value: access),
        ChangeNotifierProvider(create: (_) => AppLanguageStore(AppLanguage.chinese)),
      ], child: MaterialApp(home: Scaffold(body: page)),
    ));
    await tester.pumpAndSettle();
    return care;
  }

  testWidgets('health page exposes three tools; PDF preview is free and export is gated', (tester) async {
    await mount(tester, const PetHealthSection(pet: dog));
    for (final tool in ['photos', 'pdf', 'courses']) {
      expect(find.byKey(ValueKey('health_tool_$tool')), findsOneWidget);
    }
    await tester.ensureVisible(find.byKey(const ValueKey('health_tool_pdf')));
    await tester.tap(find.byKey(const ValueKey('health_tool_pdf')));
    await tester.pumpAndSettle();
    expect(find.byType(VetVisitPackView), findsOneWidget);
    expect(find.textContaining('Luna'), findsWidgets);
    await tester.tap(find.text('导出 PDF'));
    await tester.pumpAndSettle();
    expect(find.byType(ProView), findsOneWidget);
    expect(find.textContaining('导出兽医就诊包 PDF 是 Pro 功能'), findsOneWidget);
  });

  testWidgets('medical photos entry offers Health Pro to a free user', (tester) async {
    await mount(tester, const PetHealthSection(pet: dog));
    await tester.ensureVisible(find.byKey(const ValueKey('health_tool_photos')));
    await tester.tap(find.byKey(const ValueKey('health_tool_photos')));
    await tester.pumpAndSettle();
    expect(find.byType(ProView), findsOneWidget);
    await tester.scrollUntilVisible(find.text('健康 Pro、AI 护理录入和多宠物是三个独立订阅。'), 200,
      scrollable: find.byType(Scrollable).first);
    expect(find.text('健康 Pro、AI 护理录入和多宠物是三个独立订阅。'), findsOneWidget);
  });

  testWidgets('a paid new course stays assigned to the selected dog', (tester) async {
    final care = await mount(tester, const AddTaskView(
      initialCategory: CareCategory.medication, initialPetId: 'dog'), paid: true);
    final chip = find.widgetWithText(ChoiceChip, 'Luna');
    await tester.ensureVisible(chip);
    expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Mochi')).selected, isFalse);
    await tester.enterText(find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == '药盒上的名称'), 'Fixture medicine');
    await tester.enterText(find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == '剂量'), '1 tablet');
    await tester.pump();
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, '保存')).onPressed, isNotNull);
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();
    expect(care.errorMessage, isNull);
    expect(care.plansForPet('dog'), hasLength(1));
    expect(care.medicationPlans, hasLength(2));
    expect(care.plansForPet('cat').where((p) => p.name == 'Fixture medicine'), isEmpty);
  });

  testWidgets('Chinese vet report renders a real PDF with the selected pet data', (tester) async {
    final care = await mount(tester, const SizedBox());
    final pack = VetVisitPack.build(store: care, pet: dog,
      language: AppLanguage.chinese, rangeDays: 30);
    final bytes = await tester.runAsync(() => VetReportPdf.render(pack: pack, language: AppLanguage.chinese));
    expect(bytes, isNotNull);
    expect(String.fromCharCodes(bytes!.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
    await tester.runAsync(() => File('/tmp/pettogether-build9-fixture-vet-report.pdf').writeAsBytes(bytes));
  });
}
