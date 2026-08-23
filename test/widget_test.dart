// Smoke test for the copaw Flutter app.
//
// The app boots into the offline mock service, so this simply verifies the
// root widget tree mounts without throwing.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pettogetter/app.dart';
import 'package:pettogetter/l10n/l10n.dart';
import 'package:pettogetter/services/mock_care_service.dart';

void main() {
  testWidgets('boots into the welcome screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      CopawApp(language: AppLanguage.english, service: MockCareService()),
    );

    // Session restore is async; settle timers and rebuild.
    await tester.pumpAndSettle();

    expect(find.text('copaw'), findsOneWidget);
  });
}
