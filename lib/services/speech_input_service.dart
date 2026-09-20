import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

enum SpeechInputState {
  idle,
  initializing,
  listening,
  stopping,
  unavailable,
  permissionDenied,
  noSpeech,
  error,
}

/// Owns the app's single speech recognizer and exposes its short-dictation
/// state to the AI input dialog. `SpeechToText.initialize` keeps its first set
/// of callbacks for the whole process, so recreating it for every dialog would
/// leave later dialogs listening to callbacks owned by an earlier route.
class SpeechInputService extends ChangeNotifier {
  SpeechInputService._();

  static final SpeechInputService instance = SpeechInputService._();

  SpeechToText _speech = SpeechToText();
  SpeechInputState _state = SpeechInputState.idle;
  String _transcript = '';
  String _prefix = '';
  String? _diagnostic;
  bool _initialized = false;
  int _session = 0;
  Completer<void>? _sessionDone;

  SpeechInputState get state => _state;
  String get transcript => _transcript;
  String? get diagnostic => _diagnostic;
  bool get isListening => _state == SpeechInputState.listening;
  bool get isBusy =>
      _state == SpeechInputState.initializing ||
      _state == SpeechInputState.stopping;

  Future<void> start({
    required String existingText,
    required String languageCode,
  }) async {
    if (isBusy || isListening) return;

    _prefix = existingText.trimRight();
    _transcript = existingText;
    _diagnostic = null;
    _setState(SpeechInputState.initializing);
    final session = ++_session;

    try {
      if (!_initialized) {
        final recognizer = _speech;
        final available = await recognizer.initialize(
          onStatus: (status) => _handleStatus(recognizer, status),
          onError: (error) => _handleError(recognizer, error),
          options: [SpeechToText.androidNoBluetooth],
        );
        if (session != _session) return;
        if (!available) {
          final permitted = await recognizer.hasPermission;
          if (session != _session) return;
          _speech = SpeechToText();
          _initialized = false;
          _setState(
            permitted
                ? SpeechInputState.unavailable
                : SpeechInputState.permissionDenied,
          );
          return;
        }
        _initialized = true;
      }

      if (session != _session) return;
      if (!_speech.isAvailable) {
        _setState(SpeechInputState.unavailable);
        return;
      }

      final localeId = await _localeForLanguage(languageCode);
      if (session != _session) return;
      _sessionDone = Completer<void>();
      await _speech.listen(
        onResult: (result) => _handleResult(session, result),
        listenOptions: SpeechListenOptions(
          localeId: localeId,
          listenFor: const Duration(minutes: 1),
          pauseFor: const Duration(seconds: 3),
          listenMode: ListenMode.dictation,
          partialResults: true,
          cancelOnError: true,
          autoPunctuation: true,
        ),
      );
      if (session == _session && _state == SpeechInputState.initializing) {
        _setState(SpeechInputState.listening);
      }
    } catch (error, stackTrace) {
      if (session != _session) return;
      _completeSession();
      _diagnostic = error.toString();
      debugPrint('Speech recognition failed: $error\n$stackTrace');
      _setState(SpeechInputState.error);
    }
  }

  Future<void> stop() async {
    if (!isListening) return;
    final session = _session;
    final recognizer = _speech;
    final done = _sessionDone ??= Completer<void>();
    _setState(SpeechInputState.stopping);
    try {
      await recognizer.stop();
      var timedOut = false;
      await done.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => timedOut = true,
      );
      if (session != _session) return;
      if (timedOut) {
        await recognizer.cancel();
        if (session != _session) return;
        _speech = SpeechToText();
        _initialized = false;
        _session++;
      }
      _setState(SpeechInputState.idle);
    } catch (error, stackTrace) {
      if (session != _session) return;
      _completeSession();
      _diagnostic = error.toString();
      debugPrint('Stopping speech recognition failed: $error\n$stackTrace');
      _setState(SpeechInputState.error);
    }
  }

  Future<void> cancel() async {
    final recognizer = _speech;
    _session++;
    _completeSession();
    if (_initialized) {
      try {
        await recognizer.cancel();
      } catch (error, stackTrace) {
        debugPrint('Cancelling speech recognition failed: $error\n$stackTrace');
      }
    }
    _diagnostic = null;
    _setState(SpeechInputState.idle);
  }

  Future<String?> _localeForLanguage(String languageCode) async {
    final prefix = languageCode.toLowerCase();
    final locales = await _speech.locales();
    for (final locale in locales) {
      if (locale.localeId.toLowerCase().startsWith(prefix)) {
        return locale.localeId;
      }
    }
    return null;
  }

  void _handleResult(int session, SpeechRecognitionResult result) {
    if (session != _session) return;
    final words = result.recognizedWords.trim();
    final separator = _prefix.isEmpty || words.isEmpty ? '' : ' ';
    _transcript = '$_prefix$separator$words';
    notifyListeners();
  }

  void _handleStatus(SpeechToText recognizer, String status) {
    if (!identical(recognizer, _speech)) return;
    if (status == SpeechToText.listeningStatus) {
      _setState(SpeechInputState.listening);
      return;
    }
    if (status == SpeechToText.notListeningStatus &&
        _state == SpeechInputState.listening) {
      _setState(SpeechInputState.stopping);
      return;
    }
    if (status == SpeechToText.doneStatus) {
      _completeSession();
      if (_state == SpeechInputState.listening ||
          _state == SpeechInputState.stopping) {
        _setState(SpeechInputState.idle);
      }
    }
  }

  void _handleError(SpeechToText recognizer, SpeechRecognitionError error) {
    if (!identical(recognizer, _speech)) return;
    _completeSession();
    _diagnostic = '${error.errorMsg} (permanent: ${error.permanent})';
    debugPrint('Speech recognition error: $_diagnostic');
    final message = error.errorMsg.toLowerCase();
    if (message.contains('permission')) {
      _setState(SpeechInputState.permissionDenied);
    } else if (message.contains('no_match') ||
        message.contains('speech_timeout')) {
      _setState(SpeechInputState.noSpeech);
    } else {
      _setState(SpeechInputState.error);
    }
  }

  void _setState(SpeechInputState value) {
    if (_state == value) return;
    _state = value;
    notifyListeners();
  }

  void _completeSession() {
    final done = _sessionDone;
    if (done != null && !done.isCompleted) done.complete();
  }
}
