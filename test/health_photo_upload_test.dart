import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pettogether/l10n/l10n.dart';
import 'package:pettogether/models/health.dart';
import 'package:pettogether/models/models.dart';
import 'package:pettogether/services/mock_care_service.dart';
import 'package:pettogether/services/care_service.dart';
import 'package:pettogether/services/storage_service.dart';
import 'package:pettogether/store/care_store.dart';
import 'package:pettogether/store/pro_access.dart';
import 'package:pettogether/store/purchase_store.dart';
import 'package:pettogether/views/health/health_record_editor_view.dart';

class _FixturePicker extends ImagePickerPlatform {
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    return XFile.fromData(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a6xkAAAAASUVORK5CYII=',
      ),
    );
  }
}

class _HealthPurchases extends PurchaseStore {
  _HealthPurchases() : super(apiKey: '');
  @override
  bool get isPro => true;
}

class _PhotoCare extends CareStore {
  _PhotoCare() : super(MockCareService());
  bool denied = true;
  HealthRecord? saved;
  @override
  Future<HealthAttachment?> uploadHealthAttachment({
    required String recordID,
    required Uint8List bytes,
  }) async {
    if (denied) {
      throw FirebaseException(plugin: 'firebase_storage', code: 'unauthorized');
    }
    return HealthAttachment(
      id: 'fixture-photo',
      url: 'https://example.invalid/fixture.png',
      storagePath: 'households/fixture/records/$recordID/fixture-photo.jpg',
      sizeBytes: bytes.length,
      uploadedAt: DateTime.now(),
    );
  }

  @override
  Future<bool> saveHealthRecord(HealthRecord record) async {
    saved = record;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ja'));

  testWidgets(
    'photo permission failure is visible in Japanese, retry preserves input and saves the attachment',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final originalPicker = ImagePickerPlatform.instance;
      ImagePickerPlatform.instance = _FixturePicker();
      addTearDown(() => ImagePickerPlatform.instance = originalPicker);
      final care = _PhotoCare();
      await care.createHousehold(
        name: 'Fixture',
        pets: const [Pet(id: 'pet', name: 'Luna')],
        caregiverName: 'Tester',
      );
      final purchases = _HealthPurchases();
      final access = ProAccess(
        purchases: purchases,
        care: care,
        currentUid: () => null,
      );
      addTearDown(() {
        access.dispose();
        purchases.dispose();
        care.dispose();
      });
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CareStore>.value(value: care),
            ChangeNotifierProvider<PurchaseStore>.value(value: purchases),
            ChangeNotifierProvider<ProAccess>.value(value: access),
            ChangeNotifierProvider(
              create: (_) => AppLanguageStore(AppLanguage.japanese),
            ),
          ],
          child: const MaterialApp(
            home: HealthRecordEditorView(initialPetId: 'pet'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final titleController = tester
          .widget<TextField>(find.byType(TextField).first)
          .controller!;
      await tester.enterText(find.byType(TextField).first, '検査の記録');
      tester.testTextInput.hide();
      await tester.pumpAndSettle();

      Future<void> takePhoto() async {
        FocusManager.instance.primaryFocus?.unfocus();
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byIcon(Icons.add_a_photo_outlined).hitTestable(),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.byIcon(Icons.add_a_photo_outlined));
        await tester.pumpAndSettle();
        await tester.tap(find.text('写真を撮る'));
        await tester.pumpAndSettle();
      }

      await takePhoto();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('health_photo_error')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.textContaining('写真の利用権を確認できません（unauthorized）'),
        findsOneWidget,
      );
      expect(titleController.text, '検査の記録');
      care.denied = false;
      await takePhoto();
      expect(find.byKey(const ValueKey('health_photo_error')), findsNothing);
      await tester.scrollUntilVisible(
        find.text('保存').hitTestable(),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(care.saved!.attachments.single.id, 'fixture-photo');
      expect(care.saved!.title, '検査の記録');
    },
  );

  test(
    '5 MB photo is rejected locally before making a provider request',
    () async {
      await expectLater(
        StorageService.instance.uploadHealthAttachment(
          householdID: 'fixture',
          recordID: 'fixture',
          bytes: Uint8List(HealthAttachment.maxBytes),
        ),
        throwsA(
          isA<CareServiceError>().having(
            (e) => e.type,
            'kind',
            CareServiceErrorType.attachmentTooLarge,
          ),
        ),
      );
    },
  );
}
