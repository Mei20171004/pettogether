import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:app_settings/app_settings.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/notification_models.dart';
import 'notification_repository.dart';

abstract interface class NotificationGateway {
  Future<NotificationPermissionStatus> status();
  Future<NotificationPermissionStatus> requestPermission();
  Future<String?> token();
  Future<bool> tokenIsReady();
  Future<void> configureForegroundPresentation();
  Stream<String> get tokenRefresh;
  Future<void> register(String householdId, String token);
  Future<void> setEnabled(bool enabled);
  Future<String> installationHash();
  Future<void> openSettings();
}

final class FirebaseNotificationRepository
    implements NotificationRepository, NotificationDeviceRepository {
  FirebaseNotificationRepository({NotificationGateway? gateway})
    : _gateway = gateway ?? FirebaseNotificationGateway();

  final NotificationGateway _gateway;
  StreamSubscription<String>? _tokenRefresh;
  String? _householdId;
  int _generation = 0;
  Future<void> _pendingMutation = Future<void>.value();

  @override
  Future<NotificationPermissionStatus> configure(String householdId) async {
    if (!_validId(householdId)) return NotificationPermissionStatus.error;
    final generation = ++_generation;
    _householdId = householdId;
    try {
      final status = await _gateway.status();
      await _tokenRefresh?.cancel();
      _tokenRefresh = null;
      final effectiveStatus = await _applyStatus(householdId, status);
      if (generation == _generation && _canRegister(status)) {
        _listenForTokenRefresh(householdId, generation);
      }
      return effectiveStatus;
    } on UnsupportedError {
      return NotificationPermissionStatus.unsupported;
    } on Object {
      return NotificationPermissionStatus.error;
    }
  }

  @override
  Future<NotificationPermissionStatus> requestPermission(
    String householdId,
  ) async {
    if (!_validId(householdId)) return NotificationPermissionStatus.error;
    final generation = ++_generation;
    _householdId = householdId;
    try {
      final status = await _gateway.requestPermission();
      await _tokenRefresh?.cancel();
      _tokenRefresh = null;
      final effectiveStatus = await _applyStatus(householdId, status);
      if (generation == _generation && _canRegister(status)) {
        _listenForTokenRefresh(householdId, generation);
      }
      return effectiveStatus;
    } on UnsupportedError {
      return NotificationPermissionStatus.unsupported;
    } on Object {
      return NotificationPermissionStatus.error;
    }
  }

  @override
  Future<NotificationDeviceSnapshot> configureDevice(String householdId) =>
      _configureDevice(householdId, request: false);

  @override
  Future<NotificationDeviceSnapshot> requestDevicePermission(
    String householdId,
  ) => _configureDevice(householdId, request: true);

  Future<NotificationDeviceSnapshot> _configureDevice(
    String householdId, {
    required bool request,
  }) async {
    if (!_validId(householdId)) {
      return const NotificationDeviceSnapshot(
        osPermission: NotificationOsPermission.error,
        installationReadiness: NotificationInstallationReadiness.error,
        installationHash: null,
      );
    }
    final generation = ++_generation;
    _householdId = householdId;
    String? installationHash;
    try {
      installationHash = await _gateway.installationHash();
      final permission = request
          ? await _gateway.requestPermission()
          : await _gateway.status();
      await _tokenRefresh?.cancel();
      _tokenRefresh = null;
      final readiness = await _applyDeviceStatus(householdId, permission);
      if (generation == _generation && _canRegister(permission)) {
        _listenForTokenRefresh(householdId, generation);
      }
      return NotificationDeviceSnapshot(
        osPermission: _osPermission(permission),
        installationReadiness: readiness,
        installationHash: installationHash,
      );
    } on UnsupportedError {
      return NotificationDeviceSnapshot(
        osPermission: NotificationOsPermission.unsupported,
        installationReadiness: NotificationInstallationReadiness.unsupported,
        installationHash: installationHash,
      );
    } on Object {
      return NotificationDeviceSnapshot(
        osPermission: NotificationOsPermission.error,
        installationReadiness: NotificationInstallationReadiness.error,
        installationHash: installationHash,
      );
    }
  }

  Future<NotificationInstallationReadiness> _applyDeviceStatus(
    String householdId,
    NotificationPermissionStatus status,
  ) async {
    if (status == NotificationPermissionStatus.denied) {
      await _serialize(() => _gateway.setEnabled(false));
      return NotificationInstallationReadiness.disabled;
    }
    if (status == NotificationPermissionStatus.unsupported) {
      return NotificationInstallationReadiness.unsupported;
    }
    if (!_canRegister(status)) {
      return NotificationInstallationReadiness.disabled;
    }
    await _gateway.configureForegroundPresentation();
    if (!await _gateway.tokenIsReady()) {
      return NotificationInstallationReadiness.unavailable;
    }
    final token = await _gateway.token();
    if (token == null || token.isEmpty) {
      return NotificationInstallationReadiness.unavailable;
    }
    await _serialize(() => _gateway.register(householdId, token));
    return NotificationInstallationReadiness.ready;
  }

  Future<NotificationPermissionStatus> _applyStatus(
    String householdId,
    NotificationPermissionStatus status,
  ) async {
    if (_canRegister(status)) {
      await _gateway.configureForegroundPresentation();
      if (!await _gateway.tokenIsReady()) {
        return NotificationPermissionStatus.unavailable;
      }
      final token = await _gateway.token();
      if (token == null || token.isEmpty) {
        return NotificationPermissionStatus.unavailable;
      }
      await _serialize(() => _gateway.register(householdId, token));
    } else if (status == NotificationPermissionStatus.denied) {
      await _serialize(() => _gateway.setEnabled(false));
    }
    return status;
  }

  void _listenForTokenRefresh(String householdId, int generation) {
    _tokenRefresh = _gateway.tokenRefresh.listen((token) {
      unawaited(
        _serialize(() async {
          if (generation != _generation || _householdId != householdId) return;
          try {
            await _gateway.register(householdId, token);
          } on Object {
            // The status UI can retry configuration. Never log the token.
          }
        }),
      );
    }, onError: (_) {});
  }

  Future<void> _serialize(Future<void> Function() mutation) {
    final result = _pendingMutation.then((_) => mutation());
    _pendingMutation = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  @override
  Future<void> openSettings() => _gateway.openSettings();

  @override
  Future<void> disable() async {
    ++_generation;
    _householdId = null;
    await _tokenRefresh?.cancel();
    _tokenRefresh = null;
    await _serialize(() => _gateway.setEnabled(false));
  }

  @override
  Future<void> stop() async {
    ++_generation;
    _householdId = null;
    await _tokenRefresh?.cancel();
    _tokenRefresh = null;
  }

  static bool _canRegister(NotificationPermissionStatus status) =>
      status == NotificationPermissionStatus.authorized ||
      status == NotificationPermissionStatus.provisional;

  static bool _validId(String value) =>
      value.isNotEmpty && value.length <= 200 && !value.contains('/');

  static NotificationOsPermission _osPermission(
    NotificationPermissionStatus status,
  ) => switch (status) {
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
  };
}

final class FirebaseNotificationGateway implements NotificationGateway {
  FirebaseNotificationGateway({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseMessaging? messaging,
    SharedPreferencesAsync? preferences,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _messaging = messaging ?? FirebaseMessaging.instance,
       _preferences = preferences ?? SharedPreferencesAsync();

  static const _installationKey = 'copaw.notificationInstallationID';
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseMessaging _messaging;
  final SharedPreferencesAsync _preferences;

  @override
  Future<NotificationPermissionStatus> status() async =>
      _status((await _messaging.getNotificationSettings()).authorizationStatus);

  @override
  Future<NotificationPermissionStatus> requestPermission() async => _status(
    (await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    )).authorizationStatus,
  );

  @override
  Future<String?> token() => _messaging.getToken();

  @override
  Future<bool> tokenIsReady() async =>
      !Platform.isIOS || await _messaging.getAPNSToken() != null;

  @override
  Future<void> configureForegroundPresentation() =>
      _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

  @override
  Stream<String> get tokenRefresh => _messaging.onTokenRefresh;

  @override
  Future<void> register(String householdId, String token) async {
    final user = _auth.currentUser;
    if (user == null || token.isEmpty || token.length > 4096) return;
    final reference = await _reference(user.uid);
    await _firestore.runTransaction((transaction) async {
      final current = await transaction.get(reference);
      transaction.set(reference, {
        'token': token,
        'householdID': householdId,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'enabled': true,
        'createdAt':
            current.data()?['createdAt'] ?? FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final reference = await _reference(user.uid);
    final current = await reference.get();
    if (current.exists) {
      await reference.update({
        'enabled': enabled,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  @override
  Future<String> installationHash() async =>
      sha256.convert(utf8.encode(await _installationId())).toString();

  Future<DocumentReference<Map<String, dynamic>>> _reference(String uid) async {
    final documentId = await installationHash();
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('notificationTokens')
        .doc(documentId);
  }

  Future<String> _installationId() async {
    final existing = await _preferences.getString(_installationKey);
    if (existing != null && existing.length >= 32) return existing;
    final random = Random.secure();
    final created = List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await _preferences.setString(_installationKey, created);
    return created;
  }

  @override
  Future<void> openSettings() => AppSettings.openAppSettings();

  static NotificationPermissionStatus _status(
    AuthorizationStatus status,
  ) => switch (status) {
    AuthorizationStatus.notDetermined =>
      NotificationPermissionStatus.notDetermined,
    AuthorizationStatus.denied => NotificationPermissionStatus.denied,
    AuthorizationStatus.authorized => NotificationPermissionStatus.authorized,
    AuthorizationStatus.provisional => NotificationPermissionStatus.provisional,
  };
}
