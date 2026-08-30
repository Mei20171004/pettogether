import 'dart:async';

import 'package:copaw_flutter/src/data/notification_center_repository.dart';
import 'package:copaw_flutter/src/data/notification_lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'foreground stays generic and persists exact payload only after tap',
    () async {
      final source = FakeNotificationLifecycleSource();
      final interaction = FakeNotificationInteractionRepository();
      NotificationForegroundPrompt? prompt;
      final coordinator = NotificationLifecycleCoordinator(
        source: source,
        interaction: interaction,
        onForegroundPrompt: (value) => prompt = value,
      );
      await coordinator.start();

      source.emitForeground(_payload('a'));
      await Future<void>.delayed(Duration.zero);

      expect(prompt?.title, 'CoPaw');
      expect(prompt?.body, 'Care update available');
      expect(interaction.pendingRoute, isNull);

      await prompt!.open();
      expect(interaction.pendingRoute?.payload.inboxItemId, 'a' * 64);
      await coordinator.stop();
    },
  );

  test(
    'background and initial clicks persist before a session exists',
    () async {
      final source = FakeNotificationLifecycleSource(
        initialPayload: _payload('b'),
      );
      final interaction = FakeNotificationInteractionRepository();
      final coordinator = NotificationLifecycleCoordinator(
        source: source,
        interaction: interaction,
        onForegroundPrompt: (_) {},
      );
      await coordinator.start();
      expect(interaction.pendingRoute?.payload.inboxItemId, 'b' * 64);

      source.emitBackground(_payload('c'));
      await Future<void>.delayed(Duration.zero);
      expect(interaction.pendingRoute?.payload.inboxItemId, 'c' * 64);
      await coordinator.stop();
    },
  );

  test('malformed lifecycle payload never prompts or persists', () async {
    final source = FakeNotificationLifecycleSource();
    final interaction = FakeNotificationInteractionRepository();
    var prompts = 0;
    final coordinator = NotificationLifecycleCoordinator(
      source: source,
      interaction: interaction,
      onForegroundPrompt: (_) => prompts += 1,
    );
    await coordinator.start();
    source.emitForeground({..._payload('a'), 'extra': 'blocked'});
    await Future<void>.delayed(Duration.zero);

    expect(prompts, 0);
    expect(interaction.pendingRoute, isNull);
    await coordinator.stop();
  });

  test('delayed initial click never overwrites a newer opened click', () async {
    final source = _DelayedInitialSource();
    final interaction = FakeNotificationInteractionRepository();
    final coordinator = NotificationLifecycleCoordinator(
      source: source,
      interaction: interaction,
      onForegroundPrompt: (_) {},
    );
    final starting = coordinator.start();
    await Future<void>.delayed(Duration.zero);

    source.emitBackground(_payload('b'));
    await Future<void>.delayed(Duration.zero);
    source.initial.complete(_payload('a'));
    await starting;
    await Future<void>.delayed(Duration.zero);

    expect(interaction.pendingRoute?.payload.inboxItemId, 'b' * 64);
    await coordinator.stop();
  });

  test(
    'delayed initial click never overwrites a newer foreground prompt open',
    () async {
      final source = _DelayedInitialForegroundSource();
      final interaction = FakeNotificationInteractionRepository();
      NotificationForegroundPrompt? prompt;
      final coordinator = NotificationLifecycleCoordinator(
        source: source,
        interaction: interaction,
        onForegroundPrompt: (value) => prompt = value,
      );
      final starting = coordinator.start();
      await Future<void>.delayed(Duration.zero);

      source.emitForeground(_payload('b'));
      await Future<void>.delayed(Duration.zero);
      await prompt!.open();
      expect(interaction.pendingRoute?.payload.inboxItemId, 'b' * 64);

      source.initial.complete(_payload('a'));
      await starting;
      await Future<void>.delayed(Duration.zero);

      expect(interaction.pendingRoute?.payload.inboxItemId, 'b' * 64);
      await coordinator.stop();
    },
  );
}

final class _DelayedInitialSource implements NotificationLifecycleSource {
  final initial = Completer<Map<String, String>?>();
  final _opened = StreamController<Map<String, String>>.broadcast();

  void emitBackground(Map<String, String> payload) => _opened.add(payload);

  @override
  Stream<Map<String, String>> get foregroundMessages => const Stream.empty();

  @override
  Stream<Map<String, String>> get openedMessages => _opened.stream;

  @override
  Future<Map<String, String>?> initialMessage() => initial.future;
}

final class _DelayedInitialForegroundSource
    implements NotificationLifecycleSource {
  final initial = Completer<Map<String, String>?>();
  final _foreground = StreamController<Map<String, String>>.broadcast();

  void emitForeground(Map<String, String> payload) => _foreground.add(payload);

  @override
  Stream<Map<String, String>> get foregroundMessages => _foreground.stream;

  @override
  Stream<Map<String, String>> get openedMessages => const Stream.empty();

  @override
  Future<Map<String, String>?> initialMessage() => initial.future;
}

Map<String, String> _payload(String seed) => {
  'schemaVersion': '1',
  'destination': 'notificationInbox',
  'householdID': 'household-1',
  'inboxItemID': seed * 64,
};
