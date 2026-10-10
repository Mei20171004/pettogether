import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:pettogether/services/speech_input_service.dart';

void main() {
  testWidgets(
    'manual finish and automatic silence keep final words and recover for another recording',
    (tester) async {
      const channel = MethodChannel('plugin.csdcorp.com/speech_to_text');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => switch (call.method) {
          'initialize' || 'has_permission' || 'listen' => true,
          'locales' => ['zh_CN:Chinese'],
          _ => null,
        },
      );
      Future<void> native(String method, dynamic value) async {
        await messenger.handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(MethodCall(method, value)),
          (_) {},
        );
      }

      Future<void> words(String value, ResultType type) => native(
        'textRecognition',
        jsonEncode({
          'alternates': [
            {'recognizedWords': value, 'confidence': 0.9},
          ],
          'resultType': type.value,
        }),
      );
      final speech = SpeechInputService();
      await speech.start(existingText: '', languageCode: 'zh');
      await words('每天喂', ResultType.partial);
      final stopped = speech.stop();
      expect(speech.state, SpeechInputState.stopping);
      await words('每天喂猫', ResultType.finalResult);
      await native('notifyStatus', 'done');
      await stopped;
      expect(speech.transcript, '每天喂猫');
      expect(speech.isBusy, isFalse);

      await speech.start(existingText: '每天喂猫', languageCode: 'zh');
      await words('晚上喂药', ResultType.partial);
      await native('notifyStatus', 'notListening');
      expect(speech.state, SpeechInputState.stopping);
      // The native recognizer never supplies `done`; the bounded wait recovers.
      await tester.pump(const Duration(seconds: 4));
      expect(speech.isBusy, isFalse);
      expect(speech.transcript, '每天喂猫 晚上喂药');
      await speech.cancel();
      await tester.pump(const Duration(seconds: 4));
      messenger.setMockMethodCallHandler(channel, null);
    },
  );
}
