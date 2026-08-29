import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'l10n/l10n.dart';
import 'services/care_service.dart';
import 'services/notification_service.dart';
import 'store/care_store.dart';
import 'theme/app_theme.dart';
import 'views/auth_gate.dart';

class PetTogetherApp extends StatefulWidget {
  const PetTogetherApp({
    super.key,
    required this.language,
    required this.service,
    this.notifications,
  });

  final AppLanguage language;
  final CareService service;
  final NotificationService? notifications;

  @override
  State<PetTogetherApp> createState() => _PetTogetherAppState();
}

class _PetTogetherAppState extends State<PetTogetherApp> {
  late final CareStore _store;
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
