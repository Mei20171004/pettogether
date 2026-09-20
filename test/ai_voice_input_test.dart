import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pettogether/l10n/l10n.dart';
import 'package:pettogether/theme/app_theme.dart';
import 'package:pettogether/views/ai_input_dialog.dart';

void main() {
  testWidgets('AI dialog offers editable voice input in Chinese', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: AiInputDialog(
            language: AppLanguage.chinese,
            aiParsesLeft: 99,
            aiParseLimit: 100,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('ai_voice_input_button')), findsOneWidget);
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    expect(find.byTooltip('开始语音输入'), findsOneWidget);
    expect(find.text('输入或说出宠物护理计划…'), findsOneWidget);
    expect(find.text('本月 AI 录入剩余 99/100 次'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '每天晚上八点喂药');
    expect(find.text('每天晚上八点喂药'), findsOneWidget);
  });

  test('light app bars use a white system area with dark controls', () {
    final appBarTheme = buildAppTheme().appBarTheme;

    expect(appBarTheme.backgroundColor, Colors.white);
    expect(appBarTheme.foregroundColor, PawColors.ink);
    expect(appBarTheme.surfaceTintColor, Colors.transparent);
    expect(appBarTheme.systemOverlayStyle, petSystemUiOverlayStyle);
    expect(
      appBarTheme.systemOverlayStyle?.statusBarIconBrightness,
      Brightness.dark,
    );
    expect(
      appBarTheme.systemOverlayStyle?.statusBarBrightness,
      Brightness.light,
    );
  });

  test('speech recognition permissions are declared on iOS and Android', () {
    final iosInfo = File('ios/Runner/Info.plist').readAsStringSync();
    final androidManifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();

    expect(iosInfo, contains('NSMicrophoneUsageDescription'));
    expect(iosInfo, contains('NSSpeechRecognitionUsageDescription'));
    expect(androidManifest, contains('android.permission.RECORD_AUDIO'));
    expect(androidManifest, contains('android.permission.INTERNET'));
    expect(androidManifest, contains('android.speech.RecognitionService'));
  });

  test('global system overlay style is explicit', () {
    expect(petSystemUiOverlayStyle.statusBarColor, Colors.white);
    expect(petSystemUiOverlayStyle.statusBarIconBrightness, Brightness.dark);
    expect(petSystemUiOverlayStyle.statusBarBrightness, Brightness.light);
  });
}
