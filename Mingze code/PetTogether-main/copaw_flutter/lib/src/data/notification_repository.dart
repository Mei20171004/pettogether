import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/notification_models.dart';

enum NotificationPermissionStatus {
  notDetermined,
  denied,
  authorized,
  provisional,
  unavailable,
  unsupported,
  error,
}

abstract interface class NotificationRepository {
  Future<NotificationPermissionStatus> configure(String householdId);
  Future<NotificationPermissionStatus> requestPermission(String householdId);
  Future<void> openSettings();
  Future<void> disable();
  Future<void> stop();
}

final class NotificationDeviceSnapshot {
  const NotificationDeviceSnapshot({
    required this.osPermission,
    required this.installationReadiness,
    required this.installationHash,
  });

  final NotificationOsPermission osPermission;
  final NotificationInstallationReadiness installationReadiness;
  final String? installationHash;
}

abstract interface class NotificationDeviceRepository {
  Future<NotificationDeviceSnapshot> configureDevice(String householdId);
  Future<NotificationDeviceSnapshot> requestDevicePermission(
    String householdId,
  );
}

final class ProviderDisabledNotificationDeviceRepository
    implements NotificationDeviceRepository {
  const ProviderDisabledNotificationDeviceRepository();

  @override
  Future<NotificationDeviceSnapshot> configureDevice(
    String householdId,
  ) async => _snapshot;

  @override
  Future<NotificationDeviceSnapshot> requestDevicePermission(
    String householdId,
  ) async => _snapshot;

  static const _snapshot = NotificationDeviceSnapshot(
    osPermission: NotificationOsPermission.unsupported,
    installationReadiness: NotificationInstallationReadiness.unsupported,
    installationHash: null,
  );
}

final class LegacyNotificationDeviceRepository
    implements NotificationDeviceRepository {
  const LegacyNotificationDeviceRepository(this.repository);

  final NotificationRepository repository;

  @override
  Future<NotificationDeviceSnapshot> configureDevice(
    String householdId,
  ) async => _snapshot(await repository.configure(householdId));

  @override
  Future<NotificationDeviceSnapshot> requestDevicePermission(
    String householdId,
  ) async => _snapshot(await repository.requestPermission(householdId));

  static NotificationDeviceSnapshot _snapshot(
    NotificationPermissionStatus status,
  ) => NotificationDeviceSnapshot(
    osPermission: switch (status) {
      NotificationPermissionStatus.notDetermined =>
        NotificationOsPermission.notDetermined,
      NotificationPermissionStatus.denied => NotificationOsPermission.denied,
      NotificationPermissionStatus.authorized =>
        NotificationOsPermission.authorized,
      NotificationPermissionStatus.provisional =>
        NotificationOsPermission.provisional,
      NotificationPermissionStatus.unsupported =>
        NotificationOsPermission.unsupported,
      NotificationPermissionStatus.unavailable ||
      NotificationPermissionStatus.error => NotificationOsPermission.error,
    },
    installationReadiness: switch (status) {
      NotificationPermissionStatus.authorized ||
      NotificationPermissionStatus.provisional =>
        NotificationInstallationReadiness.registering,
      NotificationPermissionStatus.denied ||
      NotificationPermissionStatus.notDetermined =>
        NotificationInstallationReadiness.disabled,
      NotificationPermissionStatus.unavailable =>
        NotificationInstallationReadiness.unavailable,
      NotificationPermissionStatus.unsupported =>
        NotificationInstallationReadiness.unsupported,
      NotificationPermissionStatus.error =>
        NotificationInstallationReadiness.error,
    },
    installationHash: null,
  );
}

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  throw StateError(
    'NotificationRepository must be provided at the app boundary.',
  );
});

final notificationDeviceRepositoryProvider =
    Provider<NotificationDeviceRepository>((ref) {
      throw StateError(
        'NotificationDeviceRepository must be provided at the app boundary.',
      );
    });
