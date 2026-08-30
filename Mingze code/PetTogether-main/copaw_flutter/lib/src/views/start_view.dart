import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_controller.dart';
import '../data/household_repository.dart';
import '../data/local_timezone_repository.dart';
import '../localization/app_locale.dart';
import '../theme/copaw_theme.dart';

enum _SetupMode { create, join }

class StartView extends ConsumerStatefulWidget {
  const StartView({super.key});

  @override
  ConsumerState<StartView> createState() => _StartViewState();
}

class _StartViewState extends ConsumerState<StartView> {
  _SetupMode mode = _SetupMode.create;
  final caregiverController = TextEditingController();
  final householdController = TextEditingController();
  final petController = TextEditingController();
  final inviteController = TextEditingController();
  bool submitting = false;
  String? errorMessage;

  @override
  void dispose() {
    caregiverController.dispose();
    householdController.dispose();
    petController.dispose();
    inviteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale =
        ref.watch(appControllerProvider).value?.locale ?? AppLocale.english;
    final strings = AppStrings(locale);

    return Scaffold(
      body: CopawBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            key: const Key('start.shell'),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: _LanguageMenu(locale: locale, strings: strings),
                    ),
                    const SizedBox(height: 8),
                    _Hero(strings: strings),
                    const SizedBox(height: 22),
                    CopawCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SegmentedButton<_SetupMode>(
                            segments: [
                              ButtonSegment(
                                value: _SetupMode.create,
                                label: Text(strings.createHome),
                                icon: const Icon(Icons.home_rounded),
                              ),
                              ButtonSegment(
                                value: _SetupMode.join,
                                label: Text(strings.joinHome),
                                icon: const Icon(Icons.group_add_rounded),
                              ),
                            ],
                            selected: {mode},
                            onSelectionChanged: (selection) {
                              setState(() => mode = selection.single);
                            },
                          ),
                          const SizedBox(height: 20),
                          _Field(
                            key: const Key('start.caregiverName'),
                            label: strings.yourName,
                            hint: strings.yourNameHint,
                            icon: Icons.person_rounded,
                            controller: caregiverController,
                            maximumLength: 50,
                          ),
                          const SizedBox(height: 14),
                          if (mode == _SetupMode.create) ...[
                            _Field(
                              key: const Key('start.householdName'),
                              label: strings.household,
                              hint: strings.householdHint,
                              icon: Icons.home_rounded,
                              controller: householdController,
                              maximumLength: 60,
                            ),
                            const SizedBox(height: 14),
                            _Field(
                              key: const Key('start.petName'),
                              label: strings.yourPet,
                              hint: strings.petHint,
                              icon: Icons.pets_rounded,
                              controller: petController,
                              maximumLength: 60,
                            ),
                          ] else ...[
                            _Field(
                              key: const Key('start.inviteCode'),
                              label: strings.inviteCode,
                              hint: strings.inviteCodeHint,
                              icon: Icons.group_rounded,
                              controller: inviteController,
                              maximumLength: 6,
                              capitalization: TextCapitalization.characters,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              strings.inviteHelp,
                              style: const TextStyle(
                                color: CopawColors.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                          if (errorMessage != null) ...[
                            const SizedBox(height: 14),
                            Text(
                              errorMessage!,
                              key: const Key('start.error'),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton.icon(
                        key: const Key('start.primaryAction'),
                        onPressed: submitting ? null : () => _submit(strings),
                        icon: submitting
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.arrow_forward_rounded),
                        label: Text(
                          submitting
                              ? mode == _SetupMode.create
                                    ? strings.creatingHousehold
                                    : strings.joiningHousehold
                              : mode == _SetupMode.create
                              ? strings.createHousehold
                              : strings.joinHousehold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      strings.footer,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: CopawColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit(AppStrings strings) async {
    final caregiverName = caregiverController.text.trim();
    final missingCreateField =
        householdController.text.trim().isEmpty ||
        petController.text.trim().isEmpty;
    if (caregiverName.isEmpty ||
        (mode == _SetupMode.create && missingCreateField) ||
        (mode == _SetupMode.join && inviteController.text.trim().isEmpty)) {
      setState(() => errorMessage = strings.requiredFields);
      return;
    }

    setState(() {
      submitting = true;
      errorMessage = null;
    });
    try {
      final controller = ref.read(appControllerProvider.notifier);
      if (mode == _SetupMode.create) {
        final timezone = await ref
            .read(localTimeZoneRepositoryProvider)
            .loadIdentifier();
        await controller.createHousehold(
          householdName: householdController.text,
          petName: petController.text,
          caregiverName: caregiverName,
          timeZoneIdentifier: timezone,
        );
      } else {
        await controller.joinHousehold(
          inviteCode: inviteController.text,
          caregiverName: caregiverName,
        );
      }
    } on HouseholdRepositoryException catch (error) {
      if (!mounted) return;
      setState(
        () => errorMessage = switch (error.code) {
          HouseholdRepositoryErrorCode.invalidInviteCode =>
            strings.invalidInvite,
          HouseholdRepositoryErrorCode.network => strings.setupNetworkFailure,
          HouseholdRepositoryErrorCode.permission =>
            strings.setupPermissionFailure,
          HouseholdRepositoryErrorCode.invalidInput => strings.requiredFields,
          _ => strings.setupUnknownFailure,
        },
      );
    } on Object {
      if (mounted) setState(() => errorMessage = strings.setupUnknownFailure);
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }
}

class _LanguageMenu extends ConsumerWidget {
  const _LanguageMenu({required this.locale, required this.strings});

  final AppLocale locale;
  final AppStrings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<AppLocale>(
      key: const Key('locale.menu'),
      tooltip: strings.language,
      initialValue: locale,
      onSelected: (next) =>
          ref.read(appControllerProvider.notifier).setLocale(next),
      itemBuilder: (context) => AppLocale.values
          .map(
            (item) => PopupMenuItem(
              value: item,
              child: Row(
                children: [
                  if (item == locale) const Icon(Icons.check_rounded, size: 18),
                  if (item == locale) const SizedBox(width: 8),
                  Text(item.label),
                ],
              ),
            ),
          )
          .toList(),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.language_rounded,
                color: CopawColors.purple,
                size: 19,
              ),
              const SizedBox(width: 7),
              Text(locale.label),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return CopawCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          children: [
            Container(
              height: 155,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [CopawColors.lavender, CopawColors.peach],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Center(
                child: Icon(
                  Icons.pets_rounded,
                  size: 82,
                  color: CopawColors.purple,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 17, 22, 21),
              child: Column(
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.pets_rounded, color: CopawColors.purple),
                      SizedBox(width: 9),
                      Text(
                        'copaw',
                        style: TextStyle(
                          fontSize: 31,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    strings.tagline,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: CopawColors.muted,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.auto_awesome_rounded,
                        color: CopawColors.purple,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          strings.supportingTagline,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: CopawColors.purpleDark,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.hint,
    required this.icon,
    required this.controller,
    required this.maximumLength,
    this.capitalization = TextCapitalization.sentences,
    super.key,
  });

  final String label;
  final String hint;
  final IconData icon;
  final TextEditingController controller;
  final int maximumLength;
  final TextCapitalization capitalization;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: CopawColors.purpleDark),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: CopawColors.purpleDark,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLength: maximumLength,
          textCapitalization: capitalization,
          decoration: InputDecoration(hintText: hint, counterText: ''),
        ),
      ],
    );
  }
}
