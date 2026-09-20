import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pettogether/app.dart';
import 'package:pettogether/l10n/l10n.dart';
import 'package:pettogether/services/mock_care_service.dart';

void main() {
  testWidgets('startup loading state uses the PetTogether app icon', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      PetTogetherApp(language: AppLanguage.chinese, service: MockCareService()),
    );

    expect(find.byKey(const ValueKey('startup_brand_icon')), findsOneWidget);
    expect(find.text('Loading your household…'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
