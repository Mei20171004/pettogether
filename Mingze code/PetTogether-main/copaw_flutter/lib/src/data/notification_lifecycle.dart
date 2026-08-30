import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notification_center_repository.dart';
import 'notification_interaction_repository.dart';

abstract interface class NotificationLifecycleSource {
  Stream<Map<String, String>> get foregroundMessages;
  Stream<Map<String, String>> get openedMessages;
  Future<Map<String, String>?> initialMessage();
}

final class DisabledNotificationLifecycleSource
    implements NotificationLifecycleSource {
  const DisabledNotificationLifecycleSource();

  @override
  Stream<Map<String, String>> get foregroundMessages => const Stream.empty();

  @override
  Stream<Map<String, String>> get openedMessages => const Stream.empty();

  @override
  Future<Map<String, String>?> initialMessage() async => null;
}

final class FakeNotificationLifecycleSource
    implements NotificationLifecycleSource {
  FakeNotificationLifecycleSource({this.initialPayload});

  final Map<String, String>? initialPayload;
  final _foreground = StreamController<Map<String, String>>.broadcast();
  final _opened = StreamController<Map<String, String>>.broadcast();

  bool get hasForegroundListener => _foreground.hasListener;

  void emitForeground(Map<String, String> payload) => _foreground.add(payload);
  void emitBackground(Map<String, String> payload) => _opened.add(payload);

  @override
  Stream<Map<String, String>> get foregroundMessages => _foreground.stream;

  @override
  Stream<Map<String, String>> get openedMessages => _opened.stream;

  @override
  Future<Map<String, String>?> initialMessage() async => initialPayload;

  Future<void> close() async {
    await _foreground.close();
    await _opened.close();
  }
}

final class NotificationForegroundPrompt {
  const NotificationForegroundPrompt({
    required this.title,
    required this.body,
    required this.open,
  });

  final String title;
  final String body;
  final Future<void> Function() open;
}

final class NotificationLifecycleCoordinator {
  NotificationLifecycleCoordinator({
    required NotificationLifecycleSource source,
    required NotificationInteractionRepository interaction,
    required void Function(NotificationForegroundPrompt prompt)
    onForegroundPrompt,
    this.onPendingRoutePersisted,
    this.genericBody = 'Care update available',
  }) : _source = source,
       _interaction = interaction,
       _onForegroundPrompt = onForegroundPrompt;

  final NotificationLifecycleSource _source;
  final NotificationInteractionRepository _interaction;
  final void Function(NotificationForegroundPrompt prompt) _onForegroundPrompt;
  final void Function()? onPendingRoutePersisted;
  final String genericBody;
  StreamSubscription<Map<String, String>>? _foregroundSubscription;
  StreamSubscription<Map<String, String>>? _openedSubscription;
  Future<void> _persistChain = Future<void>.value();
  int _clickSequence = 0;
  int _runGeneration = 0;

  Future<void> start() async {
    await stop();
    final generation = ++_runGeneration;
    final initialSequence = _clickSequence;
    _foregroundSubscription = _source.foregroundMessages.listen(
      (payload) => _handleForeground(payload, generation),
      onError: (_) {},
    );
    _openedSubscription = _source.openedMessages.listen((payload) {
      _clickSequence += 1;
      unawaited(_enqueuePersist(payload, generation));
    }, onError: (_) {});
    final initial = await _source.initialMessage();
    if (initial != null &&
        generation == _runGeneration &&
        initialSequence == _clickSequence) {
      await _enqueuePersist(initial, generation);
    }
  }

  void _handleForeground(Map<String, String> payload, int generation) {
    if (generation != _runGeneration) return;
    try {
      decodeNotificationRoutePayload(payload);
    } on NotificationCenterException {
      return;
    }
    _onForegroundPrompt(
      NotificationForegroundPrompt(
        title: 'CoPaw',
        body: genericBody,
        open: () async {
          if (generation != _runGeneration) return;
          _clickSequence += 1;
          await _enqueuePersist(payload, generation);
        },
      ),
    );
  }

  Future<void> _enqueuePersist(Map<String, String> payload, int generation) {
    final result = _persistChain.then(
      (_) => _persistIfExact(payload, generation),
    );
    _persistChain = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _persistIfExact(
    Map<String, String> payload,
    int generation,
  ) async {
    if (generation != _runGeneration) return;
    try {
      final route = await _interaction.persistClick(payload);
      if (generation != _runGeneration) {
        await _interaction.clearPendingRouteIfGeneration(route.generation);
        return;
      }
      onPendingRoutePersisted?.call();
    } on NotificationCenterException {
      // Invalid provider payload is ignored without exposing its contents.
    }
  }

  Future<void> stop() async {
    _runGeneration += 1;
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
    _foregroundSubscription = null;
    _openedSubscription = null;
  }
}

final notificationLifecycleSourceProvider =
    Provider<NotificationLifecycleSource>(
      (ref) => const DisabledNotificationLifecycleSource(),
    );

final class NotificationPendingRouteSignal extends Notifier<int> {
  @override
  int build() => 0;

  void signal() => state += 1;
}

final notificationPendingRouteSignalProvider =
    NotifierProvider<NotificationPendingRouteSignal, int>(
      NotificationPendingRouteSignal.new,
    );
// ignore_for_file: prefer_initializing_formals
