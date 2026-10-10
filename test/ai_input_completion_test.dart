import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettogether/l10n/l10n.dart';
import 'package:pettogether/services/speech_input_service.dart';
import 'package:pettogether/views/ai_input_dialog.dart';

class FakeSpeech extends SpeechInputService {
  SpeechInputState status = SpeechInputState.idle;
  String text = '';
  @override
  SpeechInputState get state => status;
  @override
  String get transcript => text;
  @override
  bool get isListening => status == SpeechInputState.listening;
  @override
  bool get isBusy =>
      status == SpeechInputState.initializing ||
      status == SpeechInputState.stopping;
  @override
  Future<void> start({
    required String existingText,
    required String languageCode,
  }) async {
    text = existingText;
    status = SpeechInputState.listening;
    notifyListeners();
  }

  void words(String value) {
    text = value;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    status = SpeechInputState.stopping;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    text = '每天晚上八点喂药';
    status = SpeechInputState.idle;
    notifyListeners();
  }

  @override
  Future<void> cancel() async {
    status = SpeechInputState.idle;
    notifyListeners();
  }
}

void main() {
  testWidgets(
    'explicit finish retains final words and only then permits generating a plan',
    (tester) async {
      final speech = FakeSpeech();
      String? submitted;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  submitted = await showDialog<String>(
                    context: context,
                    builder: (_) => AiInputDialog(
                      language: AppLanguage.chinese,
                      aiParsesLeft: 99,
                      aiParseLimit: 100,
                      speechInput: speech,
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '生成护理计划'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('ai_voice_input_button')));
      await tester.pump();
      expect(find.text('我说完了'), findsOneWidget);
      speech.words('每天晚上八点');
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '生成护理计划'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('我说完了'));
      await tester.pump();
      expect(find.text('正在完成语音转写…'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('每天晚上八点喂药'), findsOneWidget);
      await tester.tap(find.text('生成护理计划'));
      await tester.pumpAndSettle();
      expect(submitted, '每天晚上八点喂药');
    },
  );
  testWidgets('speech status changes do not erase manually typed text', (
    tester,
  ) async {
    final speech = FakeSpeech();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiInputDialog(
            language: AppLanguage.chinese,
            aiParsesLeft: 99,
            aiParseLimit: 100,
            speechInput: speech,
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '每天喂猫');
    speech.status = SpeechInputState.permissionDenied;
    speech.notifyListeners();
    await tester.pump();
    expect(find.text('每天喂猫'), findsOneWidget);
    expect(find.textContaining('系统设置中允许麦克风'), findsOneWidget);
  });
  testWidgets('retry dialog restores the previous instruction', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiInputDialog(
            language: AppLanguage.chinese,
            aiParsesLeft: 99,
            aiParseLimit: 100,
            initialText: '每天给猫喂药',
          ),
        ),
      ),
    );
    expect(find.text('每天给猫喂药'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '生成护理计划'))
          .onPressed,
      isNotNull,
    );
  });
}
