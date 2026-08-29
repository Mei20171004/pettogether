// Smoke test for the pettogether Flutter app.
//
// The app boots into the offline mock service, so this simply verifies the
// root widget tree mounts without throwing.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pettogether/app.dart';
import 'package:pettogether/l10n/l10n.dart';
import 'package:pettogether/services/mock_care_service.dart';

void main() {
  testWidgets('boots into the welcome screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      PetTogetherApp(language: AppLanguage.english, service: MockCareService()),
    );

    // Session restore is async; settle timers and rebuild.
    await tester.pumpAndSettle();

    expect(find.text('pettogether'), findsOneWidget);
  });
}
