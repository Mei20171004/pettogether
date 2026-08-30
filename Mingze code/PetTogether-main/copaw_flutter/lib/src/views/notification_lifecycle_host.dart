import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/notification_center_repository.dart';
import '../data/notification_lifecycle.dart';
import '../localization/app_locale.dart';

class NotificationLifecycleHost extends ConsumerStatefulWidget {
  const NotificationLifecycleHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<NotificationLifecycleHost> createState() =>
      _NotificationLifecycleHostState();
}

class _NotificationLifecycleHostState
    extends ConsumerState<NotificationLifecycleHost> {
  NotificationLifecycleCoordinator? _coordinator;
  String? _languageCode;
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final languageCode = Localizations.localeOf(context).languageCode;
    if (_languageCode == languageCode) return;
    _languageCode = languageCode;
    unawaited(_restart(languageCode));
  }

  Future<void> _restart(String languageCode) async {
    await _coordinator?.stop();
    if (!mounted || _languageCode != languageCode) return;
    final strings = AppStrings(AppLocale.fromLanguageCode(languageCode));
    final coordinator = NotificationLifecycleCoordinator(
      source: ref.read(notificationLifecycleSourceProvider),
      interaction: ref.read(notificationInteractionRepositoryProvider),
      genericBody: strings.notificationForegroundBody,
      onPendingRoutePersisted: () {
        ref.read(notificationPendingRouteSignalProvider.notifier).signal();
      },
      onForegroundPrompt: _showPrompt,
    );
    _coordinator = coordinator;
    await coordinator.start();
  }

  void _showPrompt(NotificationForegroundPrompt prompt) {
    if (!mounted) return;
    final messenger = _messengerKey.currentState;
    if (messenger == null) return;
    final strings = AppStrings(
      AppLocale.fromLanguageCode(Localizations.localeOf(context).languageCode),
    );
    messenger
      ..hideCurrentMaterialBanner()
      ..showMaterialBanner(
        MaterialBanner(
          content: Semantics(
            liveRegion: true,
            label: '${prompt.title}. ${prompt.body}',
            child: ExcludeSemantics(
              child: Text('${prompt.title}\n${prompt.body}'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: messenger.hideCurrentMaterialBanner,
              child: Text(strings.cancel),
            ),
            TextButton(
              key: const Key('notifications.foreground.open'),
              onPressed: () async {
                await prompt.open();
                messenger.hideCurrentMaterialBanner();
              },
              child: Text(strings.notificationOpenReminder),
            ),
          ],
        ),
      );
  }

  @override
  void dispose() {
    unawaited(_coordinator?.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ScaffoldMessenger(key: _messengerKey, child: widget.child);
}
