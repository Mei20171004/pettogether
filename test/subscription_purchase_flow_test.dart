import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'package:pettogether/l10n/l10n.dart';
import 'package:pettogether/services/mock_care_service.dart';
import 'package:pettogether/store/care_store.dart';
import 'package:pettogether/store/pro_access.dart';
import 'package:pettogether/store/purchase_store.dart';
import 'package:pettogether/views/pro_view.dart';

class FakePurchases extends PurchaseStore {
  FakePurchases(this.plans) : super(apiKey: '');
  final List<Package> plans;
  final List<String> bought = [];
  bool busy = false;
  bool unlocked = false;
  Object? failure;
  Completer<bool>? completion;
  @override
  bool get isAvailable => true;
  @override
  bool get isPurchasing => busy;
  @override
  List<Package> get packages => plans;
  @override
  bool hasEntitlement(String id) => unlocked;
  @override
  Future<bool> purchase(
    Package package, {
    String entitlementId = 'pet_together_pro',
  }) async {
    bought.add(package.storeProduct.identifier);
    busy = true;
    notifyListeners();
    try {
      if (failure != null) throw failure!;
      return unlocked = await (completion?.future ?? Future.value(false));
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}

Package plan(String id, PackageType type, String price) => Package(
  id,
  type,
  StoreProduct(id, 'Plan', 'Plan', 300, price, 'JPY'),
  const PresentedOfferingContext('default', null, null),
);

Widget paywall(FakePurchases purchases, ProFeature feature) => MultiProvider(
  providers: [
    ChangeNotifierProvider<PurchaseStore>.value(value: purchases),
    ChangeNotifierProvider(
      create: (_) => AppLanguageStore(AppLanguage.chinese),
    ),
    ChangeNotifierProvider(create: (_) => CareStore(MockCareService())),
    ChangeNotifierProvider(
      create: (context) => ProAccess(
        purchases: purchases,
        care: context.read<CareStore>(),
        entitlements: null,
        currentUid: () => null,
      ),
    ),
  ],
  child: MaterialApp(home: ProView(feature: feature)),
);

void main() {
  for (final feature in ProFeature.values) {
    testWidgets(
      '${feature.name} places purchase action and monthly price together',
      (tester) async {
        final id = switch (feature) {
          ProFeature.health => 'pettogether_pro_monthly',
          ProFeature.ai => 'pettogether_ai_monthly',
          ProFeature.multiPet => 'pettogether_multi_pet_monthly',
        };
        final purchases = FakePurchases([
          plan(id, PackageType.monthly, '¥300'),
        ]);
        await tester.pumpWidget(paywall(purchases, feature));
        await tester.scrollUntilVisible(
          find.byKey(ValueKey('subscribe_$id')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('订阅 · ¥300 / 月'), findsOneWidget);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('subscribe_$id')));
        await tester.pumpAndSettle();
        expect(purchases.bought, [id]);
        expect(find.text('已取消购买，可以重新订阅。'), findsOneWidget);
      },
    );
  }
  testWidgets('annual button charges the annual price with its annual period', (
    tester,
  ) async {
    final purchases = FakePurchases([
      plan('pettogether_pro_yearly', PackageType.annual, '¥2000'),
    ]);
    await tester.pumpWidget(paywall(purchases, ProFeature.health));
    await tester.scrollUntilVisible(
      find.text('订阅 · ¥2000 / 年'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('订阅 · ¥2000 / 年'));
    await tester.pumpAndSettle();
    expect(purchases.bought, ['pettogether_pro_yearly']);
  });
  testWidgets('whole monthly card opens purchase and repeat taps are blocked', (
    tester,
  ) async {
    final purchases = FakePurchases([
      plan('pettogether_multi_pet_monthly', PackageType.monthly, '¥300'),
    ])..completion = Completer<bool>();
    await tester.pumpWidget(paywall(purchases, ProFeature.multiPet));
    await tester.scrollUntilVisible(
      find.text('按月'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('按月'));
    await tester.pump();
    expect(find.text('正在等待商店确认…'), findsOneWidget);
    await tester.tap(find.text('按月'));
    await tester.pump();
    expect(purchases.bought.length, 1);
    purchases.completion!.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('已解锁更多宠物。'), findsOneWidget);
  });
  for (final failure in [
    const PurchaseAccessPending(),
    PlatformException(code: PurchasesErrorCode.networkError.index.toString()),
    PlatformException(
      code: PurchasesErrorCode.paymentPendingError.index.toString(),
    ),
  ]) {
    testWidgets(
      'purchase failure remains visible: ${failure.runtimeType} ${failure is PlatformException ? failure.code : "pending"}',
      (tester) async {
        final purchases = FakePurchases([
          plan('pettogether_ai_monthly', PackageType.monthly, '¥300'),
        ])..failure = failure;
        await tester.pumpWidget(paywall(purchases, ProFeature.ai));
        await tester.scrollUntilVisible(
          find.text('订阅 · ¥300 / 月'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('订阅 · ¥300 / 月'));
        await tester.pumpAndSettle();
        final message = failure is PurchaseAccessPending
            ? '购买已完成，权限仍在同步。请点击“恢复购买”，不要重复购买。'
            : (failure as PlatformException).code ==
                  PurchasesErrorCode.networkError.index.toString()
            ? '无法连接商店，请检查网络后重试。'
            : '付款正在等待批准，请勿重复购买。';
        expect(find.text(message), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('subscribe_pettogether_ai_monthly')),
              )
              .onPressed,
          failure is PlatformException &&
                  failure.code ==
                      PurchasesErrorCode.networkError.index.toString()
              ? isNotNull
              : isNull,
        );
      },
    );
  }
}
