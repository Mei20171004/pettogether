import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config/app_config.dart';
import 'l10n/l10n.dart';
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

class _PetTogetherAppState extends State<PetTogetherApp> {
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
  String? _lastInvitationLink;

  @override
  void initState() {
    super.initState();
    _store = CareStore(
      widget.service,
      notificationService: widget.notifications,
    );
    _initializeAppLinks();
  }

  Future<void> _initializeAppLinks() async {
    try {
      final appLinks = AppLinks();
      final initialLink = await appLinks.getInitialLink();
      if (initialLink != null) await _handleAppLink(initialLink);
      _appLinkSubscription = appLinks.uriLinkStream.listen((uri) {
        unawaited(_handleAppLink(uri));
      });
    } catch (_) {
      // Deep links are unavailable (e.g. in widget tests or on desktop);
      // invitation links can still be pasted or scanned in the app.
    }
  }

  Future<void> _handleAppLink(Uri uri) async {
    final value = uri.toString();
    if (_lastInvitationLink == value) return;
    _lastInvitationLink = value;
    await _store.handleInvitationLink(uri);
  }

  @override
  void dispose() {
    _appLinkSubscription?.cancel();
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
        home: const AuthGate(),
      ),
    );
  }
}
