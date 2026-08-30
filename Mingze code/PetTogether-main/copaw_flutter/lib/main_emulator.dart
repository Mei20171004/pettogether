import 'package:flutter/material.dart';

import 'main.dart' as production;
import 'src/bootstrap/bootstrap_repository.dart';
import 'src/bootstrap/firebase_emulator_configuration.dart';
import 'src/data/notification_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureLocalFirebaseEmulators();

  production.runFirebaseCopawApp(
    bootstrapRepository: const _ReadyFirebaseBootstrapRepository(),
    notificationRepository: const _LocalNotificationRepository(),
  );
}

final class _ReadyFirebaseBootstrapRepository implements BootstrapRepository {
  const _ReadyFirebaseBootstrapRepository();

  @override
  Future<BootstrapResult> initialize() async => BootstrapResult.noHousehold;
}

final class _LocalNotificationRepository implements NotificationRepository {
  const _LocalNotificationRepository();

  @override
  Future<NotificationPermissionStatus> configure(String householdId) async =>
      NotificationPermissionStatus.unsupported;

  @override
  Future<NotificationPermissionStatus> requestPermission(
    String householdId,
  ) async => NotificationPermissionStatus.unsupported;

  @override
  Future<void> disable() async {}

  @override
  Future<void> openSettings() async {}

  @override
  Future<void> stop() async {}
}
