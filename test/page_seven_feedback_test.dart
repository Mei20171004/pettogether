import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pettogether/l10n/l10n.dart';
import 'package:pettogether/models/models.dart';
import 'package:pettogether/services/mock_care_service.dart';
import 'package:pettogether/store/care_store.dart';
import 'package:pettogether/views/widgets/medication_adherence_chart.dart';
import 'package:pettogether/views/widgets/pet_time_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<CareStore> readyStore() async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime.now();
    final store = CareStore(MockCareService());
    await store.createHousehold(
      name: 'Pet Family',
      pets: [
        Pet(
          id: 'cat',
          name: 'Mochi',
          type: PetType.cat,
          weightKg: 4.4,
          weightHistory: [
            PetWeightEntry(
              date: now.subtract(const Duration(days: 60)),
              weightKg: 4.1,
            ),
            PetWeightEntry(
              date: now.subtract(const Duration(days: 30)),
              weightKg: 4.3,
            ),
            PetWeightEntry(date: now, weightKg: 4.4),
          ],
        ),
      ],
      caregiverName: 'Sam',
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return store;
  }

  testWidgets('time selection uses a wheel and returns the confirmed value', (
    tester,
  ) async {
    TimeOfDay? result;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showPetTimePicker(
                context: context,
                initialTime: const TimeOfDay(hour: 8, minute: 15),
                language: AppLanguage.chinese,
              );
            },
            child: const Text('Pick time'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Pick time'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoDatePicker), findsOneWidget);
    expect(find.text('选择时间'), findsOneWidget);

    final picker = tester.widget<CupertinoDatePicker>(
      find.byType(CupertinoDatePicker),
    );
    picker.onDateTimeChanged(DateTime(2026, 1, 1, 18, 45));
    await tester.tap(find.byKey(const ValueKey('pet-time-picker-done')));
    await tester.pumpAndSettle();

    expect(result, const TimeOfDay(hour: 18, minute: 45));

    result = const TimeOfDay(hour: 1, minute: 2);
    await tester.tap(find.text('Pick time'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pet-time-picker-cancel')));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });

  test('medication trend is derived from the pet schedule', () async {
    final store = await readyStore();
    addTearDown(store.dispose);

    final trend = medicationTrendForPet(store, 'cat');

    expect(trend, hasLength(7));
    expect(trend.any((day) => day.planned > 0), isTrue);
    expect(trend.every((day) => day.completed <= day.planned), isTrue);
    for (var index = 1; index < trend.length; index++) {
      expect(trend[index].date.isAfter(trend[index - 1].date), isTrue);
    }

    final noSchedule = medicationTrendForPet(store, 'unknown-pet');
    expect(noSchedule.every((day) => day.planned == 0), isTrue);
  });
}
