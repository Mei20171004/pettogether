import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pettogether/l10n/l10n.dart';
import 'package:pettogether/models/health.dart';
import 'package:pettogether/models/models.dart';
import 'package:pettogether/services/mock_care_service.dart';
import 'package:pettogether/store/care_store.dart';
import 'package:pettogether/theme/app_theme.dart';
import 'package:pettogether/views/create_join_view.dart';
import 'package:pettogether/views/health/health_record_editor_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('zh');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'invitation deep link resolves the household id from the invitation',
    () async {
      final store = CareStore(MockCareService());
      addTearDown(store.dispose);

      final firstRestore = store.restoreSession();
      final concurrentRestore = store.restoreSession();
      expect(identical(firstRestore, concurrentRestore), isTrue);
      await firstRestore;
      await store.handleInvitationLink(
        Uri.parse('pettogether://invite/PAW123'),
      );

      expect(store.invitationPreview, isNotNull);
      expect(store.invitationPreview!.id, 'mock-invitation');
      expect(store.invitationPreview!.householdId, isNotEmpty);
      expect(store.errorMessage, isNull);
    },
  );

  testWidgets('platform link opens the invitation preview join flow', (
    tester,
  ) async {
    final store = CareStore(MockCareService());
    addTearDown(store.dispose);
    await store.restoreSession();
    await store.handleInvitationLink(
      Uri.parse(
        'pettogether://invite/PAW123'
        '?household=demo-household',
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CareStore>.value(value: store),
          ChangeNotifierProvider<AppLanguageStore>(
            create: (_) => AppLanguageStore(AppLanguage.english),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const CreateJoinView(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Check before requesting'), findsOneWidget);
    expect(find.text('Mochi Family'), findsWidgets);
    expect(find.textContaining('Invited by'), findsOneWidget);
  });

  test('iOS and Android hand the invitation scheme to app_links', () {
    final androidManifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(androidManifest, contains('android:scheme="pettogether"'));
    expect(androidManifest, contains('android:host="invite"'));
    expect(androidManifest, contains('flutter_deeplinking_enabled'));
    expect(androidManifest, contains('android:value="false"'));

    final iosInfo = File('ios/Runner/Info.plist').readAsStringSync();
    expect(iosInfo, contains('<string>pettogether</string>'));
    expect(iosInfo, contains('<key>FlutterDeepLinkingEnabled</key>'));
  });

  testWidgets('health record labels requirements and saves with blank text', (
    tester,
  ) async {
    final store = CareStore(MockCareService());
    addTearDown(store.dispose);
    await store.createHousehold(
      name: 'Pet Family',
      pets: const [
        Pet(id: 'cat', name: 'Mochi', type: PetType.cat),
        Pet(id: 'dog', name: 'Rex', type: PetType.dog),
      ],
      caregiverName: 'Sam',
    );
    final recordsBefore = store.healthRecords.length;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CareStore>.value(value: store),
          ChangeNotifierProvider<AppLanguageStore>(
            create: (_) => AppLanguageStore(AppLanguage.chinese),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme().copyWith(
            splashFactory: NoSplash.splashFactory,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const HealthRecordEditorView(
                      initialPetId: 'cat',
                      initialType: HealthRecordType.note,
                    ),
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

    expect(find.text('哪只宠物 · 必填'), findsOneWidget);
    expect(find.text('记录类型 · 必填'), findsOneWidget);
    expect(
      tester
          .widgetList<TextField>(find.byType(TextField))
          .any(
            (field) => field.decoration?.hintText?.endsWith('· 选填') ?? false,
          ),
      isTrue,
    );

    final saveButton = find.text('保存记录');
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(store.healthRecords, hasLength(recordsBefore + 1));
    final saved = store.healthRecords.last;
    expect(saved.type, HealthRecordType.note);
    expect(
      saved.title,
      L10n.healthRecordTypeTitle(AppLanguage.chinese, HealthRecordType.note),
    );
  });
}
