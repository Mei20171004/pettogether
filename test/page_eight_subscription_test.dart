import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pettogether/l10n/l10n.dart';
import 'package:pettogether/services/mock_care_service.dart';
import 'package:pettogether/store/care_store.dart';
import 'package:pettogether/store/pro_access.dart';
import 'package:pettogether/store/purchase_store.dart';
import 'package:pettogether/views/pro_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget paywall(ProFeature feature) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AppLanguageStore(AppLanguage.chinese),
        ),
        ChangeNotifierProvider(create: (_) => PurchaseStore(apiKey: '')),
        ChangeNotifierProvider(create: (_) => CareStore(MockCareService())),
        ChangeNotifierProvider(
          create: (context) => ProAccess(
            purchases: context.read<PurchaseStore>(),
            care: context.read<CareStore>(),
            entitlements: null,
            currentUid: () => null,
          ),
        ),
      ],
      child: MaterialApp(home: ProView(feature: feature)),
    );
  }

  testWidgets('multi-pet paywall explains the free first pet and ¥300 price', (
    tester,
  ) async {
    await tester.pumpWidget(paywall(ProFeature.multiPet));
    await tester.pumpAndSettle();

    expect(find.text('更多宠物'), findsWidgets);
    expect(find.textContaining('第 1 只宠物免费'), findsOneWidget);
    expect(find.text('¥300 / 月'), findsOneWidget);
    expect(find.text('Free coupon'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('同时使用时合计 ¥600/月'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('同时使用时合计 ¥600/月'), findsOneWidget);
    expect(find.text('医疗记录照片'), findsNothing);
  });

  testWidgets('AI paywall is separate and costs ¥300 per month', (
    tester,
  ) async {
    await tester.pumpWidget(paywall(ProFeature.ai));
    await tester.pumpAndSettle();

    expect(find.text('AI 护理录入'), findsWidgets);
    expect(find.textContaining('每月 ¥300'), findsOneWidget);
    expect(find.text('¥300 / 月'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('同时使用时合计 ¥600/月'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('同时使用时合计 ¥600/月'), findsOneWidget);
    expect(find.text('第 2 只及更多宠物'), findsNothing);
  });
}
