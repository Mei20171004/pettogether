import 'dart:async';

import 'package:copaw_flutter/src/data/firebase_notification_repository.dart';
import 'package:copaw_flutter/src/data/notification_repository.dart';
import 'package:copaw_flutter/src/domain/notification_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'authorized configure registers and refreshes without exposing token',
    () async {
      final gateway = _Gateway(
        statusValue: NotificationPermissionStatus.authorized,
        tokenValue: 'secret-token-a',
      );
      final repository = FirebaseNotificationRepository(gateway: gateway);

      expect(
        await repository.configure('home-1'),
        NotificationPermissionStatus.authorized,
      );
      gateway.refresh.add('secret-token-b');
      await Future<void>.delayed(Duration.zero);

      expect(gateway.registrations, [
        ('home-1', 'secret-token-a'),
        ('home-1', 'secret-token-b'),
      ]);
      expect(gateway.enabledChanges, isEmpty);
      expect(gateway.foregroundConfigurationCalls, 1);
      await repository.stop();
      await gateway.close();
    },
  );

  test(
    'denied permission disables the installation and can open settings',
    () async {
      final gateway = _Gateway(
        statusValue: NotificationPermissionStatus.notDetermined,
        requestedValue: NotificationPermissionStatus.denied,
      );
      final repository = FirebaseNotificationRepository(gateway: gateway);

      expect(
        await repository.requestPermission('home-1'),
        NotificationPermissionStatus.denied,
      );
      await repository.openSettings();

      expect(gateway.enabledChanges, [false]);
      expect(gateway.settingsCalls, 1);
      await gateway.close();
    },
  );

  test('missing APNs readiness is visible and waits for retry', () async {
    final gateway = _Gateway(
      statusValue: NotificationPermissionStatus.authorized,
      tokenReady: false,
      tokenValue: 'secret-token-a',
    );
    final repository = FirebaseNotificationRepository(gateway: gateway);

    expect(
      await repository.configure('home-1'),
      NotificationPermissionStatus.unavailable,
    );

    expect(gateway.registrations, isEmpty);
    await repository.stop();
    await gateway.close();
  });

  test('denied configure never listens for token refresh', () async {
    final gateway = _Gateway(statusValue: NotificationPermissionStatus.denied);
    final repository = FirebaseNotificationRepository(gateway: gateway);

    expect(
      await repository.configure('home-1'),
      NotificationPermissionStatus.denied,
    );
    gateway.refresh.add('secret-token');
    await Future<void>.delayed(Duration.zero);

    expect(gateway.enabledChanges, [false]);
    expect(gateway.registrations, isEmpty);
    await gateway.close();
  });

  test('disable is serialized after an in-flight token registration', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    final gateway = _Gateway(
      statusValue: NotificationPermissionStatus.authorized,
      tokenValue: 'secret-token-a',
      registerGate: gate,
      registerStarted: started,
    );
    final repository = FirebaseNotificationRepository(gateway: gateway);

    final configure = repository.configure('home-1');
    await started.future;
    final disable = repository.disable();
    gate.complete();
    await Future.wait([configure, disable]);

    expect(gateway.mutationLog, ['register', 'enabled:false']);
    await gateway.close();
  });

  test(
    'stop cancels refresh and disable turns off this installation',
    () async {
      final gateway = _Gateway(
        statusValue: NotificationPermissionStatus.authorized,
        tokenValue: 'secret-token-a',
      );
      final repository = FirebaseNotificationRepository(gateway: gateway);
      await repository.configure('home-1');

      await repository.disable();
      gateway.refresh.add('secret-token-b');
      await Future<void>.delayed(Duration.zero);

      expect(gateway.enabledChanges, [false]);
      expect(gateway.registrations, [('home-1', 'secret-token-a')]);
      await gateway.close();
    },
  );

  test('provider errors are visible without raw diagnostics', () async {
    final gateway = _Gateway(
      statusValue: NotificationPermissionStatus.authorized,
      statusError: StateError('secret-token'),
    );
    final repository = FirebaseNotificationRepository(gateway: gateway);

    expect(
      await repository.configure('home-1'),
      NotificationPermissionStatus.error,
    );
    await gateway.close();
  });

  test('device snapshot keeps OS permission separate from readiness', () async {
    final gateway = _Gateway(
      statusValue: NotificationPermissionStatus.authorized,
      tokenValue: 'secret-token-a',
      installationHashValue: 'a' * 64,
    );
    final repository = FirebaseNotificationRepository(gateway: gateway);

    final snapshot = await repository.configureDevice('home-1');

    expect(snapshot.osPermission, NotificationOsPermission.authorized);
    expect(
      snapshot.installationReadiness,
      NotificationInstallationReadiness.ready,
    );
    expect(snapshot.installationHash, 'a' * 64);
    await repository.stop();
    await gateway.close();
  });

  test(
    'authorized OS with missing APNs token is not labelled disabled',
    () async {
      final gateway = _Gateway(
        statusValue: NotificationPermissionStatus.authorized,
        tokenReady: false,
        tokenValue: 'secret-token-a',
        installationHashValue: 'b' * 64,
      );
      final repository = FirebaseNotificationRepository(gateway: gateway);

      final snapshot = await repository.configureDevice('home-1');

      expect(snapshot.osPermission, NotificationOsPermission.authorized);
      expect(
        snapshot.installationReadiness,
        NotificationInstallationReadiness.unavailable,
      );
      expect(snapshot.installationHash, 'b' * 64);
      await repository.stop();
      await gateway.close();
    },
  );
}

final class _Gateway implements NotificationGateway {
  _Gateway({
    required this.statusValue,
    this.requestedValue,
    this.tokenValue,
    this.tokenReady = true,
    this.statusError,
    this.registerGate,
    this.registerStarted,
    this.installationHashValue =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
  });

  final NotificationPermissionStatus statusValue;
  final NotificationPermissionStatus? requestedValue;
  final String? tokenValue;
  final bool tokenReady;
  final Object? statusError;
  final Completer<void>? registerGate;
  final Completer<void>? registerStarted;
  final String installationHashValue;
  final refresh = StreamController<String>.broadcast();
  final registrations = <(String, String)>[];
  final enabledChanges = <bool>[];
  int settingsCalls = 0;
  int foregroundConfigurationCalls = 0;
  final mutationLog = <String>[];

  @override
  Future<NotificationPermissionStatus> status() async {
    if (statusError case final Object error) throw error;
    return statusValue;
  }

  @override
  Future<NotificationPermissionStatus> requestPermission() async =>
      requestedValue ?? statusValue;

  @override
  Future<String?> token() async => tokenValue;

  @override
  Future<bool> tokenIsReady() async => tokenReady;

  @override
  Future<void> configureForegroundPresentation() async {
    foregroundConfigurationCalls += 1;
  }

  @override
  Stream<String> get tokenRefresh => refresh.stream;

  @override
  Future<void> register(String householdId, String token) async {
    if (registerStarted != null && !registerStarted!.isCompleted) {
      registerStarted!.complete();
    }
    if (registerGate case final gate?) await gate.future;
    registrations.add((householdId, token));
    mutationLog.add('register');
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    enabledChanges.add(enabled);
    mutationLog.add('enabled:$enabled');
  }

  @override
  Future<void> openSettings() async {
    settingsCalls += 1;
  }

  @override
  Future<String> installationHash() async => installationHashValue;

  Future<void> close() => refresh.close();
}
