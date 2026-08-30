import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app_controller.dart';
import 'localization/app_locale.dart';
import 'theme/copaw_theme.dart';
import 'views/boot_view.dart';
import 'views/notification_lifecycle_host.dart';

class CopawApp extends ConsumerStatefulWidget {
  const CopawApp({super.key});

  @override
  ConsumerState<CopawApp> createState() => _CopawAppState();
}

class _CopawAppState extends ConsumerState<CopawApp> {
  late final GoRouter _router = GoRouter(
    routes: [GoRoute(path: '/', builder: (context, state) => const BootView())],
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(appControllerProvider).value;
    final locale = snapshot?.locale ?? AppLocale.english;

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'CoPaw',
      theme: buildCopawTheme(),
      locale: locale.locale,
      supportedLocales: AppLocale.values.map((item) => item.locale),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) =>
          NotificationLifecycleHost(child: child ?? const SizedBox.shrink()),
      routerConfig: _router,
    );
  }
}
