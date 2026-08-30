import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_controller.dart';
import '../bootstrap/bootstrap_repository.dart';
import '../localization/app_locale.dart';
import '../theme/copaw_theme.dart';
import 'start_view.dart';
import 'household_home_view.dart';

class BootView extends ConsumerWidget {
  const BootView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appControllerProvider);
    final snapshot = appState.value;
    final locale = snapshot?.locale ?? AppLocale.english;

    return switch (snapshot?.status) {
      AppBootStatus.ready =>
        snapshot?.session == null
            ? const StartView()
            : HouseholdHomeView(session: snapshot!.session!),
      AppBootStatus.failed => _StartupErrorView(
        locale: locale,
        failureKind: snapshot?.failureKind,
      ),
      AppBootStatus.loading || null => _LoadingView(locale: locale),
    };
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView({required this.locale});

  final AppLocale locale;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings(locale);
    return Scaffold(
      body: CopawBackground(
        child: Center(
          child: Column(
            key: const Key('boot.loading'),
            mainAxisSize: MainAxisSize.min,
            children: [
              const _PawMark(size: 68),
              const SizedBox(height: 18),
              const CircularProgressIndicator(color: CopawColors.purple),
              const SizedBox(height: 14),
              Text(
                strings.loading,
                style: const TextStyle(color: CopawColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartupErrorView extends ConsumerWidget {
  const _StartupErrorView({required this.locale, required this.failureKind});

  final AppLocale locale;
  final BootstrapFailureKind? failureKind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppStrings(locale);
    return Scaffold(
      body: CopawBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: CopawCard(
                  child: Column(
                    key: const Key('boot.error'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _PawMark(size: 68, icon: Icons.cloud_off_rounded),
                      const SizedBox(height: 18),
                      Text(
                        strings.startupFailed,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        switch (failureKind) {
                          BootstrapFailureKind.configuration =>
                            strings.configurationFailureDetail,
                          BootstrapFailureKind.network =>
                            strings.startupNetworkFailureDetail,
                          BootstrapFailureKind.permission =>
                            strings.startupPermissionFailureDetail,
                          BootstrapFailureKind.malformedData =>
                            strings.startupDataFailureDetail,
                          _ => strings.startupFailureDetail,
                        },
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: CopawColors.muted,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 22),
                      FilledButton.icon(
                        key: const Key('boot.retry'),
                        onPressed: () =>
                            ref.read(appControllerProvider.notifier).retry(),
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(strings.retry),
                      ),
                      const SizedBox(height: 12),
                      _LocaleToggle(locale: locale),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LocaleToggle extends ConsumerWidget {
  const _LocaleToggle({required this.locale});

  final AppLocale locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton.icon(
      key: const Key('locale.toggle'),
      onPressed: () {
        final next = locale == AppLocale.english
            ? AppLocale.japanese
            : AppLocale.english;
        ref.read(appControllerProvider.notifier).setLocale(next);
      },
      icon: const Icon(Icons.language_rounded),
      label: Text(locale == AppLocale.english ? '日本語' : 'English'),
    );
  }
}

class _PawMark extends StatelessWidget {
  const _PawMark({required this.size, this.icon = Icons.pets_rounded});

  final double size;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.32),
        boxShadow: const [
          BoxShadow(
            color: Color(0x267363E8),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Icon(icon, color: CopawColors.purple, size: size * 0.44),
    );
  }
}
