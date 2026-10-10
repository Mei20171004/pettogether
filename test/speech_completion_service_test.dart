import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:pettogether/services/speech_input_service.dart';

void main() {
  testWidgets(
    'only manual finish ends input; native pauses resume without losing words',
    (tester) async {
      const channel = MethodChannel('plugin.csdcorp.com/speech_to_text');
      final messenger = tester.binding.defaultBinaryMessenger;
      var listenCount = 0;
      Completer<bool>? pendingListen;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'listen') {
          listenCount++;
          if (pendingListen != null) return pendingListen.future;
        }
        return switch (call.method) {
          'initialize' || 'has_permission' || 'listen' => true,
          'locales' => ['zh_CN:Chinese'],
          _ => null,
        };
      });
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
      expect(speech.state, SpeechInputState.listening);
      await words('晚上喂水', ResultType.finalResult);
      await native('notifyStatus', 'done');
      await tester.pump();
      expect(listenCount, 3);
      expect(speech.state, SpeechInputState.listening);
      await words('每天梳', ResultType.partial);
      await words('每天梳毛', ResultType.finalResult);
      expect(speech.transcript, '每天喂猫 晚上喂水 每天梳毛');

      // Finish while a pause is awaiting the recognizer's final result.
      await native('notifyStatus', 'notListening');
      final finishDuringPause = speech.stop();
      await native('notifyStatus', 'done');
      await finishDuringPause;
      await tester.pump();
      expect(speech.state, SpeechInputState.idle);
      expect(listenCount, 3);

      // A platform that omits `done` still resumes after a bounded drain.
      await speech.start(existingText: '', languageCode: 'zh');
      await words('喂水', ResultType.partial);
      await native('notifyStatus', 'notListening');
      await tester.pump(const Duration(seconds: 4));
      expect(speech.state, SpeechInputState.listening);
      expect(listenCount, 5);
      await words('梳毛', ResultType.partial);
      expect(speech.transcript, '喂水 梳毛');
      await native('notifyStatus', 'notListening');
      await speech.cancel();
      await tester.pump(const Duration(seconds: 4));
      expect(speech.state, SpeechInputState.idle);
      expect(listenCount, 5);
      // Late native callbacks must not reopen a dismissed dialog's microphone.
      await native('notifyStatus', 'listening');
      await words('过期结果', ResultType.finalResult);
      expect(speech.state, SpeechInputState.idle);
      expect(speech.transcript, '喂水 梳毛');

      // Silence is recoverable; an actual authorization error stops capture.
      await speech.start(existingText: '', languageCode: 'zh');
      await native(
        'notifyError',
        jsonEncode({'errorMsg': 'error_no_match', 'permanent': true}),
      );
      await tester.pump();
      expect(speech.state, SpeechInputState.listening);
      expect(listenCount, 7);
      await native(
        'notifyError',
        jsonEncode({
          'errorMsg': 'error_speech_recognizer_request_not_authorized',
          'permanent': true,
        }),
      );
      expect(speech.state, SpeechInputState.permissionDenied);
      await speech.cancel();

      // Done can also be pressed while a replacement native listen is starting.
      await speech.start(existingText: '', languageCode: 'zh');
      await words('喂水', ResultType.finalResult);
      pendingListen = Completer<bool>();
      await native('notifyStatus', 'done');
      await tester.pump();
      expect(listenCount, 9);
      final finishDuringStart = speech.stop();
      pendingListen.complete(true);
      pendingListen = null;
      await tester.pump();
      await native('notifyStatus', 'doneNoResult');
      await finishDuringStart;
      expect(speech.state, SpeechInputState.idle);
      expect(speech.transcript, '喂水');
      await speech.cancel();
      messenger.setMockMethodCallHandler(channel, null);
    },
  );
}
