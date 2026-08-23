import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'l10n/l10n.dart';
import 'services/care_service.dart';
import 'store/care_store.dart';
import 'theme/app_theme.dart';
import 'views/auth_gate.dart';

class CopawApp extends StatelessWidget {
  const CopawApp({super.key, required this.language, required this.service});

  final AppLanguage language;
  final CareService service;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CareStore>(
          create: (_) => CareStore(service),
        ),
        ChangeNotifierProvider<AppLanguageStore>(
          create: (_) => AppLanguageStore(language),
        ),
      ],
      child: MaterialApp(
        title: 'copaw',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const AuthGate(),
      ),
    );
  }
}
