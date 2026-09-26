import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config/app_config.dart';
import 'l10n/l10n.dart';
import 'models/invitation_link.dart';
import 'services/care_service.dart';
import 'services/notification_service.dart';
import 'store/care_store.dart';
import 'services/entitlement_service.dart';
import 'store/pro_access.dart';
import 'store/purchase_store.dart';
import 'theme/app_theme.dart';
import 'views/auth_gate.dart';

class PetTogetherApp extends StatefulWidget {
  const PetTogetherApp({
    super.key,
    required this.language,
    required this.service,
    this.notifications,
    this.purchases,
  });

  final AppLanguage language;
  final CareService service;
  final NotificationService? notifications;

  /// Optional so widget tests can run without configuring RevenueCat.
  final PurchaseStore? purchases;

  @override
  State<PetTogetherApp> createState() => _PetTogetherAppState();
}

class _PetTogetherAppState extends State<PetTogetherApp>
    with WidgetsBindingObserver {
  late final CareStore _store;
  late final PurchaseStore _purchases =
      widget.purchases ?? PurchaseStore(apiKey: '');
  late final ProAccess _proAccess = ProAccess(
    purchases: _purchases,
    care: _store,
    entitlements: _entitlementService(),
  );

  /// Without Firebase there is no household mirror and no usage counter, so the
  /// offline mock build and the widget tests simply have no paid state to read.
  /// Touching `FirebaseFirestore.instance` before Firebase is initialized
  /// throws, which would take the whole app down on the mock fallback path.
  static EntitlementService? _entitlementService() {
    if (!AppConfig.useFirebase || Firebase.apps.isEmpty) return null;
    try {
      return EntitlementService();
    } catch (_) {
      return null;
    }
  }

  StreamSubscription<Uri>? _appLinkSubscription;
  StreamSubscription<User?>? _authSubscription;
  Future<void> _userInfoSyncQueue = Future<void>.value();
  DateTime? _observedProPurchaseAt;
  bool _observedPro = false;
  final AppLinks _appLinks = AppLinks();
  Uri? _pendingInvitationLink;
  String? _lastHandledInvitationLink;
  bool _handlingInvitationLink = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _store = CareStore(
      widget.service,
      notificationService: widget.notifications,
    );
    _observedPro = _purchases.isPro;
    _purchases.addListener(_onPurchaseStateChanged);
    if (AppConfig.useFirebase && Firebase.apps.isNotEmpty) {
      _authSubscription = FirebaseAuth.instance.authStateChanges().listen((
        user,
      ) {
        unawaited(_proAccess.refreshFreeCoupon());
        if (user != null) {
          _queueUserInfoSync(user.uid);
          unawaited(_flushPendingInvitationLink());
        }
      });
    }
    _initializeAppLinks();
  }

  void _onPurchaseStateChanged() {
    if (!AppConfig.useFirebase || Firebase.apps.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final paidAt = _purchases.proLatestPurchaseAtFor(uid);
    final isPro = _purchases.isPro;
    if (paidAt == _observedProPurchaseAt && isPro == _observedPro) return;
    _observedProPurchaseAt = paidAt;
    _observedPro = isPro;
    _queueUserInfoSync(uid);
  }

  void _queueUserInfoSync(String uid) {
    _userInfoSyncQueue = _userInfoSyncQueue.then((_) async {
      if (FirebaseAuth.instance.currentUser?.uid != uid) return;
      try {
        await EntitlementService().syncUserInfo(
          uid,
          latestProPurchaseAt: _purchases.proLatestPurchaseAtFor(uid),
        );
      } catch (error, stackTrace) {
        debugPrint('User info refresh failed: $error\n$stackTrace');
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_proAccess.refreshFreeCoupon());
      if (AppConfig.useFirebase && Firebase.apps.isNotEmpty) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) _queueUserInfoSync(uid);
      }
    }
  }

  Future<void> _initializeAppLinks() async {
    try {
      _appLinkSubscription = _appLinks.uriLinkStream.listen(
        (uri) => unawaited(_receiveAppLink(uri)),
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Invitation link stream failed: $error\n$stackTrace');
        },
      );
      final initialLink = await _appLinks.getInitialLink();
      if (initialLink != null) await _receiveAppLink(initialLink);
    } catch (error, stackTrace) {
      // Deep links are unavailable (e.g. in widget tests or on desktop);
      // invitation links can still be pasted or scanned in the app.
      debugPrint('Invitation links unavailable: $error\n$stackTrace');
    }
  }

  Future<void> _receiveAppLink(Uri uri) async {
    if (!InvitationLink.looksLikeInvitationUri(uri)) return;
    final value = uri.toString();
    if (_lastHandledInvitationLink == value ||
        _pendingInvitationLink?.toString() == value) {
      return;
    }
    _pendingInvitationLink = uri;
    await _flushPendingInvitationLink();
  }

  Future<void> _flushPendingInvitationLink() async {
    if (_handlingInvitationLink) return;
    final uri = _pendingInvitationLink;
    if (uri == null) return;
    if (AppConfig.useFirebase &&
        Firebase.apps.isNotEmpty &&
        FirebaseAuth.instance.currentUser == null) {
      return;
    }

    _handlingInvitationLink = true;
    try {
      await _store.restoreSession();
      final succeeded = await _store.handleInvitationLink(uri);
      if (_pendingInvitationLink == uri) {
        if (succeeded) _lastHandledInvitationLink = uri.toString();
        _pendingInvitationLink = null;
      }
    } finally {
      final hasAnotherPendingLink =
          _pendingInvitationLink != null && _pendingInvitationLink != uri;
      _handlingInvitationLink = false;
      if (hasAnotherPendingLink) unawaited(_flushPendingInvitationLink());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _appLinkSubscription?.cancel();
    _authSubscription?.cancel();
    _purchases.removeListener(_onPurchaseStateChanged);
    _store.dispose();
    widget.notifications?.dispose();
    _proAccess.dispose();
    _purchases.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CareStore>.value(value: _store),
        ChangeNotifierProvider<AppLanguageStore>(
          create: (_) => AppLanguageStore(widget.language),
        ),
        ChangeNotifierProvider<PurchaseStore>.value(value: _purchases),
        ChangeNotifierProvider<ProAccess>.value(value: _proAccess),
      ],
      child: MaterialApp(
        title: 'pettogether',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        builder: (context, child) => AnnotatedRegion(
          value: petSystemUiOverlayStyle,
          child: child ?? const SizedBox.shrink(),
        ),
        home: const AuthGate(),
      ),
    );
  }
}
