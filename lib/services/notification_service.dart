import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'firebase_care_service.dart';

const _channelId = 'copaw_care';
const _channelName = 'Care updates';
const _channelDescription = 'Task handoffs and pet-care reminders.';

/// Must remain a top-level entry point so Android can initialize Firebase
/// before delivering a background FCM message.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

enum NotificationPermissionState {
  unavailable,
  notDetermined,
  denied,
  authorized,
  provisional,
}

extension NotificationPermissionStateX on NotificationPermissionState {
  bool get isGranted =>
      this == NotificationPermissionState.authorized ||
      this == NotificationPermissionState.provisional;
}

/// Owns native notification permission, foreground presentation and FCM token
/// registration. FCM tokens are written beneath the current member document so
/// household members cannot read one another's device tokens.
class NotificationService {
  NotificationService(
    this._careService, {
    FirebaseMessaging? messaging,
    FlutterLocalNotificationsPlugin? localNotifications,
  }) : _messaging = messaging ?? FirebaseMessaging.instance,
       _localNotifications =
           localNotifications ?? FlutterLocalNotificationsPlugin();

  final FirebaseCareService _careService;
  final FirebaseMessaging _messaging;
  final FlutterLocalNotificationsPlugin _localNotifications;

  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  String? _householdId;
  String? _caregiverId;
  String? _storedToken;
  bool _pushEnabled = false;
  bool _initialized = false;

  bool get _isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> initialize() async {
    if (!_isSupported || _initialized) return;
    _initialized = true;

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_copaw'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _localNotifications.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (_) {},
    );

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    // FCM has no foreground banner by default on Android. On iOS we use the
    // same local-notification path, preventing duplicate foreground banners.
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );
    _foregroundSubscription = FirebaseMessaging.onMessage.listen(
      _showForegroundNotification,
    );
    _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen((_) {});
    _tokenSubscription = _messaging.onTokenRefresh.listen((token) {
      unawaited(_persistToken(token));
    });
  }

  Future<NotificationPermissionState> currentPermission() async {
    if (!_isSupported) return NotificationPermissionState.unavailable;
    return _permissionState(await _messaging.getNotificationSettings());
  }

  Future<NotificationPermissionState> requestAndSync({
    required String householdId,
    required String caregiverId,
  }) async {
    if (!_isSupported) return NotificationPermissionState.unavailable;
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    final permission = _permissionState(settings);
    if (permission.isGranted) {
      _householdId = householdId;
      _caregiverId = caregiverId;
      _pushEnabled = true;
      await _careService.setNotificationsEnabled(
        householdID: householdId,
        caregiverID: caregiverId,
        enabled: true,
      );
      await syncForMember(householdId: householdId, caregiverId: caregiverId);
    } else {
      _pushEnabled = false;
      await _careService.setNotificationsEnabled(
        householdID: householdId,
        caregiverID: caregiverId,
        enabled: false,
      );
    }
    return permission;
  }

  /// Restores the per-device opt-in after an app restart without prompting.
  Future<bool> prepareMember({
    required String householdId,
    required String caregiverId,
  }) async {
    if (!_isSupported) return false;
    _householdId = householdId;
    _caregiverId = caregiverId;
    _pushEnabled = await _careService.notificationsEnabled(
      householdID: householdId,
      caregiverID: caregiverId,
    );
    if (_pushEnabled && (await currentPermission()).isGranted) {
      await syncForMember(householdId: householdId, caregiverId: caregiverId);
    }
    return _pushEnabled;
  }

  Future<void> syncForMember({
    required String householdId,
    required String caregiverId,
  }) async {
    if (!_isSupported) return;
    _householdId = householdId;
    _caregiverId = caregiverId;
    if (!_pushEnabled || !(await currentPermission()).isGranted) return;

    // On iOS the APNs token must arrive before FCM can issue an FCM token.
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      for (var attempt = 0; attempt < 10; attempt++) {
        if (await _messaging.getAPNSToken() != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      if (await _messaging.getAPNSToken() == null) return;
    }

    final token = await _messaging.getToken();
    if (token != null) await _persistToken(token);
  }

  Future<void> disableForMember({
    required String householdId,
    required String caregiverId,
  }) async {
    if (!_isSupported) return;
    await _careService.setNotificationsEnabled(
      householdID: householdId,
      caregiverID: caregiverId,
      enabled: false,
    );
    final token = _storedToken ?? await _messaging.getToken();
    if (token != null) {
      await _careService.removePushToken(
        householdID: householdId,
        caregiverID: caregiverId,
        token: token,
      );
    }
    await _messaging.deleteToken();
    _storedToken = null;
    _pushEnabled = false;
    _householdId = null;
    _caregiverId = null;
  }

  Future<void> _persistToken(String token) async {
    final householdId = _householdId;
    final caregiverId = _caregiverId;
    if (householdId == null || caregiverId == null || token == _storedToken) {
      return;
    }
    await _careService.savePushToken(
      householdID: householdId,
      caregiverID: caregiverId,
      token: token,
      platform: defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
    );
    _storedToken = token;
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    final title = notification?.title ?? message.data['title'] ?? 'copaw';
    final body =
        notification?.body ??
        message.data['body'] ??
        'You have a new pet-care update.';
    await _localNotifications.show(
      id: message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: message.data.isEmpty ? null : message.data.toString(),
    );
  }

  NotificationPermissionState _permissionState(
    NotificationSettings settings,
  ) => switch (settings.authorizationStatus) {
    AuthorizationStatus.notDetermined =>
      NotificationPermissionState.notDetermined,
    AuthorizationStatus.denied => NotificationPermissionState.denied,
    AuthorizationStatus.authorized => NotificationPermissionState.authorized,
    AuthorizationStatus.provisional => NotificationPermissionState.provisional,
  };

  void dispose() {
    unawaited(_tokenSubscription?.cancel() ?? Future<void>.value());
    unawaited(_foregroundSubscription?.cancel() ?? Future<void>.value());
    unawaited(_openedSubscription?.cancel() ?? Future<void>.value());
  }
}
