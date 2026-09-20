import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/speech_input_service.dart';
import '../theme/app_theme.dart';
import 'widgets/common.dart';

class AiInputDialog extends StatefulWidget {
  const AiInputDialog({
    super.key,
    required this.language,
    required this.aiParsesLeft,
    required this.aiParseLimit,
    this.showBalance = true,
    this.speechInput,
  });

  final AppLanguage language;
  final int aiParsesLeft;
  final int aiParseLimit;
  final bool showBalance;
  final SpeechInputService? speechInput;

  @override
  State<AiInputDialog> createState() => _AiInputDialogState();
}

class _AiInputDialogState extends State<AiInputDialog>
    with WidgetsBindingObserver {
  final TextEditingController _controller = TextEditingController();
  late final SpeechInputService _speech =
      widget.speechInput ?? SpeechInputService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _speech.addListener(_onSpeechChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _speech.removeListener(_onSpeechChanged);
    unawaited(_speech.cancel());
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_speech.cancel());
    }
  }

  void _onSpeechChanged() {
    if (!mounted) return;
    final text = _speech.transcript;
    if (text != _controller.text) {
      _controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    setState(() {});
  }

  Future<void> _toggleSpeech() async {
    if (_speech.isListening) {
      await _speech.stop();
      return;
    }
    await _speech.start(
      existingText: _controller.text,
      languageCode: widget.language.rawValue,
    );
  }

  Future<void> _cancelAndClose() async {
    await _speech.cancel();
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _submit() async {
    if (_speech.isListening) await _speech.stop();
    if (!mounted) return;
    Navigator.pop(context, _controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    return AlertDialog(
      title: Text(
        L10n.text(language, 'AI assistant', 'AIアシスタント', 'AI 助手', 'AI 어시스턴트'),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showBalance) ...[
            Text(
              L10n.text(
                language,
                '${widget.aiParsesLeft} of ${widget.aiParseLimit} AI entries left this month',
                '今月のAI入力は残り${widget.aiParsesLeft}/${widget.aiParseLimit}回',
                '本月 AI 录入剩余 ${widget.aiParsesLeft}/${widget.aiParseLimit} 次',
                '이번 달 AI 입력 ${widget.aiParsesLeft}/${widget.aiParseLimit}회 남음',
              ),
              style: const TextStyle(fontSize: 12, color: PawColors.muted),
            ),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _controller,
            autofocus: true,
            readOnly: _speech.isListening || _speech.isBusy,
            maxLines: 8,
            minLines: 4,
            decoration:
                petFieldDecoration(
                  hintText: L10n.text(
                    language,
                    'Type or speak your pet care plan…',
                    'ペットのケアを入力または音声で話す…',
                    '输入或说出宠物护理计划…',
                    '반려동물 케어 계획을 입력하거나 말해 주세요…',
                  ),
                ).copyWith(
                  suffixIcon: IconButton(
                    key: const ValueKey('ai_voice_input_button'),
                    tooltip: _speech.isListening
                        ? L10n.text(
                            language,
                            'Stop voice input',
                            '音声入力を停止',
                            '停止语音输入',
                            '음성 입력 중지',
                          )
                        : L10n.text(
                            language,
                            'Start voice input',
                            '音声入力を開始',
                            '开始语音输入',
                            '음성 입력 시작',
                          ),
                    onPressed: _speech.isBusy ? null : _toggleSpeech,
                    icon: _speech.isBusy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            _speech.isListening
                                ? Icons.stop_circle_rounded
                                : Icons.mic_rounded,
                            color: _speech.isListening
                                ? PawColors.rose
                                : PawColors.purple,
                          ),
                  ),
                ),
          ),
          if (_statusMessage(language) case final message?) ...[
            const SizedBox(height: 8),
            Text(
              message,
              key: const ValueKey('ai_voice_input_status'),
              style: TextStyle(
                fontSize: 12,
                color: _speech.state == SpeechInputState.listening
                    ? PawColors.purple
                    : PawColors.rose,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _speech.isBusy ? null : _cancelAndClose,
          child: Text(L10n.text(language, 'Cancel', 'キャンセル', '取消', '취소')),
        ),
        TextButton(
          onPressed: _speech.isBusy ? null : _submit,
          child: Text(L10n.text(language, 'Parse', '解析', '解析', '분석')),
        ),
      ],
    );
  }

  String? _statusMessage(AppLanguage language) {
    return switch (_speech.state) {
      SpeechInputState.idle => null,
      SpeechInputState.initializing => L10n.text(
        language,
        'Preparing voice input…',
        '音声入力を準備しています…',
        '正在准备语音输入…',
        '음성 입력을 준비하고 있습니다…',
      ),
      SpeechInputState.listening => L10n.text(
        language,
        'Listening… Tap the stop button when finished.',
        '聞き取り中…終わったら停止ボタンを押してください。',
        '正在聆听…说完后请点击停止按钮。',
        '듣고 있습니다…완료되면 중지 버튼을 눌러 주세요.',
      ),
      SpeechInputState.stopping => L10n.text(
        language,
        'Finishing transcription…',
        '文字起こしを終了しています…',
        '正在完成语音转写…',
        '음성 변환을 마무리하고 있습니다…',
      ),
      SpeechInputState.permissionDenied => L10n.text(
        language,
        'Allow microphone and speech recognition access in Settings, then try again.',
        '設定でマイクと音声認識を許可してから、もう一度お試しください。',
        '请在系统设置中允许麦克风和语音识别权限，然后重试。',
        '설정에서 마이크와 음성 인식 권한을 허용한 뒤 다시 시도해 주세요.',
      ),
      SpeechInputState.unavailable => L10n.text(
        language,
        'Voice input is not available on this device. You can still type.',
        'この端末では音声入力を利用できません。手入力は引き続き使えます。',
        '此设备暂不支持语音输入，仍可手动输入。',
        '이 기기에서는 음성 입력을 사용할 수 없습니다. 직접 입력할 수 있습니다.',
      ),
      SpeechInputState.noSpeech => L10n.text(
        language,
        'No speech was detected. Tap the microphone to try again.',
        '音声を認識できませんでした。マイクを押してもう一度お試しください。',
        '没有识别到语音，请点击麦克风重试。',
        '음성이 감지되지 않았습니다. 마이크를 눌러 다시 시도해 주세요.',
      ),
      SpeechInputState.error => L10n.text(
        language,
        'Voice input is temporarily unavailable. Try again or type instead.',
        '音声入力を一時的に利用できません。再試行するか手入力してください。',
        '语音输入暂时不可用，请重试或手动输入。',
        '음성 입력을 일시적으로 사용할 수 없습니다. 다시 시도하거나 직접 입력해 주세요.',
      ),
    };
  }
}
