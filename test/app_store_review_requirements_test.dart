import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pettogether/l10n/l10n.dart';
import 'package:pettogether/models/models.dart';
import 'package:pettogether/services/mock_care_service.dart';
import 'package:pettogether/store/care_store.dart';
import 'package:pettogether/views/login_view.dart';
import 'package:pettogether/views/manage_household_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  Widget login() => ChangeNotifierProvider(
    create: (_) => AppLanguageStore(AppLanguage.english),
    child: const MaterialApp(home: LoginView()),
  );

  testWidgets('iOS offers Apple alongside Google on the login screen', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(login());

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);
  });

  testWidgets('Android keeps Google without presenting an Apple-only flow', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(login());

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsNothing);
  });

  testWidgets(
    'account deletion is discoverable and explains subscription billing',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = CareStore(MockCareService());
      addTearDown(store.dispose);
      await store.createHousehold(
        name: 'Mochi Family',
        pets: [const Pet(id: 'pet-1', name: 'Mochi')],
        caregiverName: 'Sam',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: store),
            ChangeNotifierProvider(
              create: (_) => AppLanguageStore(AppLanguage.english),
            ),
          ],
          child: const MaterialApp(home: ManageHouseholdView()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Delete account'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();

      expect(find.text('Permanently delete account?'), findsOneWidget);
      expect(
        find.textContaining('does not cancel an App Store subscription'),
        findsOneWidget,
      );
      expect(find.text('Type DELETE to confirm'), findsOneWidget);
    },
  );
}
