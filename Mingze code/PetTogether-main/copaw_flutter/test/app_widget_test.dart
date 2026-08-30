import 'dart:async';
import 'dart:ui' as ui;

import 'package:copaw_flutter/src/app.dart';
import 'package:copaw_flutter/src/bootstrap/bootstrap_repository.dart';
import 'package:copaw_flutter/src/data/care_task_repository.dart';
import 'package:copaw_flutter/src/data/care_task_mutation_repository.dart';
import 'package:copaw_flutter/src/data/collaboration_event_repository.dart';
import 'package:copaw_flutter/src/data/household_repository.dart';
import 'package:copaw_flutter/src/data/health_repository.dart';
import 'package:copaw_flutter/src/data/handoff_repository.dart';
import 'package:copaw_flutter/src/data/handoff_session_repository.dart';
import 'package:copaw_flutter/src/data/report_share_repository.dart';
import 'package:copaw_flutter/src/data/household_sync_repository.dart';
import 'package:copaw_flutter/src/data/local_timezone_repository.dart';
import 'package:copaw_flutter/src/data/medication_repository.dart';
import 'package:copaw_flutter/src/data/membership_exit_repository.dart';
import 'package:copaw_flutter/src/data/notification_repository.dart';
import 'package:copaw_flutter/src/data/notification_center_repository.dart';
import 'package:copaw_flutter/src/data/notification_lifecycle.dart';
import 'package:copaw_flutter/src/data/pet_repository.dart';
import 'package:copaw_flutter/src/data/task_responsibility_repository.dart';
import 'package:copaw_flutter/src/domain/legacy_firestore_codec.dart';
import 'package:copaw_flutter/src/domain/collaboration_event_models.dart';
import 'package:copaw_flutter/src/domain/health_models.dart';
import 'package:copaw_flutter/src/domain/handoff_models.dart';
import 'package:copaw_flutter/src/domain/medication_models.dart';
import 'package:copaw_flutter/src/domain/models.dart';
import 'package:copaw_flutter/src/domain/notification_models.dart';
import 'package:copaw_flutter/src/domain/report_models.dart';
import 'package:copaw_flutter/src/domain/responsibility_models.dart';
import 'package:copaw_flutter/src/localization/app_locale.dart';
import 'package:copaw_flutter/src/localization/locale_repository.dart';
import 'package:copaw_flutter/src/theme/copaw_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('core semantic text colors meet contrast on their light surfaces', () {
    double contrast(Color foreground, Color background) {
      final light = foreground.computeLuminance();
      final dark = background.computeLuminance();
      return (light > dark ? light + 0.05 : dark + 0.05) /
          (light > dark ? dark + 0.05 : light + 0.05);
    }

    expect(
      contrast(CopawColors.muted, Colors.white),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(CopawColors.muted, CopawColors.cream),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(CopawColors.purple, CopawColors.lavender),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(
        CopawColors.green,
        Color.alphaBlend(
          CopawColors.green.withValues(alpha: 0.12),
          Colors.white,
        ),
      ),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(
        CopawColors.orangeStrong,
        Color.alphaBlend(
          CopawColors.orangeStrong.withValues(alpha: 0.09),
          Colors.white,
        ),
      ),
      greaterThanOrEqualTo(3),
      reason: 'Report medication metric icon, value, and progress',
    );
    expect(
      contrast(
        CopawColors.orangeStrong,
        Color.alphaBlend(
          CopawColors.orangeStrong.withValues(alpha: 0.14),
          Colors.white,
        ),
      ),
      greaterThanOrEqualTo(3),
      reason: 'Activity skipped-medication icon',
    );
    expect(
      contrast(
        CopawColors.roseStrong,
        Color.alphaBlend(
          CopawColors.roseStrong.withValues(alpha: 0.12),
          Colors.white,
        ),
      ),
      greaterThanOrEqualTo(3),
      reason: 'Health record icon',
    );
  });

  test('notification surfaces meet contrast on actual theme blends', () {
    double contrast(Color foreground, Color background) {
      final light = foreground.computeLuminance();
      final dark = background.computeLuminance();
      return (light > dark ? light + 0.05 : dark + 0.05) /
          (light > dark ? dark + 0.05 : light + 0.05);
    }

    final theme = buildCopawTheme();
    final text = theme.textTheme.bodyMedium!.color!;
    final activeInbox = Color.alphaBlend(
      CopawColors.lavender.withValues(alpha: 0.45),
      Colors.white,
    );
    final cancelledInbox = Color.alphaBlend(
      Colors.black.withValues(alpha: 0.04),
      Colors.white,
    );
    final infoStatus = Color.alphaBlend(
      CopawColors.lavender.withValues(alpha: 0.55),
      Colors.white,
    );

    expect(
      contrast(text, CopawColors.lavender),
      greaterThanOrEqualTo(4.5),
      reason: 'Selected Changes and Reminders labels',
    );
    expect(
      contrast(CopawColors.purple, CopawColors.lavender),
      greaterThanOrEqualTo(3),
      reason: 'Selected reminder unread indicator',
    );
    expect(
      contrast(text, activeInbox),
      greaterThanOrEqualTo(4.5),
      reason: 'Active inbox row on its blended lavender surface',
    );
    expect(
      contrast(text, cancelledInbox),
      greaterThanOrEqualTo(4.5),
      reason: 'Cancelled inbox row on its blended neutral surface',
    );
    expect(
      contrast(text, infoStatus),
      greaterThanOrEqualTo(4.5),
      reason: 'Informational status message',
    );
    expect(
      contrast(text, theme.colorScheme.errorContainer),
      greaterThanOrEqualTo(4.5),
      reason: 'Error status message',
    );
    expect(
      contrast(text, theme.colorScheme.surfaceContainerLow),
      greaterThanOrEqualTo(4.5),
      reason: 'Foreground notification banner content',
    );
    expect(
      contrast(
        theme.colorScheme.primary,
        theme.colorScheme.surfaceContainerLow,
      ),
      greaterThanOrEqualTo(4.5),
      reason: 'Foreground notification banner actions',
    );
  });

  test('calendar weekday headers are Monday-first in both locales', () {
    expect(AppStrings(AppLocale.english).calendarWeekdayHeaders, const [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ]);
    expect(AppStrings(AppLocale.japanese).calendarWeekdayHeaders, const [
      '月',
      '火',
      '水',
      '木',
      '金',
      '土',
      '日',
    ]);
  });

  testWidgets('shows loading then the no-household start shell', (
    tester,
  ) async {
    final bootstrap = FakeBootstrapRepository();

    await tester.pumpWidget(_testApp(bootstrap: bootstrap));
    expect(find.byKey(const Key('boot.loading')), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byKey(const Key('start.shell')), findsOneWidget);
    expect(find.text('Shared care, without the guesswork.'), findsOneWidget);
    expect(bootstrap.attempts, 1);
  });

  testWidgets('shows an actionable startup error', (tester) async {
    final bootstrap = FakeBootstrapRepository([StateError('offline')]);

    await tester.pumpWidget(_testApp(bootstrap: bootstrap));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('boot.error')), findsOneWidget);
    expect(find.text('CoPaw could not start'), findsOneWidget);
    expect(find.byKey(const Key('boot.retry')), findsOneWidget);
    expect(find.textContaining('StateError'), findsNothing);
  });

  testWidgets('shows configuration-specific recovery without raw details', (
    tester,
  ) async {
    final bootstrap = FakeBootstrapRepository([
      const BootstrapException(
        kind: BootstrapFailureKind.configuration,
        code: 'missing-plugin',
      ),
    ]);

    await tester.pumpWidget(_testApp(bootstrap: bootstrap));
    await tester.pumpAndSettle();

    expect(find.textContaining('missing its Firebase configuration'), findsOne);
    expect(find.textContaining('missing-plugin'), findsNothing);
  });

  testWidgets('shows a network-specific restore recovery', (tester) async {
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(
          restoreError: const HouseholdRepositoryException(
            HouseholdRepositoryErrorCode.network,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('could not reach Firebase'), findsOneWidget);
    expect(find.byKey(const Key('boot.retry')), findsOneWidget);
  });

  testWidgets('retry recovers from a failed initialization', (tester) async {
    final bootstrap = FakeBootstrapRepository([
      StateError('temporary'),
      BootstrapResult.noHousehold,
    ]);

    await tester.pumpWidget(_testApp(bootstrap: bootstrap));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('boot.error')), findsOneWidget);

    await tester.tap(find.byKey(const Key('boot.retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('start.shell')), findsOneWidget);
    expect(bootstrap.attempts, 2);
  });

  testWidgets('switches to Japanese and saves the locale', (tester) async {
    final localeRepository = FakeLocaleRepository(AppLocale.english);

    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        localeRepository: localeRepository,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('locale.menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日本語').last);
    await tester.pumpAndSettle();

    expect(find.text('迷わない、みんなのケア。'), findsOneWidget);
    expect(
      Localizations.localeOf(
        tester.element(find.byKey(const Key('start.shell'))),
      ).languageCode,
      'ja',
    );
    expect(localeRepository.storedLocale, AppLocale.japanese);
    expect(localeRepository.saves, 1);
  });

  testWidgets('loads a previously saved Japanese locale', (tester) async {
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        localeRepository: FakeLocaleRepository(AppLocale.japanese),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('迷わない、みんなのケア。'), findsOneWidget);
    expect(find.text('家を作る'), findsOneWidget);
  });

  testWidgets('locale storage failure falls back to Japanese', (tester) async {
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        localeRepository: _FailingLocaleRepository(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('start.shell')), findsOneWidget);
    expect(find.text('迷わない、みんなのケア。'), findsOneWidget);
  });

  testWidgets('failed locale save rolls visible locale back', (tester) async {
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        localeRepository: _SaveFailingLocaleRepository(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('locale.menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日本語').last);
    await tester.pumpAndSettle();

    expect(find.text('Shared care, without the guesswork.'), findsOneWidget);
    expect(find.text('迷わない、みんなのケア。'), findsNothing);
  });

  testWidgets('creates a household and shows the restored session shell', (
    tester,
  ) async {
    final householdRepository = FakeHouseholdRepository();
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: householdRepository,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('start.caregiverName')),
        matching: find.byType(TextField),
      ),
      'Alex',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('start.householdName')),
        matching: find.byType(TextField),
      ),
      'Mochi Family',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('start.petName')),
        matching: find.byType(TextField),
      ),
      'Mochi',
    );
    await tester.ensureVisible(find.byKey(const Key('start.primaryAction')));
    await tester.tap(find.byKey(const Key('start.primaryAction')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('household.home')), findsOneWidget);
    expect(find.text('Mochi Family'), findsOneWidget);
    expect(householdRepository.createdTimeZone, 'Asia/Tokyo');
  });

  testWidgets('invalid join remains on form with an actionable error', (
    tester,
  ) async {
    final householdRepository = FakeHouseholdRepository(
      joinError: const HouseholdRepositoryException(
        HouseholdRepositoryErrorCode.invalidInviteCode,
      ),
    );
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: householdRepository,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Join a home'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('start.caregiverName')),
        matching: find.byType(TextField),
      ),
      'Alex',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('start.inviteCode')),
        matching: find.byType(TextField),
      ),
      'ABC234',
    );
    await tester.ensureVisible(find.byKey(const Key('start.primaryAction')));
    await tester.tap(find.byKey(const Key('start.primaryAction')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('start.shell')), findsOneWidget);
    expect(find.byKey(const Key('start.error')), findsOneWidget);
    expect(find.textContaining('invalid or no longer active'), findsOneWidget);
  });

  testWidgets('restores and disconnects only the local device', (tester) async {
    final householdRepository = FakeHouseholdRepository(
      restoredSession: _session,
    );
    final careTaskRepository = _FakeCareTaskRepository();
    final householdSyncRepository = _FakeHouseholdSyncRepository();
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: householdRepository,
        careTaskRepository: careTaskRepository,
        householdSyncRepository: householdSyncRepository,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('household.home')), findsOneWidget);

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('household.home')),
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('household.disconnect')));
    await tester.tap(find.byKey(const Key('household.disconnect')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('start.shell')), findsOneWidget);
    expect(householdRepository.leaveCalls, 1);
    expect(careTaskRepository.stopCalls, 1);
    expect(householdSyncRepository.stopCalls, 1);
  });

  testWidgets('failed device disconnect keeps the live observers running', (
    tester,
  ) async {
    final careTaskRepository = _FakeCareTaskRepository();
    final householdSyncRepository = _FakeHouseholdSyncRepository();
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(
          restoredSession: _session,
          leaveError: StateError('storage full'),
        ),
        careTaskRepository: careTaskRepository,
        householdSyncRepository: householdSyncRepository,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('household.home')),
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('household.disconnect')));
    await tester.tap(find.byKey(const Key('household.disconnect')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('household.home')), findsOneWidget);
    expect(find.byKey(const Key('household.leaveError')), findsOneWidget);
    expect(
      find.textContaining('Notification registration was disabled'),
      findsOneWidget,
    );
    expect(careTaskRepository.stopCalls, 0);
    expect(householdSyncRepository.stopCalls, 0);
  });

  testWidgets('notification disable failure preserves the device session', (
    tester,
  ) async {
    final household = FakeHouseholdRepository(restoredSession: _session);
    final notifications = _FakeNotificationRepository(
      disableError: StateError('offline'),
    );
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: household,
        notificationRepository: notifications,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('household.disconnect')));
    await tester.tap(find.byKey(const Key('household.disconnect')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('household.home')), findsOneWidget);
    expect(find.textContaining('local session was preserved'), findsOneWidget);
    expect(notifications.disableCalls, 1);
    expect(household.leaveCalls, 0);
  });

  testWidgets('shows an empty Today state for a restored household', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('care.empty')), findsOneWidget);
    expect(find.byKey(const Key('care.addTask')), findsOneWidget);
  });

  testWidgets('Today dose waits for a confirmed listener result', (
    tester,
  ) async {
    final medicationRepository = _FakeMedicationRepository(
      snapshots: [_medicationSnapshot()],
    );
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        medicationRepository: medicationRepository,
      ),
    );
    await tester.pumpAndSettle();

    final dose = find.byKey(Key('medication.dose.${_todayMedicationId()}'));
    await tester.ensureVisible(dose);
    expect(dose, findsOneWidget);
    final administer = find.byKey(
      Key('medication.administer.${_todayMedicationId()}'),
    );
    await tester.ensureVisible(administer);
    await tester.pumpAndSettle();
    await tester.tap(administer);
    await tester.pumpAndSettle();

    expect(medicationRepository.administerCalls, 1);
    expect(find.text('Administered'), findsNothing);
  });

  testWidgets('Today keeps care and medication in one agenda card', (
    tester,
  ) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        careTaskRepository: _FakeCareTaskRepository(
          snapshot: CareTaskSnapshot(
            routines: const [],
            tasks: [
              _petTask(
                'Breakfast',
                legacyPrimaryPetId,
                'Mochi',
                now.add(const Duration(minutes: 20)),
              ),
            ],
          ),
        ),
        medicationRepository: _FakeMedicationRepository(
          snapshots: [_medicationSnapshot()],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final agenda = find.byKey(const Key('today.agenda'));
    expect(
      find.descendant(of: agenda, matching: find.text('Breakfast')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: agenda,
        matching: find.byKey(Key('medication.dose.${_todayMedicationId()}')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('cached terminal medication never appears confirmed', (
    tester,
  ) async {
    final medicationRepository = _FakeMedicationRepository(
      snapshots: [
        _medicationSnapshot(
          serverConfirmed: false,
          occurrence: _medicationOccurrence(
            outcome: MedicationOutcomeStatus.administered,
            isServerConfirmed: false,
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        medicationRepository: medicationRepository,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('medication.cacheWarning')), findsOneWidget);
    expect(find.text('Administered'), findsNothing);
    expect(find.text('Record administered'), findsNothing);
  });

  testWidgets('terminal conflict refreshes to the authoritative outcome', (
    tester,
  ) async {
    final medicationRepository = _FakeMedicationRepository(
      snapshots: [
        _medicationSnapshot(),
        _medicationSnapshot(
          occurrence: _medicationOccurrence(
            outcome: MedicationOutcomeStatus.administered,
            isServerConfirmed: true,
          ),
        ),
      ],
      actionError: const MedicationRepositoryException(
        MedicationRepositoryErrorCode.terminalConflict,
      ),
    );
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        medicationRepository: medicationRepository,
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(Key('medication.dose.${_todayMedicationId()}')),
    );
    final administer = find.byKey(
      Key('medication.administer.${_todayMedicationId()}'),
    );
    await tester.ensureVisible(administer);
    await tester.pumpAndSettle();
    await tester.tap(administer);
    await tester.pumpAndSettle();

    expect(medicationRepository.observeCalls, 2);
    expect(find.text('Administered'), findsOneWidget);
    expect(find.textContaining('Recorded by Alex'), findsOneWidget);
  });

  testWidgets('Activity shows confirmed skipped history and reason', (
    tester,
  ) async {
    final occurrence = _medicationOccurrence(
      outcome: MedicationOutcomeStatus.skipped,
      isServerConfirmed: true,
      reason: MedicationSkipReasonCode.petRefused,
      reasonNote: 'Vet said wait',
    );
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        medicationRepository: _FakeMedicationRepository(
          snapshots: [_medicationSnapshot(occurrence: occurrence)],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _openRecordSection(tester, const Key('records.activity.open'));

    expect(
      find.byKey(Key('activity.medication.${occurrence.id}')),
      findsOneWidget,
    );
    final medicationEvent = find.byKey(
      Key('activity.medication.${occurrence.id}'),
    );
    expect(
      find.descendant(
        of: medicationEvent,
        matching: find.textContaining('Skipped'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: medicationEvent,
        matching: find.textContaining('Pet refused'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: medicationEvent,
        matching: find.textContaining('Vet said wait'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('creates a one-off task from Today', (tester) async {
    final careTaskRepository = _FakeCareTaskRepository();
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        careTaskRepository: careTaskRepository,
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('care.addTask')));
    await tester.tap(find.byKey(const Key('care.addTask')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('care.taskTitle')),
      'Evening walk',
    );
    await tester.tap(find.byKey(const Key('care.saveTask')));
    await tester.pumpAndSettle();

    expect(careTaskRepository.createdTitle, 'Evening walk');
    expect(find.byKey(const Key('care.taskTitle')), findsNothing);
  });

  testWidgets('keeps the task sheet open when save fails', (tester) async {
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        careTaskRepository: _FakeCareTaskRepository(failCreate: true),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('care.addTask')));
    await tester.tap(find.byKey(const Key('care.addTask')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('care.taskTitle')),
      'Evening walk',
    );
    await tester.tap(find.byKey(const Key('care.saveTask')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('care.taskTitle')), findsOneWidget);
    expect(
      find.text(
        'The task was not confirmed. Check your connection and try again.',
      ),
      findsOne,
    );
  });

  testWidgets('self-claim is wired to the task mutation repository', (
    tester,
  ) async {
    final mutationRepository = _FakeCareTaskMutationRepository();
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        careTaskRepository: _FakeCareTaskRepository(
          snapshot: CareTaskSnapshot(
            routines: const [],
            tasks: [_unclaimedTask()],
          ),
        ),
        careTaskMutationRepository: mutationRepository,
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('care.claim.task-1')));
    await tester.tap(find.byKey(const Key('care.claim.task-1')));
    await tester.pumpAndSettle();

    expect(mutationRepository.claimCalls, 1);
    expect(mutationRepository.lastTaskId, 'task-1');
  });

  testWidgets('failed task action remains visible and retryable', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        careTaskRepository: _FakeCareTaskRepository(
          snapshot: CareTaskSnapshot(
            routines: const [],
            tasks: [_unclaimedTask()],
          ),
        ),
        careTaskMutationRepository: _FakeCareTaskMutationRepository(
          failActions: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('care.claim.task-1')));
    await tester.tap(find.byKey(const Key('care.claim.task-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('care.actionError.task-1')), findsOneWidget);
    expect(find.byKey(const Key('care.claim.task-1')), findsOneWidget);
  });

  testWidgets('unsafe legacy task is visible but cannot be mutated', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        careTaskRepository: _FakeCareTaskRepository(
          snapshot: CareTaskSnapshot(
            routines: const [],
            tasks: [_unclaimedTask()],
            diagnostics: const [
              DomainDiagnostic(
                code: DomainDiagnosticCode.legacyUnsafeToMutate,
                documentId: 'task-1',
                message: 'legacy task',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Evening walk'), findsOneWidget);
    expect(find.byKey(const Key('care.legacyWarning')), findsOneWidget);
    expect(find.byKey(const Key('care.claim.task-1')), findsNothing);
  });

  testWidgets('malformed hidden care shows repair instead of empty Today', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        careTaskRepository: _FakeCareTaskRepository(
          snapshot: const CareTaskSnapshot(
            routines: [],
            tasks: [],
            diagnostics: [
              DomainDiagnostic(
                code: DomainDiagnosticCode.malformedData,
                documentId: 'bad-task',
                message: 'malformed task',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('care.repairRequired')), findsOneWidget);
    expect(find.byKey(const Key('care.empty')), findsNothing);
  });

  testWidgets('unknown timezone shows repair without crashing', (tester) async {
    const invalidTimeZoneSession = HouseholdSession(
      household: Household(
        id: 'household-1',
        name: 'Mochi Family',
        inviteCode: 'ABC234',
        petName: 'Mochi',
        timeZoneIdentifier: 'Asia/NotReal',
      ),
      caregiver: Caregiver(id: 'user-1', displayName: 'Alex'),
    );
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(
          restoredSession: invalidTimeZoneSession,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('needs a timezone'), findsOneWidget);
    expect(find.byKey(const Key('household.home')), findsOneWidget);
  });

  testWidgets('care listener failure is visible and retryable', (tester) async {
    final careTaskRepository = _FakeCareTaskRepository(
      observeError: const HouseholdRepositoryException(
        HouseholdRepositoryErrorCode.network,
      ),
    );
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        careTaskRepository: careTaskRepository,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('care.error')), findsOneWidget);
    expect(find.byKey(const Key('care.retry')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('care.retry')));
    await tester.tap(find.byKey(const Key('care.retry')));
    await tester.pumpAndSettle();
    expect(careTaskRepository.observeCalls, 2);
  });

  testWidgets('direct assignment selects another household member', (
    tester,
  ) async {
    final mutationRepository = _FakeCareTaskMutationRepository();
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        householdSyncRepository: _FakeHouseholdSyncRepository(
          snapshot: HouseholdSyncSnapshot(
            household: _session.household,
            caregiver: _session.caregiver,
            members: const [
              Caregiver(id: 'user-1', displayName: 'Alex'),
              Caregiver(id: 'user-2', displayName: 'Sam'),
            ],
          ),
        ),
        careTaskRepository: _FakeCareTaskRepository(
          snapshot: CareTaskSnapshot(
            routines: const [],
            tasks: [_unclaimedTask()],
          ),
        ),
        careTaskMutationRepository: mutationRepository,
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('care.requestDirect.task-1')),
    );
    await tester.tap(find.byKey(const Key('care.requestDirect.task-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sam'));
    await tester.pumpAndSettle();

    expect(mutationRepository.lastRecipientId, 'user-2');
  });

  testWidgets('Calendar and Activity navigation show care states', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('calendar.picker')), findsOneWidget);
    final calendarDays = find.descendant(
      of: find.byKey(const Key('calendar.picker')),
      matching: find.byWidgetPredicate((widget) {
        final key = widget.key;
        return widget is InkWell &&
            key is ValueKey<String> &&
            key.value.startsWith('calendar.day.');
      }),
    );
    expect(calendarDays, findsNWidgets(42));
    expect(
      tester.getCenter(find.byKey(const Key('calendar.weekday.0'))).dx,
      closeTo(tester.getCenter(calendarDays.at(0)).dx, 0.1),
    );
    expect(
      tester.getCenter(find.byKey(const Key('calendar.weekday.6'))).dx,
      closeTo(tester.getCenter(calendarDays.at(6)).dx, 0.1),
    );

    await _openRecordSection(tester, const Key('records.activity.open'));
    expect(find.byKey(const Key('activity.empty')), findsOneWidget);
  });

  testWidgets(
    'Japanese Calendar headers align with Monday-first date columns',
    (tester) async {
      await tester.pumpWidget(
        _testApp(
          bootstrap: FakeBootstrapRepository(),
          localeRepository: FakeLocaleRepository(AppLocale.japanese),
          householdRepository: FakeHouseholdRepository(
            restoredSession: _session,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('カレンダー'));
      await tester.pumpAndSettle();
      final calendarDays = find.descendant(
        of: find.byKey(const Key('calendar.picker')),
        matching: find.byWidgetPredicate((widget) {
          final key = widget.key;
          return widget is InkWell &&
              key is ValueKey<String> &&
              key.value.startsWith('calendar.day.');
        }),
      );
      expect(calendarDays, findsNWidgets(42));
      expect(
        tester.getCenter(find.byKey(const Key('calendar.weekday.0'))).dx,
        closeTo(tester.getCenter(calendarDays.at(0)).dx, 0.1),
      );
      expect(
        tester.getCenter(find.byKey(const Key('calendar.weekday.6'))).dx,
        closeTo(tester.getCenter(calendarDays.at(6)).dx, 0.1),
      );
    },
  );

  testWidgets('profile edits call the atomic sync repository', (tester) async {
    final syncRepository = _FakeHouseholdSyncRepository();
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        householdSyncRepository: syncRepository,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('profile.edit')));
    await tester.tap(find.byKey(const Key('profile.edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('profile.householdName')),
      'New Home',
    );
    await tester.tap(find.byKey(const Key('profile.save')));
    await tester.pumpAndSettle();

    expect(syncRepository.updatedHouseholdName, 'New Home');
  });

  testWidgets('profile sheet stays scrollable above a keyboard at large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final syncRepository = _FakeHouseholdSyncRepository();
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        householdSyncRepository: syncRepository,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('profile.edit')));
    await tester.tap(find.byKey(const Key('profile.edit')));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('profile.caregiverName')));
    await tester.enterText(
      find.byKey(const Key('profile.caregiverName')),
      'Large text caregiver',
    );
    await tester.ensureVisible(find.byKey(const Key('profile.save')));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('profile.save')));
    await tester.pumpAndSettle();

    expect(syncRepository.updatedCaregiverName, 'Large text caregiver');
  });

  testWidgets('profile cancel is reachable and does not save changes', (
    tester,
  ) async {
    final syncRepository = _FakeHouseholdSyncRepository();
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        householdSyncRepository: syncRepository,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('profile.edit')));
    await tester.tap(find.byKey(const Key('profile.edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('profile.householdName')),
      'Unsaved Home',
    );
    await tester.ensureVisible(find.byKey(const Key('profile.cancel')));
    await tester.tap(find.byKey(const Key('profile.cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile.householdName')), findsNothing);
    expect(syncRepository.updateCalls, 0);
  });

  testWidgets('profile failure preserves input and retry prevents duplicates', (
    tester,
  ) async {
    final syncRepository = _FakeHouseholdSyncRepository(
      updateError: StateError('offline'),
    );
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        householdSyncRepository: syncRepository,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('profile.edit')));
    await tester.tap(find.byKey(const Key('profile.edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('profile.householdName')),
      'Retry Home',
    );
    await tester.ensureVisible(find.byKey(const Key('profile.save')));
    await tester.tap(find.byKey(const Key('profile.save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile.error')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('profile.householdName')))
          .controller
          ?.text,
      'Retry Home',
    );
    expect(syncRepository.updateCalls, 1);
    syncRepository.updateError = null;
    syncRepository.updateCompleter = Completer<void>();
    await tester.tap(find.byKey(const Key('profile.save')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('profile.save')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const Key('profile.save')));
    expect(syncRepository.updateCalls, 2);
    syncRepository.updateCompleter!.complete();
    await tester.pumpAndSettle();
    expect(syncRepository.updatedHouseholdName, 'Retry Home');
  });

  testWidgets('creates a daily recurring routine from Today', (tester) async {
    final careRepository = _FakeCareTaskRepository();
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        careTaskRepository: careRepository,
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('care.addTask')));
    await tester.tap(find.byKey(const Key('care.addTask')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('care.taskTitle')),
      'Morning meal',
    );
    await tester.tap(find.text('Recurring'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('care.saveTask')));
    await tester.pumpAndSettle();

    expect(careRepository.createdRoutineTitle, 'Morning meal');
  });

  testWidgets(
    'Calendar date and category create a future household-local one-off',
    (tester) async {
      final careRepository = _FakeCareTaskRepository();
      await tester.pumpWidget(
        _testApp(
          bootstrap: FakeBootstrapRepository(),
          householdRepository: FakeHouseholdRepository(
            restoredSession: _session,
          ),
          careTaskRepository: careRepository,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Calendar'));
      await tester.pumpAndSettle();
      final now = DateTime.now();
      final target = DateTime(now.year, now.month + 6, 20);
      final monthCount =
          (target.year - now.year) * 12 + target.month - now.month;
      for (var month = 0; month < monthCount; month += 1) {
        await tester.tap(find.byKey(const Key('calendar.nextMonth')));
        await tester.pumpAndSettle();
      }
      final targetDay = find.byKey(
        Key(
          'calendar.day.${target.year}-${target.month.toString().padLeft(2, '0')}-20',
        ),
      );
      await tester.ensureVisible(targetDay);
      await tester.tap(targetDay);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('care.addTask')));
      await tester.tap(find.byKey(const Key('care.addTask')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('care.taskTitle')),
        'Future medicine',
      );
      await tester.tap(find.byKey(const Key('care.category')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Medication').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('care.saveTask')));
      await tester.tap(find.byKey(const Key('care.saveTask')));
      await tester.pumpAndSettle();

      final householdDue = careRepository.createdDueTime!.toUtc().add(
        const Duration(hours: 9),
      );
      expect(careRepository.createdCategory, CareCategory.medication);
      expect(
        (householdDue.year, householdDue.month, householdDue.day),
        (target.year, target.month, target.day),
      );
    },
  );

  testWidgets('creates a selected-weekday routine from its selected start day', (
    tester,
  ) async {
    final careRepository = _FakeCareTaskRepository();
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        careTaskRepository: careRepository,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    final now = DateTime.now();
    final target = DateTime(now.year, now.month + 8, 12);
    final monthCount = (target.year - now.year) * 12 + target.month - now.month;
    for (var month = 0; month < monthCount; month += 1) {
      await tester.tap(find.byKey(const Key('calendar.nextMonth')));
      await tester.pumpAndSettle();
    }
    final targetDay = find.byKey(
      Key(
        'calendar.day.${target.year}-${target.month.toString().padLeft(2, '0')}-12',
      ),
    );
    await tester.ensureVisible(targetDay);
    await tester.tap(targetDay);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('care.addTask')));
    await tester.tap(find.byKey(const Key('care.addTask')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('care.taskTitle')),
      'Weekday walk',
    );
    await tester.tap(find.text('Recurring'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Selected days'));
    await tester.pumpAndSettle();
    for (final weekday in [1, 3, 5, 6, 7]) {
      final chip = find.byKey(Key('care.weekday.$weekday'));
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pump();
    }
    await tester.ensureVisible(find.byKey(const Key('care.saveTask')));
    await tester.tap(find.byKey(const Key('care.saveTask')));
    await tester.pumpAndSettle();

    final householdStart = careRepository.createdRoutineStartDate!.toUtc().add(
      const Duration(hours: 9),
    );
    expect(
      careRepository.createdRoutineFrequency,
      CareRoutineFrequency.selectedDays,
    );
    expect(careRepository.createdRoutineWeekdays, [2, 4]);
    expect(
      (householdStart.year, householdStart.month, householdStart.day),
      (target.year, target.month, target.day),
    );
  });

  testWidgets('Japanese care UI has localized core task and schedule labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        localeRepository: FakeLocaleRepository(AppLocale.japanese),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        careTaskRepository: _FakeCareTaskRepository(
          snapshot: CareTaskSnapshot(
            routines: const [],
            tasks: [_unclaimedTask()],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('未担当'), findsOneWidget);
    expect(find.textContaining('単発'), findsWidgets);
    expect(find.textContaining('散歩'), findsOneWidget);
    expect(find.textContaining('通常'), findsOneWidget);
    expect(find.textContaining('unclaimed'), findsNothing);
    expect(find.textContaining('oneOff'), findsNothing);
    expect(find.textContaining('walking'), findsNothing);

    await tester.drag(
      find.byKey(const Key('household.home')),
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('care.addTask')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('繰り返し'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('曜日を選ぶ'));
    await tester.pumpAndSettle();
    expect(find.text('日'), findsOneWidget);
    expect(find.text('月'), findsOneWidget);
    expect(find.text('S'), findsNothing);
    expect(find.text('M'), findsNothing);
  });

  testWidgets('household listener error is classified and retry reconnects', (
    tester,
  ) async {
    final syncRepository = _FakeHouseholdSyncRepository(
      observeError: const HouseholdRepositoryException(
        HouseholdRepositoryErrorCode.network,
      ),
      recoverOnRetry: true,
      snapshot: HouseholdSyncSnapshot(
        household: _session.household,
        caregiver: _session.caregiver,
        members: const [Caregiver(id: 'user-1', displayName: 'Alex')],
      ),
    );
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        householdSyncRepository: syncRepository,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('household.syncError')), findsOneWidget);
    expect(find.textContaining('updates are offline'), findsOneWidget);
    await tester.tap(find.byKey(const Key('household.syncRetry')));
    await tester.pumpAndSettle();

    expect(syncRepository.observeCalls, 2);
    expect(find.byKey(const Key('household.syncError')), findsNothing);
  });

  testWidgets('Calendar and Activity show local care and completion metadata', (
    tester,
  ) async {
    final now = DateTime.now();
    final completed = CareTask(
      id: 'completed-1',
      title: 'Vet medicine',
      category: CareCategory.medication,
      dueTime: now,
      kind: CareTaskKind.oneOff,
      priority: CarePriority.urgent,
      routineId: null,
      status: CareTaskStatus.completed,
      assignmentRequest: null,
      assigneeId: 'user-2',
      assigneeNameSnapshot: 'Sam',
      claimedAt: now,
      createdById: 'user-1',
      createdBy: 'Alex',
      createdAt: now,
      completedById: 'user-2',
      completedBy: 'Sam',
      completedAt: now,
      revision: 2,
    );
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        careTaskRepository: _FakeCareTaskRepository(
          snapshot: CareTaskSnapshot(routines: const [], tasks: [completed]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Medication'), findsWidgets);
    expect(find.textContaining('Urgent'), findsWidgets);
    expect(find.textContaining('One time'), findsWidgets);

    await _openRecordSection(tester, const Key('records.activity.open'));
    final activityCard = find.byKey(const Key('activity.card'));
    expect(
      find.descendant(
        of: activityCard,
        matching: find.textContaining('Completed by Sam'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: activityCard,
        matching: find.textContaining('Medication'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: activityCard,
        matching: find.textContaining('Urgent'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Today shows all pets then filters and saves against that pet', (
    tester,
  ) async {
    final now = DateTime.now();
    final careRepository = _FakeCareTaskRepository(
      snapshot: CareTaskSnapshot(
        routines: const [],
        tasks: [
          _petTask('Mochi meal', legacyPrimaryPetId, 'Mochi', now),
          _petTask('Nori walk', 'pet-nori', 'Nori', now),
        ],
      ),
    );
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        careTaskRepository: careRepository,
        petRepository: _FakePetRepository(
          snapshot: const PetSnapshot(
            pets: [
              Pet(
                id: legacyPrimaryPetId,
                name: 'Mochi',
                species: PetSpecies.dog,
                isArchived: false,
                createdAt: null,
                updatedAt: null,
              ),
              Pet(
                id: 'pet-nori',
                name: 'Nori',
                species: PetSpecies.cat,
                isArchived: false,
                createdAt: null,
                updatedAt: null,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mochi meal'), findsOneWidget);
    expect(find.text('Nori walk'), findsOneWidget);
    expect(find.byKey(const Key('today.petFilter.all')), findsOneWidget);
    await tester.tap(find.byKey(const Key('today.petFilter.pet-nori')));
    await tester.pumpAndSettle();
    expect(find.text('Mochi meal'), findsNothing);
    expect(find.text('Nori walk'), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('household.home')),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('care.addTask')));
    await tester.pumpAndSettle();
    expect(find.text('For Nori'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('care.taskTitle')),
      'Nori dinner',
    );
    await tester.tap(find.byKey(const Key('care.saveTask')));
    await tester.pumpAndSettle();
    expect(careRepository.createdPetId, 'pet-nori');
    expect(careRepository.createdPetName, 'Nori');
  });

  testWidgets('Japanese pet load failure is visible and retryable', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        localeRepository: FakeLocaleRepository(AppLocale.japanese),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        petRepository: _FakePetRepository(
          observeError: const PetRepositoryException(
            PetRepositoryErrorCode.network,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pets.error')), findsOneWidget);
    expect(find.textContaining('ペット情報を更新できませんでした'), findsOneWidget);
    expect(find.text('ペット情報を再読み込み'), findsOneWidget);
  });

  testWidgets(
    'health shows all pets then filters and creates a structured note',
    (tester) async {
      final health = _FakeHealthRepository(
        snapshot: HealthSnapshot([
          HealthRecord(
            id: 'health-mochi-latest',
            petId: legacyPrimaryPetId,
            petNameSnapshot: 'Mochi',
            type: HealthRecordType.weight,
            recordedAt: DateTime(2026, 8, 13, 10),
            detail: null,
            weightKilograms: 4.4,
            createdById: 'user-1',
            createdByNameSnapshot: 'Alex',
            createdAt: DateTime(2026, 8, 13, 10),
          ),
          HealthRecord(
            id: 'health-mochi',
            petId: legacyPrimaryPetId,
            petNameSnapshot: 'Mochi',
            type: HealthRecordType.weight,
            recordedAt: DateTime(2026, 8, 13, 8),
            detail: null,
            weightKilograms: 4.2,
            createdById: 'user-1',
            createdByNameSnapshot: 'Alex',
            createdAt: DateTime(2026, 8, 13, 8),
          ),
          HealthRecord(
            id: 'health-nori',
            petId: 'pet-nori',
            petNameSnapshot: 'Nori',
            type: HealthRecordType.note,
            recordedAt: DateTime(2026, 8, 13, 9),
            detail: 'Nori private observation',
            weightKilograms: null,
            createdById: 'user-1',
            createdByNameSnapshot: 'Alex',
            createdAt: DateTime(2026, 8, 13, 9),
          ),
        ]),
      );
      await tester.pumpWidget(
        _testApp(
          bootstrap: FakeBootstrapRepository(),
          householdRepository: FakeHouseholdRepository(
            restoredSession: _session,
          ),
          healthRepository: health,
          petRepository: _FakePetRepository(
            snapshot: const PetSnapshot(
              pets: [
                Pet(
                  id: legacyPrimaryPetId,
                  name: 'Mochi',
                  species: PetSpecies.dog,
                  isArchived: false,
                  createdAt: null,
                  updatedAt: null,
                ),
                Pet(
                  id: 'pet-nori',
                  name: 'Nori',
                  species: PetSpecies.cat,
                  isArchived: false,
                  createdAt: null,
                  updatedAt: null,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openRecordSection(tester, const Key('records.health.open'));

      expect(
        find.byKey(const Key('health.record.health-mochi')),
        findsOneWidget,
      );
      expect(find.textContaining('Nori private observation'), findsOneWidget);
      expect(find.textContaining('not medical advice'), findsOneWidget);
      expect(find.textContaining('Latest weight:'), findsNothing);
      await tester.tap(find.byKey(const Key('pets.selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nori').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.byKey(const Key('pets.selector')),
            )
            .value,
        'pet-nori',
      );
      await tester.drag(
        find.byKey(const Key('household.home')),
        const Offset(0, -1000),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('health.empty')), findsNothing);
      expect(
        find.byKey(const Key('health.record.health-nori')),
        findsOneWidget,
      );
      expect(find.textContaining('Nori private observation'), findsOneWidget);
      expect(find.textContaining('Latest weight:'), findsNothing);
      await tester.drag(
        find.byKey(const Key('household.home')),
        const Offset(0, 1000),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pets.selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mochi').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('health.add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('health.add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('health.detail')),
        'Eating normally',
      );
      await tester.tap(find.byKey(const Key('health.save')));
      await tester.pumpAndSettle();

      expect(health.createdPetId, legacyPrimaryPetId);
      expect(health.createdType, HealthRecordType.note);
      expect(health.createdDetail, 'Eating normally');
    },
  );

  testWidgets(
    'health records structured water and exposes honest photo state',
    (tester) async {
      final health = _FakeHealthRepository();
      await tester.pumpWidget(
        _testApp(
          bootstrap: FakeBootstrapRepository(),
          householdRepository: FakeHouseholdRepository(
            restoredSession: _session,
          ),
          healthRepository: health,
        ),
      );
      await tester.pumpAndSettle();

      await _openRecordSection(tester, const Key('records.health.open'));
      await tester.ensureVisible(find.byKey(const Key('health.add')));
      await tester.tap(find.byKey(const Key('health.add')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('health.photoAffordance')), findsOneWidget);
      expect(find.textContaining('Secure photo sync'), findsOneWidget);

      await tester.tap(find.byKey(const Key('health.type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Water intake').last);
      await tester.pumpAndSettle();
      expect(find.text('This single drinking event (ml)'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('health.water')), '420');
      await tester.enterText(
        find.byKey(const Key('health.detail')),
        'Measured after dinner',
      );
      await tester.tap(find.byKey(const Key('health.save')));
      await tester.pumpAndSettle();

      expect(health.createdType, HealthRecordType.waterIntake);
      expect(health.createdWaterMilliliters, 420);
      expect(health.createdDetail, 'Measured after dinner');
    },
  );

  testWidgets('health daily template saves structured change-from-usual data', (
    tester,
  ) async {
    final health = _FakeHealthRepository();
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        healthRepository: health,
      ),
    );
    await tester.pumpAndSettle();

    await _openRecordSection(tester, const Key('records.health.open'));
    await tester.ensureVisible(
      find.byKey(const Key('health.daily.start.legacy-primary')),
    );
    await tester.tap(
      find.byKey(const Key('health.daily.start.legacy-primary')),
    );
    await tester.pumpAndSettle();

    expect(find.text('As usual'), findsWidgets);
    expect(
      find.text('Total measured so far today (ml, optional)'),
      findsOneWidget,
    );
    expect(
      AppStrings(AppLocale.japanese).dailyHealthWaterMeasured,
      '今日、チェック時点までの累計飲水量（ml・任意）',
    );
    expect(AppStrings(AppLocale.japanese).waterMilliliters, '今回1回分の飲水量（ml）');
    expect(
      find.byKey(const Key('health.daily.photoAffordance')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('health.daily.waterMilliliters')),
      '510',
    );
    await tester.enterText(
      find.byKey(const Key('health.daily.detail')),
      'A little quieter after the walk',
    );
    await tester.ensureVisible(find.byKey(const Key('health.daily.appetite')));
    await tester.tap(find.byKey(const Key('health.daily.appetite')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Less than usual').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('health.daily.save')));
    await tester.pumpAndSettle();

    expect(health.createdType, HealthRecordType.dailyCheckIn);
    expect(health.createdWaterMilliliters, 510);
    expect(
      health.createdDailyCheckIn?.appetite,
      DailyHealthLevel.lessThanUsual,
    );
    expect(health.createdDailyCheckIn?.water, DailyHealthLevel.usual);
    expect(health.createdDetail, 'A little quieter after the walk');
  });

  testWidgets('care coverage names gaps without blaming anyone', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
      ),
    );
    await tester.pumpAndSettle();

    await _openRecordSection(tester, const Key('records.coverage.open'));
    expect(find.byKey(const Key('coverage.purpose')), findsOneWidget);
    // The screen states that counts describe records, not conclusions.
    expect(
      find.textContaining('Nothing here concludes that care did not happen'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('coverage.contributionsNote')),
      findsOneWidget,
    );
    expect(
      find.textContaining('may simply mean a member was not on duty'),
      findsOneWidget,
    );
  });

  testWidgets('the visit pack attributes every line to its source', (
    tester,
  ) async {
    final health = _FakeHealthRepository(
      snapshot: HealthSnapshot([
        HealthRecord(
          id: 'observed',
          petId: legacyPrimaryPetId,
          petNameSnapshot: 'Mochi',
          type: HealthRecordType.note,
          recordedAt: DateTime.now().subtract(const Duration(days: 1)),
          detail: 'Ate less than usual',
          weightKilograms: null,
          createdById: 'user-1',
          createdByNameSnapshot: 'Alex',
          createdAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
      ]),
    );
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        healthRepository: health,
      ),
    );
    await tester.pumpAndSettle();

    await _openRecordSection(tester, const Key('records.vetPack.open'));
    expect(find.byKey(const Key('vetPack.purpose')), findsOneWidget);
    expect(find.text('Ate less than usual'), findsOneWidget);
    expect(find.textContaining('Recorded by Alex'), findsOneWidget);

    // A section with nothing recorded says so, instead of being absent in a way
    // that could read as "this pack left it out".
    expect(
      find.byKey(const Key('vetPack.missing.activeMedications')),
      findsOneWidget,
    );
  });

  testWidgets('a report can exclude a section and use a custom range', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
      ),
    );
    await tester.pumpAndSettle();

    await _openRecordSection(tester, const Key('records.reports.open'));
    expect(find.byKey(const Key('report.card')), findsOneWidget);
    for (final section in ReportSection.values) {
      expect(
        find.byKey(Key('report.section.${section.name}')),
        findsOneWidget,
        reason: section.name,
      );
    }
    expect(find.byKey(const Key('report.customRange')), findsOneWidget);

    // Deselecting a section keeps the report available rather than breaking it.
    await tester.tap(find.byKey(const Key('report.section.water')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('report.card')), findsOneWidget);

    // The last remaining section cannot be removed, so a report always has
    // something in it.
    for (final section in [
      ReportSection.care,
      ReportSection.medication,
      ReportSection.health,
    ]) {
      await tester.tap(find.byKey(Key('report.section.${section.name}')));
      await tester.pumpAndSettle();
    }
    final chip = tester.widget<FilterChip>(
      find.byKey(const Key('report.section.health')),
    );
    expect(chip.selected, isTrue);
  });

  testWidgets('history search finds a past record by keyword and date', (
    tester,
  ) async {
    final health = _FakeHealthRepository(
      snapshot: HealthSnapshot([
        HealthRecord(
          id: 'old-note',
          petId: legacyPrimaryPetId,
          petNameSnapshot: 'Mochi',
          type: HealthRecordType.note,
          recordedAt: DateTime.utc(2026, 3, 2, 1),
          recordedLocalDate: '2026-03-02',
          recordedTimeZoneIdentifier: 'Asia/Tokyo',
          detail: 'Vomited after breakfast',
          weightKilograms: null,
          createdById: 'user-1',
          createdByNameSnapshot: 'Alex',
          createdAt: DateTime.utc(2026, 3, 2, 1),
        ),
        HealthRecord(
          id: 'recent-note',
          petId: legacyPrimaryPetId,
          petNameSnapshot: 'Mochi',
          type: HealthRecordType.note,
          recordedAt: DateTime.utc(2026, 8, 16, 1),
          recordedLocalDate: '2026-08-16',
          recordedTimeZoneIdentifier: 'Asia/Tokyo',
          detail: 'Calm evening walk',
          weightKilograms: null,
          createdById: 'user-1',
          createdByNameSnapshot: 'Alex',
          createdAt: DateTime.utc(2026, 8, 16, 1),
        ),
      ]),
    );
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        healthRepository: health,
      ),
    );
    await tester.pumpAndSettle();

    await _openRecordSection(tester, const Key('records.search.open'));
    expect(find.byKey(const Key('search.result.old-note')), findsOneWidget);
    expect(find.byKey(const Key('search.result.recent-note')), findsOneWidget);
    expect(find.text('2026-03-02'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('search.keyword')), 'vomited');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search.result.old-note')), findsOneWidget);
    expect(find.byKey(const Key('search.result.recent-note')), findsNothing);
    expect(find.text('1 records'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('search.keyword')), 'zzz');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search.empty')), findsOneWidget);

    await tester.tap(find.byKey(const Key('search.clear')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search.result.old-note')), findsOneWidget);

    await tester.tap(find.byKey(const Key('search.kind.health')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search.result.old-note')), findsNothing);
  });

  testWidgets('malformed health is visible and blocks incomplete reports', (
    tester,
  ) async {
    final health = _FakeHealthRepository(
      snapshot: HealthSnapshot([
        HealthRecord(
          id: 'valid-note',
          petId: legacyPrimaryPetId,
          petNameSnapshot: 'Mochi',
          type: HealthRecordType.note,
          recordedAt: DateTime(2026, 8, 16, 9),
          detail: 'Visible source record',
          weightKilograms: null,
          createdById: 'user-1',
          createdByNameSnapshot: 'Alex',
          createdAt: DateTime(2026, 8, 16, 9),
        ),
      ], droppedRecordCount: 1),
    );
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        healthRepository: health,
      ),
    );
    await tester.pumpAndSettle();

    await _openRecordSection(tester, const Key('records.health.open'));
    expect(find.byKey(const Key('health.incomplete')), findsOneWidget);
    expect(find.textContaining('1 health record could not'), findsOneWidget);
    expect(find.textContaining('Visible source record'), findsOneWidget);

    await _openRecordSection(tester, const Key('records.activity.open'));
    expect(find.byKey(const Key('activity.healthIncomplete')), findsOneWidget);

    await _openRecordSection(tester, const Key('records.reports.open'));
    expect(find.byKey(const Key('report.error')), findsWidgets);
    expect(find.byKey(const Key('report.share')), findsNothing);
  });

  testWidgets('notification permission status is visible and recoverable', (
    tester,
  ) async {
    final notifications = _FakeNotificationRepository(
      status: NotificationPermissionStatus.notDetermined,
      requestedStatus: NotificationPermissionStatus.denied,
    );
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        notificationRepository: notifications,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notifications.enable')), findsOneWidget);
    expect(find.textContaining('Permission not requested'), findsOneWidget);
    expect(find.textContaining('Conservative defaults'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('notifications.enable')));
    await tester.tap(find.byKey(const Key('notifications.enable')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notifications.settings')), findsOneWidget);
    expect(find.textContaining('Blocked in system settings'), findsOneWidget);

    await tester.tap(find.byKey(const Key('notifications.settings')));
    await tester.pumpAndSettle();
    expect(notifications.settingsCalls, 1);
  });

  testWidgets('notification failure is private and retryable', (tester) async {
    final notifications = _FakeNotificationRepository(
      status: NotificationPermissionStatus.error,
    );
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        notificationRepository: notifications,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notifications.retry')), findsOneWidget);
    expect(
      find.textContaining('Permission status could not be checked'),
      findsOneWidget,
    );
    expect(find.textContaining('secret-token'), findsNothing);
  });

  testWidgets(
    'HouseholdHome navigates Changes to Reminders to Profile at compact scale',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final joinedAt = DateTime.utc(2026, 8, 1);
      final item = NotificationInboxItem(
        id: 'a' * 64,
        householdId: 'household-1',
        recipientId: 'user-1',
        recipientJoinedAt: joinedAt,
        category: NotificationInboxCategory.assignment,
        level: NotificationInboxLevel.responsibilityProposal,
        routeReason: NotificationRouteReason.directTarget,
        sourceType: NotificationSourceType.taskResponsibilityTransfer,
        sourceId: 'transfer-1',
        sourcePath: 'taskResponsibilityTransfers/transfer-1',
        sourceRevision: 1,
        preferenceRevision: 1,
        status: NotificationInboxStatus.active,
        availableAt: DateTime.utc(2026, 8, 17),
        expiresAt: DateTime.utc(2026, 8, 18),
        createdAt: DateTime.utc(2026, 8, 17),
        updatedAt: DateTime.utc(2026, 8, 17),
      );
      await tester.pumpWidget(
        _testApp(
          bootstrap: FakeBootstrapRepository(),
          householdRepository: FakeHouseholdRepository(
            restoredSession: _session,
          ),
          householdSyncRepository: _FakeHouseholdSyncRepository(
            snapshot: HouseholdSyncSnapshot(
              household: _session.household,
              caregiver: _session.caregiver,
              memberJoinedAt: joinedAt,
              members: const [Caregiver(id: 'user-1', displayName: 'Alex')],
            ),
          ),
          notificationInboxRepository: FakeNotificationInboxRepository(
            items: [item],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Updates').last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('notificationUpdates.changes')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('notificationUpdates.reminders')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(Key('notificationInbox.item.${item.id}')),
        findsOneWidget,
      );

      await tester.tap(find.text('Profile').last);
      await tester.pumpAndSettle();
      expect(find.text('Notifications'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'HouseholdHome navigates Changes to Reminders to Profile at 320 Japanese 3x',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      tester.platformDispatcher.textScaleFactorTestValue = 3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final joinedAt = DateTime.utc(2026, 8, 1);
      final item = NotificationInboxItem(
        id: 'c' * 64,
        householdId: 'household-1',
        recipientId: 'user-1',
        recipientJoinedAt: joinedAt,
        category: NotificationInboxCategory.assignment,
        level: NotificationInboxLevel.responsibilityProposal,
        routeReason: NotificationRouteReason.directTarget,
        sourceType: NotificationSourceType.taskResponsibilityTransfer,
        sourceId: 'transfer-1',
        sourcePath: 'taskResponsibilityTransfers/transfer-1',
        sourceRevision: 1,
        preferenceRevision: 1,
        status: NotificationInboxStatus.active,
        availableAt: DateTime.utc(2026, 8, 17),
        expiresAt: DateTime.utc(2026, 8, 18),
        createdAt: DateTime.utc(2026, 8, 17),
        updatedAt: DateTime.utc(2026, 8, 17),
      );
      await tester.pumpWidget(
        _testApp(
          bootstrap: FakeBootstrapRepository(),
          localeRepository: FakeLocaleRepository(AppLocale.japanese),
          householdRepository: FakeHouseholdRepository(
            restoredSession: _session,
          ),
          householdSyncRepository: _FakeHouseholdSyncRepository(
            snapshot: HouseholdSyncSnapshot(
              household: _session.household,
              caregiver: _session.caregiver,
              memberJoinedAt: joinedAt,
              members: const [Caregiver(id: 'user-1', displayName: 'Alex')],
            ),
          ),
          notificationInboxRepository: FakeNotificationInboxRepository(
            items: [item],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('更新').last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('notificationUpdates.changes')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('notificationUpdates.reminders')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(Key('notificationInbox.item.${item.id}')),
        findsOneWidget,
      );

      await tester.tap(find.text('プロフィール').last);
      await tester.pumpAndSettle();
      expect(find.text('通知'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('CopawApp foreground banner opens and signals the inbox pane', (
    tester,
  ) async {
    final source = FakeNotificationLifecycleSource();
    addTearDown(source.close);
    final joinedAt = DateTime.utc(2026, 8, 1);
    final item = NotificationInboxItem(
      id: 'b' * 64,
      householdId: 'household-1',
      recipientId: 'user-1',
      recipientJoinedAt: joinedAt,
      category: NotificationInboxCategory.assignment,
      level: NotificationInboxLevel.responsibilityProposal,
      routeReason: NotificationRouteReason.directTarget,
      sourceType: NotificationSourceType.taskResponsibilityTransfer,
      sourceId: 'transfer-banner',
      sourcePath: 'taskResponsibilityTransfers/transfer-banner',
      sourceRevision: 1,
      preferenceRevision: 1,
      status: NotificationInboxStatus.active,
      availableAt: DateTime.utc(2026, 8, 17),
      expiresAt: DateTime.utc(2026, 8, 18),
      createdAt: DateTime.utc(2026, 8, 17),
      updatedAt: DateTime.utc(2026, 8, 17),
    );
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        householdSyncRepository: _FakeHouseholdSyncRepository(
          snapshot: HouseholdSyncSnapshot(
            household: _session.household,
            caregiver: _session.caregiver,
            memberJoinedAt: joinedAt,
            members: const [Caregiver(id: 'user-1', displayName: 'Alex')],
          ),
        ),
        notificationInboxRepository: FakeNotificationInboxRepository(
          items: [item],
        ),
        notificationLifecycleSource: source,
      ),
    );
    await tester.pumpAndSettle();
    expect(source.hasForegroundListener, isTrue);

    source.emitForeground(
      NotificationRoutePayload(
        householdId: item.householdId,
        inboxItemId: item.id,
      ).toJson(),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Care update available'), findsOneWidget);
    expect(find.byKey(Key('notificationInbox.item.${item.id}')), findsNothing);

    await tester.tap(find.byKey(const Key('notifications.foreground.open')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(Key('notificationInbox.item.${item.id}')),
      findsOneWidget,
    );
  });

  testWidgets('household handoff is visible and saves shared details', (
    tester,
  ) async {
    final handoff = _FakeHandoffRepository(
      snapshot: HandoffSnapshot(
        handoff: HouseholdHandoff(
          careInstructions: 'Dinner at 18:00',
          emergencyContactName: 'Sam',
          emergencyContactPhone: '090-0000-0000',
          veterinaryHospitalName: 'Central Animal Hospital',
          veterinaryHospitalPhone: '03-0000-0000',
          revision: 2,
          updatedById: 'user-2',
          updatedByNameSnapshot: 'Sam',
          updatedAt: DateTime.utc(2026, 8, 13, 8),
        ),
        isFromCache: false,
        hasPendingWrites: false,
      ),
    );
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        handoffRepository: handoff,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Dinner at 18:00'), findsOneWidget);
    expect(find.text('Central Animal Hospital'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('handoff.edit')));
    await tester.tap(find.byKey(const Key('handoff.edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('handoff.careInstructions')),
      'Dinner at 18:30',
    );
    await tester.enterText(
      find.byKey(const Key('handoff.contactName')),
      'Taylor',
    );
    await tester.tap(find.byKey(const Key('handoff.save')));
    await tester.pumpAndSettle();

    expect(handoff.savedCareInstructions, 'Dinner at 18:30');
    expect(handoff.savedEmergencyContactName, 'Taylor');
    expect(handoff.savedUpdatedById, 'user-1');
    expect(handoff.savedExpectedRevision, 2);
  });

  testWidgets('handoff conflict keeps the form and entered values visible', (
    tester,
  ) async {
    final handoff = _FakeHandoffRepository(
      snapshot: HandoffSnapshot(
        handoff: HouseholdHandoff(
          careInstructions: 'Dinner at 18:00',
          emergencyContactName: 'Sam',
          emergencyContactPhone: '090-0000-0000',
          veterinaryHospitalName: 'Central Animal Hospital',
          veterinaryHospitalPhone: '03-0000-0000',
          revision: 2,
          updatedById: 'user-2',
          updatedByNameSnapshot: 'Sam',
          updatedAt: DateTime.utc(2026, 8, 13, 8),
        ),
        isFromCache: false,
        hasPendingWrites: false,
      ),
      saveOutcomes: const [
        HandoffRepositoryException(HandoffRepositoryErrorCode.conflict),
        null,
      ],
    );
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        handoffRepository: handoff,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('handoff.edit')));
    await tester.tap(find.byKey(const Key('handoff.edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('handoff.careInstructions')),
      'Keep this unsaved edit',
    );
    await tester.tap(find.byKey(const Key('handoff.save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('handoff.saveError')), findsOneWidget);
    expect(find.textContaining('Someone updated the handoff'), findsOneWidget);
    expect(find.text('Keep this unsaved edit'), findsOneWidget);
    expect(handoff.savedExpectedRevision, 2);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    handoff.addSnapshot(
      HandoffSnapshot(
        handoff: HouseholdHandoff(
          careInstructions: 'Dinner at 19:00',
          emergencyContactName: 'Taylor',
          emergencyContactPhone: '090-1111-1111',
          veterinaryHospitalName: 'Updated Animal Hospital',
          veterinaryHospitalPhone: '03-1111-1111',
          revision: 3,
          updatedById: 'user-3',
          updatedByNameSnapshot: 'Taylor',
          updatedAt: DateTime.utc(2026, 8, 13, 9),
        ),
        isFromCache: false,
        hasPendingWrites: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Dinner at 19:00'), findsOneWidget);

    await tester.tap(find.byKey(const Key('handoff.edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('handoff.careInstructions')),
      'Reviewed after conflict',
    );
    await tester.tap(find.byKey(const Key('handoff.save')));
    await tester.pumpAndSettle();
    expect(handoff.savedExpectedRevisions, [2, 3]);
    expect(handoff.savedCareInstructions, 'Reviewed after conflict');
  });

  testWidgets('7 and 30 day reports reconcile selected pet source records', (
    tester,
  ) async {
    final share = _FakeReportShareRepository(remainingFailures: 1);
    final completedAt = DateTime.now().subtract(const Duration(hours: 1));
    final recordedLocalDate =
        '${completedAt.year.toString().padLeft(4, '0')}-'
        '${completedAt.month.toString().padLeft(2, '0')}-'
        '${completedAt.day.toString().padLeft(2, '0')}';
    final care = _FakeCareTaskRepository(
      snapshot: CareTaskSnapshot(
        routines: const [],
        tasks: [_completedReportTask(completedAt)],
      ),
    );
    final health = _FakeHealthRepository(
      snapshot: HealthSnapshot([
        HealthRecord(
          id: 'health-report',
          petId: legacyPrimaryPetId,
          petNameSnapshot: 'Mochi',
          type: HealthRecordType.note,
          recordedAt: completedAt,
          detail: 'Routine observation',
          weightKilograms: null,
          createdById: 'user-1',
          createdByNameSnapshot: 'Alex',
          createdAt: completedAt,
        ),
        HealthRecord(
          id: 'water-report',
          petId: legacyPrimaryPetId,
          petNameSnapshot: 'Mochi',
          type: HealthRecordType.waterIntake,
          recordedAt: completedAt.subtract(const Duration(minutes: 20)),
          recordedLocalDate: recordedLocalDate,
          recordedTimeZoneIdentifier: 'Asia/Tokyo',
          detail: 'Measured after dinner',
          weightKilograms: null,
          waterMilliliters: 420,
          waterMeasurementBasis: WaterMeasurementBasis.singleIntake,
          createdById: 'user-1',
          createdByNameSnapshot: 'Alex',
          createdAt: completedAt.subtract(const Duration(minutes: 20)),
        ),
        HealthRecord(
          id: 'daily-water-report',
          petId: legacyPrimaryPetId,
          petNameSnapshot: 'Mochi',
          type: HealthRecordType.dailyCheckIn,
          recordedAt: completedAt.subtract(const Duration(minutes: 30)),
          recordedLocalDate: recordedLocalDate,
          recordedTimeZoneIdentifier: 'Asia/Tokyo',
          detail: null,
          weightKilograms: null,
          waterMilliliters: 180,
          waterMeasurementBasis: WaterMeasurementBasis.localDayToDate,
          dailyCheckIn: const DailyHealthCheckIn(
            water: DailyHealthLevel.usual,
            appetite: DailyHealthLevel.usual,
            urination: DailyHealthLevel.usual,
            stool: DailyHealthStatus.usual,
            energy: DailyHealthLevel.usual,
            mood: DailyHealthStatus.usual,
          ),
          createdById: 'user-1',
          createdByNameSnapshot: 'Alex',
          createdAt: completedAt.subtract(const Duration(minutes: 30)),
        ),
      ]),
    );
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        careTaskRepository: care,
        medicationRepository: _FakeMedicationRepository(
          snapshots: [
            _medicationSnapshot(
              occurrence: _medicationOccurrence(
                outcome: MedicationOutcomeStatus.administered,
                isServerConfirmed: true,
              ),
            ),
          ],
        ),
        healthRepository: health,
        reportShareRepository: share,
      ),
    );
    await tester.pumpAndSettle();

    await _openRecordSection(tester, const Key('records.reports.open'));
    await tester.drag(
      find.byKey(const Key('household.home')),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('report.contents')), findsOneWidget);
    expect(find.text('Completed: 1'), findsOneWidget);
    expect(find.text('Administered: 1'), findsOneWidget);
    expect(find.text('Records: 3'), findsOneWidget);
    expect(find.byKey(const Key('report.nonDiagnostic')), findsOneWidget);
    expect(find.text('Tablet A · 1 tablet'), findsOneWidget);
    expect(find.textContaining('Routine observation'), findsWidgets);
    expect(find.text('Recorded water entries: 2'), findsOneWidget);
    expect(find.textContaining('420 ml'), findsWidgets);
    expect(find.textContaining('180 ml'), findsWidgets);
    expect(find.textContaining('through check-in time'), findsOneWidget);
    expect(
      find.textContaining('1 water value remained source-only'),
      findsOneWidget,
    );
    expect(find.textContaining('Recorded water total'), findsNothing);
    expect(find.textContaining('600 ml'), findsNothing);
    expect(
      find.textContaining('missing values are not inferred'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('30 days'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 days'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('report.contents')), findsOneWidget);
    expect(find.text('Administered: 1'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('report.share')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report.share')));
    await tester.pumpAndSettle();
    expect(share.calls, 1);
    expect(find.byKey(const Key('report.shareError')), findsOneWidget);
    expect(find.byKey(const Key('report.contents')), findsOneWidget);

    await tester.tap(find.byKey(const Key('report.share')));
    await tester.pumpAndSettle();
    expect(share.calls, 2);
    expect(find.byKey(const Key('report.shareError')), findsNothing);
    expect(share.report?.rangeDays, 30);
    expect(share.report?.petId, legacyPrimaryPetId);
  });

  testWidgets('Today orders all-pet care by household due time', (
    tester,
  ) async {
    final localNow = DateTime.now().toUtc().add(const Duration(hours: 9));
    final householdDayStart = DateTime.utc(
      localNow.year,
      localNow.month,
      localNow.day,
    ).subtract(const Duration(hours: 9));
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        careTaskRepository: _FakeCareTaskRepository(
          snapshot: CareTaskSnapshot(
            routines: const [],
            tasks: [
              _petTask(
                'Luna evening',
                'pet-nori',
                'Luna',
                householdDayStart.add(const Duration(hours: 18)),
              ),
              _petTask(
                'Mochi morning',
                legacyPrimaryPetId,
                'Mochi',
                householdDayStart.add(const Duration(hours: 8)),
              ),
            ],
          ),
        ),
        petRepository: _FakePetRepository(snapshot: _twoPetSnapshot),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mochi morning'), findsOneWidget);
    expect(find.text('Luna evening'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Mochi morning')).dy,
      lessThan(tester.getTopLeft(find.text('Luna evening')).dy),
    );
  });

  testWidgets('claimed responsibility and calendar marker stay distinct', (
    tester,
  ) async {
    final localNow = DateTime.now().toUtc().add(const Duration(hours: 9));
    final dueAt = DateTime.utc(localNow.year, localNow.month, localNow.day, 1);
    final task = _claimedTask(dueAt);
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        careTaskRepository: _FakeCareTaskRepository(
          snapshot: CareTaskSnapshot(routines: const [], tasks: [task]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Responsible: Sam'), findsOneWidget);
    expect(find.textContaining('Completed by'), findsNothing);
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        Key(
          'calendar.marker.${localNow.year}-${localNow.month.toString().padLeft(2, '0')}-${localNow.day.toString().padLeft(2, '0')}',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Profile owns invite and persists language preference', (
    tester,
  ) async {
    final localeRepository = FakeLocaleRepository(AppLocale.english);
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        localeRepository: localeRepository,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('household.inviteCode')), findsNothing);
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('household.inviteCode')), findsOneWidget);
    expect(find.text('ABC234'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('profile.language')));
    await tester.tap(find.text('日本語'));
    await tester.pumpAndSettle();
    expect(localeRepository.storedLocale, AppLocale.japanese);
    expect(find.text('プロフィール'), findsWidgets);
  });

  testWidgets('clean install locale repository defaults to Japanese', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        localeRepository: FakeLocaleRepository(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('迷わない、みんなのケア。'), findsOneWidget);
  });

  testWidgets('Medications defaults to all pets and shares the global filter', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        petRepository: _FakePetRepository(snapshot: _twoPetSnapshot),
        medicationRepository: _FakeMedicationRepository(
          snapshots: [_twoPetMedicationSnapshot()],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _openRecordSection(tester, const Key('records.medication.open'));
    expect(find.text('Tablet A'), findsWidgets);
    expect(find.text('Eye drops'), findsWidgets);
    expect(find.text('Past medication'), findsOneWidget);
    expect(
      tester
          .widget<DropdownButton<String>>(
            find.byKey(const Key('pets.selector')),
          )
          .value,
      '__all_pets__',
    );

    await tester.ensureVisible(
      find.byKey(const Key('medication.archive.med-1')),
    );
    await tester.tap(find.byKey(const Key('medication.archive.med-1')));
    await tester.pumpAndSettle();
    expect(find.text('Medication record'), findsOneWidget);
    expect(find.text('Cardiac support'), findsOneWidget);
    expect(find.text('Watch for appetite changes'), findsOneWidget);
    expect(find.text('Medication photo'), findsOneWidget);
    expect(find.textContaining('Secure photo sync'), findsOneWidget);
    await tester.tap(find.byKey(const Key('medication.detail.close')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('pets.selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pets.selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Luna').last);
    await tester.pumpAndSettle();
    expect(find.text('Tablet A'), findsNothing);
    expect(find.text('Eye drops'), findsWidgets);
  });

  testWidgets('Medication page includes confirmed administration history', (
    tester,
  ) async {
    final occurrence = _medicationOccurrence(
      outcome: MedicationOutcomeStatus.administered,
      isServerConfirmed: true,
    );
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        medicationRepository: _FakeMedicationRepository(
          snapshots: [_medicationSnapshot(occurrence: occurrence)],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _openRecordSection(tester, const Key('records.medication.open'));
    await tester.ensureVisible(
      find.byKey(Key('medication.history.${occurrence.id}')),
    );
    expect(
      find.byKey(Key('medication.history.${occurrence.id}')),
      findsOneWidget,
    );
    expect(find.text('Confirmed administration history'), findsOneWidget);
    expect(find.textContaining('Administered'), findsWidgets);
  });

  testWidgets('one pet filter follows the user across every care surface', (
    tester,
  ) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        petRepository: _FakePetRepository(snapshot: _twoPetSnapshot),
        careTaskRepository: _FakeCareTaskRepository(
          snapshot: CareTaskSnapshot(
            routines: const [],
            tasks: [
              _petTask('Mochi care', legacyPrimaryPetId, 'Mochi', now),
              _petTask('Luna care', 'pet-nori', 'Luna', now),
            ],
          ),
        ),
        medicationRepository: _FakeMedicationRepository(
          snapshots: [_twoPetMedicationSnapshot()],
        ),
        healthRepository: _FakeHealthRepository(
          snapshot: HealthSnapshot([
            HealthRecord(
              id: 'mochi-health',
              petId: legacyPrimaryPetId,
              petNameSnapshot: 'Mochi',
              type: HealthRecordType.note,
              recordedAt: now,
              detail: 'Mochi observation',
              weightKilograms: null,
              createdById: 'user-1',
              createdByNameSnapshot: 'Alex',
              createdAt: now,
            ),
            HealthRecord(
              id: 'luna-health',
              petId: 'pet-nori',
              petNameSnapshot: 'Luna',
              type: HealthRecordType.note,
              recordedAt: now,
              detail: 'Luna observation',
              weightKilograms: null,
              createdById: 'user-1',
              createdByNameSnapshot: 'Alex',
              createdAt: now,
            ),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _openRecordSection(tester, const Key('records.medication.open'));
    await tester.tap(find.byKey(const Key('pets.selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Luna').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Calendar').last);
    await tester.pumpAndSettle();
    expect(find.text('Luna care'), findsOneWidget);
    expect(find.text('Mochi care'), findsNothing);

    await _openRecordSection(tester, const Key('records.health.open'));
    expect(find.textContaining('Luna observation'), findsOneWidget);
    expect(find.textContaining('Mochi observation'), findsNothing);

    await _openRecordSection(tester, const Key('records.activity.open'));
    expect(find.textContaining('Luna observation'), findsWidgets);
    expect(find.textContaining('Mochi observation'), findsNothing);

    await tester.tap(find.text('Today').last);
    await tester.pumpAndSettle();
    expect(find.text('Luna care'), findsOneWidget);
    expect(find.text('Mochi care'), findsNothing);

    await tester.tap(find.byKey(const Key('today.petFilter.all')));
    await tester.pumpAndSettle();
    await _openRecordSection(tester, const Key('records.medication.open'));
    expect(find.text('Tablet A'), findsWidgets);
    expect(find.text('Eye drops'), findsWidgets);
  });

  testWidgets('five primary tabs keep records within two taps', (tester) async {
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationDestination), findsNWidgets(5));
    for (final label in [
      'Today',
      'Calendar',
      'Updates',
      'Records',
      'Profile',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }

    await tester.tap(find.text('Records').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('records.medication.open')), findsOneWidget);
    expect(find.byKey(const Key('records.health.open')), findsOneWidget);
    expect(find.byKey(const Key('records.activity.open')), findsOneWidget);
    expect(find.byKey(const Key('records.reports.open')), findsOneWidget);
    expect(find.byKey(const Key('records.search.open')), findsOneWidget);
    expect(find.byKey(const Key('records.vetPack.open')), findsOneWidget);
    expect(find.byKey(const Key('records.coverage.open')), findsOneWidget);
    for (final entry in {
      const Key('records.medication.open'): 'Medications',
      const Key('records.health.open'): 'Health',
      const Key('records.activity.open'): 'Pet history',
      const Key('records.reports.open'): 'Reports',
      const Key('records.search.open'): 'Search history',
      const Key('records.vetPack.open'): 'Visit pack',
      const Key('records.coverage.open'): 'Care coverage',
    }.entries) {
      final finder = find.byKey(entry.key);
      final semantics = tester.widget<Semantics>(finder);
      expect(semantics.properties.button, isTrue, reason: entry.value);
      expect(semantics.properties.label, entry.value);
      expect(tester.getSize(finder).height, greaterThanOrEqualTo(44));
    }

    await tester.tap(find.byKey(const Key('records.medication.open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('records.back')), findsOneWidget);

    await tester.tap(find.text('Updates').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('updates.collaboration')), findsOneWidget);

    await _openRecordSection(tester, const Key('records.activity.open'));
    expect(find.byKey(const Key('activity.card')), findsOneWidget);
  });

  testWidgets('English five-tab shell survives 320pt and 2x text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        petRepository: _FakePetRepository(snapshot: _twoPetSnapshot),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: 'Today');
    for (final label in ['Calendar', 'Updates', 'Records', 'Profile']) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: label);
    }
    await _openRecordSection(tester, const Key('records.reports.open'));
    expect(tester.takeException(), isNull, reason: 'Reports');
  });

  testWidgets('Japanese five-tab shell survives 402pt XXL text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        localeRepository: FakeLocaleRepository(AppLocale.japanese),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(tester.takeException(), isNull);
    for (final label in ['カレンダー', '更新', '記録', 'プロフィール']) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: label);
    }
    await tester.tap(find.text('更新').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('updates.collaboration')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Today long content survives compact sizes across locale scales',
    (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final now = DateTime.now().toUtc();
      final configurations = [
        (const Size(320, 568), AppLocale.english, 1.0),
        (const Size(320, 568), AppLocale.english, 2.0),
        (const Size(320, 568), AppLocale.english, 3.0),
        (const Size(320, 568), AppLocale.japanese, 1.0),
        (const Size(320, 568), AppLocale.japanese, 2.0),
        (const Size(320, 568), AppLocale.japanese, 3.0),
        (const Size(390, 844), AppLocale.english, 1.0),
        (const Size(390, 844), AppLocale.english, 2.0),
        (const Size(390, 844), AppLocale.english, 3.0),
        (const Size(390, 844), AppLocale.japanese, 1.0),
        (const Size(390, 844), AppLocale.japanese, 2.0),
        (const Size(390, 844), AppLocale.japanese, 3.0),
      ];

      for (final configuration in configurations) {
        final japanese = configuration.$2 == AppLocale.japanese;
        final householdName = japanese
            ? 'とても長い共同ケアのファミリーネーム'
            : 'The exceptionally long shared-care household name';
        final petName = japanese
            ? 'むぎちゃんのとても長い表示名'
            : 'Mochi with an exceptionally long household display name';
        final caregiverName = japanese
            ? '長い名前のケア担当者アレックス'
            : 'Alexandra with an exceptionally long caregiver name';
        final taskTitle = japanese
            ? '朝の長い散歩と食事と水分補給のケアタスク'
            : 'Morning walk, breakfast, hydration, and shared-care check-in';
        final medicationName = japanese
            ? '非常に長い表示名の毎日のケア用お薬'
            : 'Daily medication with an exceptionally long display name';
        final longSession = HouseholdSession(
          household: Household(
            id: 'household-1',
            name: householdName,
            inviteCode: 'ABC234',
            petName: petName,
            timeZoneIdentifier: 'Asia/Tokyo',
          ),
          caregiver: Caregiver(id: 'user-1', displayName: caregiverName),
        );
        final petSnapshot = PetSnapshot(
          pets: [
            Pet(
              id: legacyPrimaryPetId,
              name: petName,
              species: PetSpecies.dog,
              isArchived: false,
              createdAt: null,
              updatedAt: null,
            ),
          ],
        );
        final careSnapshot = CareTaskSnapshot(
          routines: const [],
          tasks: [
            _longTodayTask(
              now,
              title: taskTitle,
              caregiverName: caregiverName,
              petName: petName,
            ),
          ],
        );
        final medicationSnapshot = MedicationSnapshot(
          medications: [
            Medication(
              id: 'med-1',
              petId: legacyPrimaryPetId,
              displayName: medicationName,
              isActive: true,
              currentScheduleVersion: 1,
              currentScheduleVersionId: 'v000001',
              revision: 0,
            ),
          ],
          schedules: [
            _longTodayMedicationSchedule(
              petName: petName,
              medicationName: medicationName,
              doseText: japanese
                  ? '食事と一緒に一錠をゆっくり飲ませる'
                  : 'Give one tablet slowly with food and fresh water',
              instructions: japanese
                  ? '服薬後の様子を家族で確認してください'
                  : 'Ask the household to check behavior after the dose',
            ),
          ],
          occurrences: const [],
          isServerConfirmed: true,
        );
        tester.view.physicalSize = configuration.$1;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = configuration.$3;
        await tester.pumpWidget(
          _testApp(
            bootstrap: FakeBootstrapRepository(),
            localeRepository: FakeLocaleRepository(configuration.$2),
            householdRepository: FakeHouseholdRepository(
              restoredSession: longSession,
            ),
            careTaskRepository: _FakeCareTaskRepository(snapshot: careSnapshot),
            petRepository: _FakePetRepository(snapshot: petSnapshot),
            medicationRepository: _FakeMedicationRepository(
              snapshots: [medicationSnapshot],
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: '$configuration');
        expect(find.text(taskTitle), findsOneWidget);
        expect(find.textContaining(petName), findsWidgets);
        expect(find.text(medicationName), findsOneWidget);
        final complete = find.byKey(const Key('care.complete.long-today-task'));
        expect(complete, findsOneWidget);
        expect(tester.getSize(complete).height, greaterThanOrEqualTo(44));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets('Today navigation rows and controls expose ordered semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final now = DateTime.now().toUtc();
    final task = _longTodayTask(
      now,
      title: 'Morning shared-care walk',
      caregiverName: 'Alex',
      petName: 'Mochi',
    );
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        careTaskRepository: _FakeCareTaskRepository(
          snapshot: CareTaskSnapshot(routines: const [], tasks: [task]),
        ),
        medicationRepository: _FakeMedicationRepository(
          snapshots: [
            MedicationSnapshot(
              medications: const [
                Medication(
                  id: 'med-1',
                  petId: legacyPrimaryPetId,
                  displayName: 'Daily tablet',
                  isActive: true,
                  currentScheduleVersion: 1,
                  currentScheduleVersionId: 'v000001',
                  revision: 0,
                ),
              ],
              schedules: [
                _longTodayMedicationSchedule(
                  petName: 'Mochi',
                  medicationName: 'Daily tablet',
                  doseText: 'One tablet',
                  instructions: 'With food',
                ),
              ],
              occurrences: const [],
              isServerConfirmed: true,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final todayNavigation = tester.getSemantics(
      find.widgetWithText(NavigationDestination, 'Today'),
    );
    expect(todayNavigation.flagsCollection.isSelected, ui.Tristate.isTrue);
    final careSemantics = tester.widget<Semantics>(
      find.byKey(const Key('care.semantic.long-today-task')),
    );
    expect(careSemantics.container, isTrue);
    expect(careSemantics.explicitChildNodes, isTrue);
    expect(
      careSemantics.properties.label,
      contains('Morning shared-care walk'),
    );
    expect(careSemantics.properties.label, contains('Responsible: Alex'));
    expect(
      find.byKey(const Key('care.decorativeIcon.long-today-task')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ExcludeSemantics>(
            find.byKey(const Key('care.decorativeIcon.long-today-task')),
          )
          .excluding,
      isTrue,
    );

    final medicationId = _todayMedicationId();
    final medicationSemantics = tester.widget<Semantics>(
      find.byKey(Key('medication.semantic.$medicationId')),
    );
    expect(medicationSemantics.container, isTrue);
    expect(medicationSemantics.explicitChildNodes, isTrue);
    expect(medicationSemantics.properties.label, contains('Daily tablet'));
    expect(medicationSemantics.properties.label, contains('One tablet'));
    expect(
      tester
          .widget<ExcludeSemantics>(
            find.byKey(Key('medication.decorativeIcon.$medicationId')),
          )
          .excluding,
      isTrue,
    );
    expect(
      tester
          .getSemantics(find.byKey(const Key('care.complete.long-today-task')))
          .getSemanticsData()
          .hasAction(ui.SemanticsAction.tap),
      isTrue,
    );
    expect(
      tester
          .getSemantics(find.byKey(Key('medication.details.$medicationId')))
          .getSemanticsData()
          .hasAction(ui.SemanticsAction.tap),
      isTrue,
    );
    semantics.dispose();
  });

  testWidgets('Today empty error and primary controls remain semantic', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.byKey(const Key('care.empty'))).label,
      contains('Nothing is scheduled yet'),
    );
    expect(
      tester
          .getSemantics(find.byKey(const Key('care.addTask')))
          .getSemanticsData()
          .hasAction(ui.SemanticsAction.tap),
      isTrue,
    );
    await tester.tap(find.text('Calendar').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .getSemantics(find.widgetWithText(NavigationDestination, 'Calendar'))
          .flagsCollection
          .isSelected,
      ui.Tristate.isTrue,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        careTaskRepository: _FakeCareTaskRepository(
          observeError: StateError('offline'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.textContaining('Care could not')).label,
      contains('Check your connection'),
    );
    expect(
      tester
          .getSemantics(find.byKey(const Key('care.retry')))
          .getSemanticsData()
          .hasAction(ui.SemanticsAction.tap),
      isTrue,
    );
    semantics.dispose();
  });

  testWidgets(
    'Updates shows collaboration facts without replacing pet history',
    (tester) async {
      final event = CollaborationEvent(
        id: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        sourceId: 'task-1',
        sourceRevision: 2,
        action: CollaborationEventAction.taskAccepted,
        actorId: 'member-b',
        actorNameSnapshot: 'Caregiver B',
        targetMemberId: 'member-a',
        targetMemberNameSnapshot: 'Caregiver A',
        requestId: 'request-1',
        assignmentMode: 'direct',
        petId: 'legacy-primary',
        petNameSnapshot: 'Mugi',
        taskTitleSnapshot: 'Evening walk',
        taskCategorySnapshot: 'walking',
        taskPrioritySnapshot: 'normal',
        taskDueTime: DateTime.utc(2026, 8, 17, 10),
        stateAfter: CollaborationTaskState.claimed,
        occurredAt: DateTime.utc(2026, 8, 17, 9),
        recordedAt: DateTime.utc(2026, 8, 17, 9),
      );
      await tester.pumpWidget(
        _testApp(
          bootstrap: FakeBootstrapRepository(),
          householdRepository: FakeHouseholdRepository(
            restoredSession: _session,
          ),
          collaborationEventRepository: FakeCollaborationEventRepository(
            events: [event],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Updates').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('updates.incomplete')), findsOneWidget);
      expect(find.byKey(Key('updates.event.${event.id}')), findsOneWidget);
      expect(find.text('Request accepted'), findsOneWidget);
      expect(find.text('Evening walk'), findsOneWidget);
      expect(find.textContaining('Caregiver B · Mugi'), findsOneWidget);
      expect(find.byKey(const Key('activity.card')), findsNothing);

      await _openRecordSection(tester, const Key('records.activity.open'));
      expect(find.byKey(const Key('activity.card')), findsOneWidget);
    },
  );

  testWidgets(
    'Updates unread dot is member scoped and uses event ID tie-breaks',
    (tester) async {
      final occurredAt = DateTime.utc(2026, 8, 17, 9);
      final older = _collaborationEvent(
        id: _collaborationEventId('1'),
        occurredAt: occurredAt,
      );
      final newest = _collaborationEvent(
        id: _collaborationEventId('8'),
        occurredAt: occurredAt,
      );
      final repository = FakeCollaborationEventRepository(
        events: [older, newest],
      );

      await tester.pumpWidget(
        _testApp(
          bootstrap: FakeBootstrapRepository(),
          householdRepository: FakeHouseholdRepository(
            restoredSession: _session,
          ),
          collaborationEventRepository: repository,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Badge>(find.byKey(const Key('updates.unreadBadge')))
            .isLabelVisible,
        isTrue,
      );

      await tester.tap(find.text('Updates').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Badge>(find.byKey(const Key('updates.unreadBadge')))
            .isLabelVisible,
        isFalse,
      );
      expect(
        (await repository.observeReadCursor('household-1', 'user-1').first)
            .cursor
            ?.eventId,
        newest.id,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final secondSession = HouseholdSession(
        household: _session.household,
        caregiver: Caregiver(id: 'user-2', displayName: 'Sam'),
      );
      await tester.pumpWidget(
        _testApp(
          bootstrap: FakeBootstrapRepository(),
          householdRepository: FakeHouseholdRepository(
            restoredSession: secondSession,
          ),
          collaborationEventRepository: repository,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Badge>(find.byKey(const Key('updates.unreadBadge')))
            .isLabelVisible,
        isTrue,
      );
      await tester.tap(find.text('Updates').last);
      await tester.pumpAndSettle();
      expect(
        (await repository.observeReadCursor('household-1', 'user-2').first)
            .cursor
            ?.eventId,
        newest.id,
      );

      await tester.tap(find.text('Today').last);
      await tester.pumpAndSettle();
      final equalTimeHigherId = _collaborationEvent(
        id: _collaborationEventId('9'),
        occurredAt: occurredAt,
      );
      repository.replace([older, newest, equalTimeHigherId]);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Badge>(find.byKey(const Key('updates.unreadBadge')))
            .isLabelVisible,
        isTrue,
      );
    },
  );

  testWidgets('Updates retains events evicted from the realtime window', (
    tester,
  ) async {
    final base = DateTime.utc(2026, 8, 17, 9);
    final initial = List.generate(
      21,
      (index) => _collaborationEvent(
        id: index.toRadixString(16).padLeft(64, '0'),
        occurredAt: base.subtract(Duration(minutes: index)),
        title: 'Care update $index',
      ),
    );
    final repository = FakeCollaborationEventRepository(events: initial);
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        collaborationEventRepository: repository,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Badge>(find.byKey(const Key('updates.unreadBadge')))
          .isLabelVisible,
      isTrue,
    );
    await tester.tap(find.text('Updates').last);
    await tester.pumpAndSettle();
    final evicted = initial[19];
    expect(find.byKey(Key('updates.event.${evicted.id}')), findsOneWidget);

    final incoming = _collaborationEvent(
      id: _collaborationEventId('f'),
      occurredAt: base.add(const Duration(minutes: 1)),
      title: 'Newest care update',
    );
    repository.replace([incoming, ...initial]);
    await tester.pumpAndSettle();
    expect(find.byKey(Key('updates.event.${incoming.id}')), findsOneWidget);
    expect(find.byKey(Key('updates.event.${evicted.id}')), findsOneWidget);
  });

  testWidgets('Updates handles malformed cached pagination at 320pt English 3x', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    const cursor = _TestCollaborationPageCursor();
    final repository = _ScriptedCollaborationRepository(
      snapshot: CollaborationEventSnapshot(
        events: const [],
        isFromCache: true,
        droppedEventCount: 20,
        nextCursor: cursor,
        hasMore: true,
      ),
      page: CollaborationEventPage(
        events: [
          _collaborationEvent(
            id: _collaborationEventId('b'),
            occurredAt: DateTime.utc(2026, 8, 15, 9),
            title:
                'A very long shared-care change that must wrap without hiding who changed it',
          ),
        ],
        nextCursor: null,
        droppedEventCount: 1,
        isFromCache: true,
      ),
    );
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        collaborationEventRepository: repository,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Updates').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('updates.cache')), findsOneWidget);
    expect(find.byKey(const Key('updates.malformed')), findsOneWidget);
    expect(find.byKey(const Key('updates.empty')), findsNothing);
    expect(find.byKey(const Key('updates.loadOlder')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const Key('updates.loadOlder')));
    await tester.tap(find.byKey(const Key('updates.loadOlder')));
    await tester.pumpAndSettle();
    expect(find.textContaining('21 collaboration'), findsOneWidget);
    expect(find.byKey(const Key('updates.loadOlder')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Updates localizes permission failure at 390pt Japanese 3x', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        localeRepository: FakeLocaleRepository(AppLocale.japanese),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        collaborationEventRepository: _ScriptedCollaborationRepository(
          error: const CollaborationEventRepositoryException(
            CollaborationEventRepositoryErrorCode.permission,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('更新').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('updates.error')), findsOneWidget);
    expect(find.textContaining('アクセス'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Updates differentiates network pagination and backend failures',
    (tester) async {
      final event = _collaborationEvent(
        id: _collaborationEventId('a'),
        occurredAt: DateTime.utc(2026, 8, 17, 9),
      );
      await tester.pumpWidget(
        _testApp(
          bootstrap: FakeBootstrapRepository(),
          householdRepository: FakeHouseholdRepository(
            restoredSession: _session,
          ),
          collaborationEventRepository: _ScriptedCollaborationRepository(
            snapshot: CollaborationEventSnapshot(
              events: [event],
              isFromCache: false,
              droppedEventCount: 0,
              nextCursor: const _TestCollaborationPageCursor(),
              hasMore: true,
            ),
            pageError: const CollaborationEventRepositoryException(
              CollaborationEventRepositoryErrorCode.network,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Updates').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('updates.loadOlder')));
      await tester.tap(find.byKey(const Key('updates.loadOlder')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('updates.pageError')), findsOneWidget);
      expect(find.textContaining('offline'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        _testApp(
          bootstrap: FakeBootstrapRepository(),
          householdRepository: FakeHouseholdRepository(
            restoredSession: _session,
          ),
          collaborationEventRepository: _ScriptedCollaborationRepository(
            error: const CollaborationEventRepositoryException(
              CollaborationEventRepositoryErrorCode.backendUnavailable,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Updates').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('updates.error')), findsOneWidget);
      expect(find.textContaining('temporarily unavailable'), findsOneWidget);
    },
  );

  testWidgets('Updates retries read cursor sync without hiding events', (
    tester,
  ) async {
    final repository = _ScriptedCollaborationRepository(
      snapshot: CollaborationEventSnapshot(
        events: [
          _collaborationEvent(
            id: _collaborationEventId('b'),
            occurredAt: DateTime.utc(2026, 8, 17, 10),
          ),
        ],
        isFromCache: false,
        droppedEventCount: 0,
      ),
      readCursorErrorsBeforeSuccess: 1,
    );
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        collaborationEventRepository: repository,
      ),
    );
    await tester.pumpAndSettle();
    expect(_updatesBadgeVisible(tester), isTrue, reason: 'read error');
    await tester.tap(find.text('Updates').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('updates.readError')), findsOneWidget);
    expect(
      find.byKey(Key('updates.event.${_collaborationEventId('b')}')),
      findsOneWidget,
    );
    expect(repository.markedRead, isEmpty);

    await tester.tap(find.byKey(const Key('updates.readRetry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('updates.readError')), findsNothing);
    expect(repository.markedRead, hasLength(1));
  });

  testWidgets('Updates keeps unread visible while read cursor is unknown', (
    tester,
  ) async {
    final repository = _ScriptedCollaborationRepository(
      snapshot: CollaborationEventSnapshot(
        events: [
          _collaborationEvent(
            id: _collaborationEventId('d'),
            occurredAt: DateTime.utc(2026, 8, 17, 12),
          ),
        ],
        isFromCache: false,
        droppedEventCount: 0,
      ),
      readCursorNeverEmits: true,
    );
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        collaborationEventRepository: repository,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Badge>(find.byKey(const Key('updates.unreadBadge')))
          .isLabelVisible,
      isTrue,
    );
    expect(repository.markedRead, isEmpty);
  });

  testWidgets(
    'Updates read cursor pending ack deny and reconnect are conservative',
    (tester) async {
      final event = _collaborationEvent(
        id: _collaborationEventId('e'),
        occurredAt: DateTime.utc(2026, 8, 17, 13),
      );
      final newestCursor = CollaborationReadCursor(
        occurredAt: event.occurredAt,
        eventId: event.id,
      );
      final repository = _ControlledReadCollaborationRepository(
        event: event,
        reconnectSnapshot: CollaborationReadCursorSnapshot(
          cursor: newestCursor,
          isFromCache: false,
          hasPendingWrites: true,
        ),
      );
      await tester.pumpWidget(
        _testApp(
          bootstrap: FakeBootstrapRepository(),
          householdRepository: FakeHouseholdRepository(
            restoredSession: _session,
          ),
          collaborationEventRepository: repository,
        ),
      );
      await tester.pumpAndSettle();
      expect(_updatesBadgeVisible(tester), isTrue, reason: 'pending');

      repository.emitRead(
        CollaborationReadCursorSnapshot(
          cursor: newestCursor,
          isFromCache: false,
          hasPendingWrites: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(_updatesBadgeVisible(tester), isFalse, reason: 'server ack');

      repository.emitRead(
        CollaborationReadCursorSnapshot(
          cursor: CollaborationReadCursor(
            occurredAt: event.occurredAt.subtract(const Duration(minutes: 1)),
            eventId: _collaborationEventId('1'),
          ),
          isFromCache: false,
          hasPendingWrites: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(_updatesBadgeVisible(tester), isTrue, reason: 'server deny');

      repository.failRead(
        const CollaborationEventRepositoryException(
          CollaborationEventRepositoryErrorCode.network,
        ),
      );
      await tester.pumpAndSettle();
      expect(_updatesBadgeVisible(tester), isTrue, reason: 'disconnected');
      await tester.tap(find.text('Updates').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('updates.readError')), findsOneWidget);

      repository.reconnectSnapshot = CollaborationReadCursorSnapshot(
        cursor: newestCursor,
        isFromCache: false,
        hasPendingWrites: false,
      );
      await tester.tap(find.byKey(const Key('updates.readRetry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('updates.readError')), findsNothing);
      expect(_updatesBadgeVisible(tester), isFalse, reason: 'reconnected ack');
    },
  );

  testWidgets('Updates keeps unread visible while read sync is pending', (
    tester,
  ) async {
    final event = _collaborationEvent(
      id: _collaborationEventId('c'),
      occurredAt: DateTime.utc(2026, 8, 17, 11),
    );
    final repository = _ScriptedCollaborationRepository(
      snapshot: CollaborationEventSnapshot(
        events: [event],
        isFromCache: false,
        droppedEventCount: 0,
      ),
      readSnapshot: CollaborationReadCursorSnapshot(
        cursor: CollaborationReadCursor(
          occurredAt: event.occurredAt,
          eventId: event.id,
        ),
        isFromCache: true,
        hasPendingWrites: true,
      ),
    );
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        collaborationEventRepository: repository,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Badge>(find.byKey(const Key('updates.unreadBadge')))
          .isLabelVisible,
      isTrue,
    );
    await tester.tap(find.text('Updates').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('updates.readPending')), findsOneWidget);
    expect(repository.markedRead, isEmpty);
  });

  testWidgets('Records keeps its secondary destination across primary tabs', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
      ),
    );
    await tester.pumpAndSettle();

    await _openRecordSection(tester, const Key('records.health.open'));
    expect(find.byKey(const Key('records.back')), findsOneWidget);
    await tester.tap(find.text('Calendar').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Records').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('records.back')), findsOneWidget);
    expect(find.byKey(const Key('records.health.open')), findsNothing);
  });

  testWidgets(
    'Today requires consent and keeps responsibility unchanged until source sync',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      tester.platformDispatcher.textScaleFactorTestValue = 3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final responsibility = FakeTaskResponsibilityRepository(
        snapshot: TaskResponsibilitySnapshot(
          pendingByTaskId: {'claimed-task': _pendingResponsibilityTransfer()},
          isFromCache: false,
          droppedTransferCount: 0,
        ),
      );
      responsibility.nextError = const TaskResponsibilityException(
        TaskResponsibilityErrorCode.network,
      );
      final care = _FakeCareTaskRepository(
        snapshot: CareTaskSnapshot(
          routines: const [],
          tasks: [_claimedTask(DateTime.now())],
        ),
      );
      await tester.pumpWidget(
        _testApp(
          bootstrap: FakeBootstrapRepository(),
          householdRepository: FakeHouseholdRepository(
            restoredSession: _session,
          ),
          careTaskRepository: care,
          taskResponsibilityRepository: responsibility,
        ),
      );
      await tester.pumpAndSettle();

      final accept = find.byKey(const Key('care.acceptTransfer.claimed-task'));
      await tester.ensureVisible(accept);
      expect(
        find.textContaining('Responsibility stays unchanged'),
        findsOneWidget,
      );
      await tester.tap(accept);
      await tester.pumpAndSettle();

      expect(find.textContaining('not confirmed'), findsOneWidget);
      await tester.ensureVisible(accept);
      await tester.tap(accept);
      await tester.pumpAndSettle();
      expect(responsibility.calls, hasLength(2));
      expect(responsibility.calls.first['action'], 'acceptTransfer');
      expect(
        responsibility.calls.first['clientMutationID'],
        responsibility.calls.last['clientMutationID'],
      );
      expect(find.textContaining('Responsible: Sam'), findsOneWidget);
      expect(
        find.byKey(const Key('responsibility.pending.claimed-task')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('handoff template and active session stay distinct at 320pt 3x', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final handoff = _FakeHandoffRepository(
      snapshot: HandoffSnapshot(
        handoff: _handoffTemplate(
          revision: 3,
          careInstructions: 'Current dinner at 18:00',
        ),
        isFromCache: false,
        hasPendingWrites: false,
      ),
    );
    final sessions = FakeHandoffSessionRepository(
      snapshot: HandoffSessionSnapshot(
        activeSession: _offeredHandoffSession(),
        pinnedVersion: _pinnedHandoffVersion(),
        isFromCache: false,
        droppedSessionCount: 0,
        droppedVersionCount: 0,
        authorityMalformed: false,
      ),
    );
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        handoffRepository: handoff,
        handoffSessionRepository: sessions,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('handoff.session.card')));
    await tester.pumpAndSettle();

    expect(find.text('Current dinner at 18:00'), findsOneWidget);
    expect(find.text('Pinned dinner at 17:00'), findsOneWidget);
    expect(find.text('Current reusable template'), findsOneWidget);
    expect(find.text('Pinned template v2'), findsOneWidget);
    expect(
      find.byKey(const Key('handoff.session.sourceCounts')),
      findsOneWidget,
    );
    expect(find.textContaining('awaiting consent'), findsOneWidget);
    expect(find.textContaining('Template revision 2'), findsOneWidget);
    expect(find.byKey(const Key('handoff.session.accept')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing pinned version blocks handoff response authority', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        handoffRepository: _FakeHandoffRepository(
          snapshot: HandoffSnapshot(
            handoff: _handoffTemplate(revision: 3),
            isFromCache: false,
            hasPendingWrites: false,
          ),
        ),
        handoffSessionRepository: FakeHandoffSessionRepository(
          snapshot: HandoffSessionSnapshot(
            activeSession: _offeredHandoffSession(),
            pinnedVersion: null,
            isFromCache: false,
            droppedSessionCount: 0,
            droppedVersionCount: 0,
            authorityMalformed: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('handoff.session.card')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('handoff.session.notCurrent')), findsOneWidget);
    expect(find.byKey(const Key('handoff.session.accept')), findsNothing);
    expect(
      find.byKey(const Key('handoff.session.pinnedVersion')),
      findsNothing,
    );
    expect(find.textContaining('awaiting consent'), findsOneWidget);
  });

  testWidgets('cached pinned session cannot be accepted', (tester) async {
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        handoffSessionRepository: FakeHandoffSessionRepository(
          snapshot: HandoffSessionSnapshot(
            activeSession: _offeredHandoffSession(),
            pinnedVersion: _pinnedHandoffVersion(),
            isFromCache: true,
            droppedSessionCount: 0,
            droppedVersionCount: 0,
            authorityMalformed: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('handoff.session.card')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('handoff.session.notCurrent')), findsOneWidget);
    expect(find.text('Pinned dinner at 17:00'), findsOneWidget);
    expect(find.byKey(const Key('handoff.session.accept')), findsNothing);
  });

  testWidgets(
    'handoff authority error exposes retry without response controls',
    (tester) async {
      await tester.pumpWidget(
        _testApp(
          bootstrap: FakeBootstrapRepository(),
          householdRepository: FakeHouseholdRepository(
            restoredSession: _session,
          ),
          handoffSessionRepository: FakeHandoffSessionRepository(
            observeError: const HandoffSessionException(
              HandoffSessionErrorCode.network,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('handoff.session.card')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('handoff.session.error')), findsOneWidget);
      expect(find.byKey(const Key('handoff.session.accept')), findsNothing);
      expect(find.text('Try again'), findsWidgets);
    },
  );

  testWidgets('handoff offer reuses identity only for the same payload', (
    tester,
  ) async {
    final sessions = FakeHandoffSessionRepository()
      ..nextError = const HandoffSessionException(
        HandoffSessionErrorCode.network,
      );
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        householdSyncRepository: _FakeHouseholdSyncRepository(
          snapshot: HouseholdSyncSnapshot(
            household: _session.household,
            caregiver: _session.caregiver,
            members: const [
              Caregiver(id: 'user-1', displayName: 'Alex'),
              Caregiver(id: 'user-2', displayName: 'Sam'),
              Caregiver(id: 'user-3', displayName: 'Jordan'),
            ],
          ),
        ),
        handoffRepository: _FakeHandoffRepository(
          snapshot: HandoffSnapshot(
            handoff: _handoffTemplate(),
            isFromCache: false,
            hasPendingWrites: false,
          ),
        ),
        handoffSessionRepository: sessions,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    final offer = find.byKey(const Key('handoff.session.offer'));
    await tester.ensureVisible(offer);
    await tester.tap(offer);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('handoff.offer.save')));
    await tester.pumpAndSettle();
    sessions.nextError = const HandoffSessionException(
      HandoffSessionErrorCode.network,
    );
    await tester.tap(find.byKey(const Key('handoff.offer.save')));
    await tester.pumpAndSettle();
    expect(sessions.calls, hasLength(2));
    expect(
      sessions.calls[0]['clientMutationID'],
      sessions.calls[1]['clientMutationID'],
    );

    sessions.nextError = const HandoffSessionException(
      HandoffSessionErrorCode.network,
    );
    await tester.tap(find.byKey(const Key('handoff.offer.recipient')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jordan').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('handoff.offer.save')));
    await tester.pumpAndSettle();
    expect(sessions.calls, hasLength(3));
    expect(
      sessions.calls[2]['clientMutationID'],
      isNot(sessions.calls[1]['clientMutationID']),
    );
  });

  testWidgets('Japanese handoff offer is usable at 390pt 3x', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final sessions = FakeHandoffSessionRepository();
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        localeRepository: FakeLocaleRepository(AppLocale.japanese),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        householdSyncRepository: _FakeHouseholdSyncRepository(
          snapshot: HouseholdSyncSnapshot(
            household: _session.household,
            caregiver: _session.caregiver,
            members: const [
              Caregiver(id: 'user-1', displayName: 'Alex'),
              Caregiver(id: 'user-2', displayName: 'Sam'),
            ],
          ),
        ),
        handoffRepository: _FakeHandoffRepository(
          snapshot: HandoffSnapshot(
            handoff: _handoffTemplate(),
            isFromCache: false,
            hasPendingWrites: false,
          ),
        ),
        handoffSessionRepository: sessions,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('プロフィール').last);
    await tester.pumpAndSettle();
    final offer = find.byKey(const Key('handoff.session.offer'));
    await tester.ensureVisible(offer);
    await tester.tap(offer);
    await tester.pumpAndSettle();
    expect(find.textContaining('承認が必要'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('handoff.offer.save')));
    await tester.tap(find.byKey(const Key('handoff.offer.save')));
    await tester.pumpAndSettle();

    expect(sessions.calls.single['action'], 'offer');
    expect(sessions.calls.single['expectedHandoffRevision'], 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('true leave blocker preserves membership and retry identity', (
    tester,
  ) async {
    final household = FakeHouseholdRepository(restoredSession: _session);
    final exit = FakeMembershipExitRepository()
      ..nextError = const MembershipExitException(
        MembershipExitErrorCode.blocked,
        diagnosticCode: 'pendingTransfer',
      );
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: household,
        membershipExitRepository: exit,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('household.leave')));
    await tester.tap(find.byKey(const Key('household.leave')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('household.leaveConfirm')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('pending responsibility transfer'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('household.home')), findsOneWidget);
    expect(household.leaveCalls, 0);

    await tester.tap(find.byKey(const Key('household.leave')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('household.leaveConfirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('start.shell')), findsOneWidget);
    expect(household.leaveCalls, 1);
    expect(exit.calls, hasLength(2));
    expect(
      exit.calls[0]['clientMutationID'],
      exit.calls[1]['clientMutationID'],
    );
  });

  testWidgets('Updates renders v2 handoff without task or pet invention', (
    tester,
  ) async {
    final event = _handoffCollaborationEvent();
    await tester.pumpWidget(
      _testApp(
        bootstrap: FakeBootstrapRepository(),
        householdRepository: FakeHouseholdRepository(restoredSession: _session),
        collaborationEventRepository: FakeCollaborationEventRepository(
          events: [event],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Updates').last);
    await tester.pumpAndSettle();

    expect(find.text('Handoff offered'), findsOneWidget);
    expect(find.text('Coverage handoff session'), findsOneWidget);
    expect(find.textContaining('Alex · Sam'), findsOneWidget);
    expect(find.textContaining('Unknown pet'), findsNothing);
  });
}

ResponsibilityTransfer _pendingResponsibilityTransfer() =>
    ResponsibilityTransfer(
      id: 'transfer-a',
      taskId: 'claimed-task',
      kind: ResponsibilityTransferKind.reassign,
      status: ResponsibilityTransferStatus.pending,
      requestedById: 'user-2',
      requestedByNameSnapshot: 'Sam',
      consentById: 'user-1',
      consentByNameSnapshot: 'Alex',
      responsibilityFromId: 'user-2',
      responsibilityFromNameSnapshot: 'Sam',
      responsibilityToId: 'user-1',
      responsibilityToNameSnapshot: 'Alex',
      taskRevisionAtProposal: 1,
      createdAt: DateTime.utc(2026, 8, 17),
      resolvedById: null,
      resolvedByNameSnapshot: null,
      resolvedAt: null,
      resultingTaskRevision: null,
      revision: 1,
    );

HouseholdHandoff _handoffTemplate({
  int revision = 2,
  String careInstructions = 'Dinner at 18:00',
}) => HouseholdHandoff(
  careInstructions: careInstructions,
  emergencyContactName: 'Taylor',
  emergencyContactPhone: '090-0000-0000',
  veterinaryHospitalName: 'Central Animal Hospital',
  veterinaryHospitalPhone: '03-0000-0000',
  revision: revision,
  updatedById: 'user-1',
  updatedByNameSnapshot: 'Alex',
  updatedAt: DateTime.utc(2026, 8, 17),
);

HandoffSession _offeredHandoffSession() => HandoffSession(
  id: 'session-a',
  versionId: 'v000002',
  handoffRevisionSnapshot: 2,
  creatorId: 'user-2',
  creatorNameSnapshot: 'Sam',
  recipientId: 'user-1',
  recipientNameSnapshot: 'Alex',
  timeZoneIdentifierSnapshot: 'Asia/Tokyo',
  plannedStartAt: DateTime.now().add(const Duration(hours: 1)),
  plannedEndAt: DateTime.now().add(const Duration(days: 1)),
  status: HandoffSessionStatus.offered,
  offeredAt: DateTime.now(),
  acceptedById: null,
  acceptedByNameSnapshot: null,
  acceptedAt: null,
  declinedById: null,
  declinedByNameSnapshot: null,
  declinedAt: null,
  cancelledById: null,
  cancelledByNameSnapshot: null,
  cancelledAt: null,
  closedById: null,
  closedByNameSnapshot: null,
  closedAt: null,
  resolutionReason: null,
  revision: 1,
);

HandoffVersion _pinnedHandoffVersion() => HandoffVersion(
  id: 'v000002',
  sourceHandoffRevision: 2,
  careInstructions: 'Pinned dinner at 17:00',
  emergencyContactName: 'Pinned Taylor',
  emergencyContactPhone: '090-1111-1111',
  veterinaryHospitalName: 'Pinned Animal Hospital',
  veterinaryHospitalPhone: '03-1111-1111',
  updatedById: 'user-2',
  updatedByNameSnapshot: 'Sam',
  updatedAt: DateTime.utc(2026, 8, 16),
  materializedAt: DateTime.utc(2026, 8, 17),
);

CollaborationEvent _handoffCollaborationEvent() => CollaborationEvent(
  id: _collaborationEventId('e'),
  sourceId: 'session-a',
  sourceRevision: 1,
  action: CollaborationEventAction.handoffOffered,
  actorId: 'user-1',
  actorNameSnapshot: 'Alex',
  targetMemberId: null,
  targetMemberNameSnapshot: null,
  requestId: null,
  assignmentMode: null,
  petId: null,
  petNameSnapshot: null,
  taskTitleSnapshot: null,
  taskCategorySnapshot: null,
  taskPrioritySnapshot: null,
  taskDueTime: null,
  stateAfter: null,
  occurredAt: DateTime.now(),
  recordedAt: DateTime.now(),
  sourceType: CollaborationEventSourceType.handoffSession,
  handoffCreatorId: 'user-1',
  handoffCreatorNameSnapshot: 'Alex',
  handoffRecipientId: 'user-2',
  handoffRecipientNameSnapshot: 'Sam',
  handoffStatus: 'offered',
);

Future<void> _openRecordSection(WidgetTester tester, Key entryKey) async {
  await tester.tap(find.text('Records').last);
  await tester.pumpAndSettle();
  if (find.byKey(entryKey).evaluate().isEmpty &&
      find.byKey(const Key('records.back')).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(const Key('records.back')));
    await tester.pumpAndSettle();
  }
  final entry = find.byKey(entryKey);
  await tester.ensureVisible(entry);
  await tester.tap(entry);
  await tester.pumpAndSettle();
}

String _collaborationEventId(String hexadecimalDigit) =>
    List.filled(64, hexadecimalDigit).join();

CollaborationEvent _collaborationEvent({
  required String id,
  required DateTime occurredAt,
  String title = 'Evening walk',
}) => CollaborationEvent(
  id: id,
  sourceId: 'task-$id',
  sourceRevision: 2,
  action: CollaborationEventAction.taskAccepted,
  actorId: 'member-b',
  actorNameSnapshot: 'Caregiver with a deliberately long display name',
  targetMemberId: 'member-a',
  targetMemberNameSnapshot: 'Caregiver A',
  requestId: 'request-$id',
  assignmentMode: 'direct',
  petId: legacyPrimaryPetId,
  petNameSnapshot: 'Mugi with a long household pet name',
  taskTitleSnapshot: title,
  taskCategorySnapshot: 'walking',
  taskPrioritySnapshot: 'normal',
  taskDueTime: occurredAt.add(const Duration(hours: 1)),
  stateAfter: CollaborationTaskState.claimed,
  occurredAt: occurredAt,
  recordedAt: occurredAt,
);

final class _ScriptedCollaborationRepository
    implements CollaborationEventRepository {
  _ScriptedCollaborationRepository({
    this.snapshot,
    this.page,
    this.error,
    this.pageError,
    this.readCursorErrorsBeforeSuccess = 0,
    this.readSnapshot,
    this.readCursorNeverEmits = false,
  });

  final CollaborationEventSnapshot? snapshot;
  final CollaborationEventPage? page;
  final Object? error;
  final Object? pageError;
  int readCursorErrorsBeforeSuccess;
  final CollaborationReadCursorSnapshot? readSnapshot;
  final bool readCursorNeverEmits;
  final List<(String, String, CollaborationReadCursor)> markedRead = [];

  @override
  Stream<CollaborationEventSnapshot> observeRecent(
    String householdId, {
    int limit = 50,
  }) => error == null
      ? Stream.value(
          snapshot ??
              const CollaborationEventSnapshot(
                events: [],
                isFromCache: false,
                droppedEventCount: 0,
              ),
        )
      : Stream.error(error!);

  @override
  Future<CollaborationEventPage> loadPage(
    String householdId, {
    int limit = 50,
    CollaborationPageCursor? after,
  }) async {
    if (pageError case final error?) throw error;
    return page ??
        const CollaborationEventPage(
          events: [],
          nextCursor: null,
          droppedEventCount: 0,
        );
  }

  @override
  Stream<CollaborationReadCursorSnapshot> observeReadCursor(
    String householdId,
    String memberId,
  ) {
    if (readCursorNeverEmits) return const Stream.empty();
    if (readCursorErrorsBeforeSuccess > 0) {
      readCursorErrorsBeforeSuccess -= 1;
      return Stream.error(
        const CollaborationEventRepositoryException(
          CollaborationEventRepositoryErrorCode.network,
        ),
      );
    }
    return Stream.value(
      readSnapshot ??
          const CollaborationReadCursorSnapshot(
            cursor: null,
            isFromCache: false,
            hasPendingWrites: false,
          ),
    );
  }

  @override
  Future<void> markRead(
    String householdId,
    String memberId,
    CollaborationReadCursor cursor,
  ) async => markedRead.add((householdId, memberId, cursor));

  @override
  Future<void> stopObserving() async {}
}

bool _updatesBadgeVisible(WidgetTester tester) => tester
    .widget<Badge>(find.byKey(const Key('updates.unreadBadge')))
    .isLabelVisible;

final class _ControlledReadCollaborationRepository
    implements CollaborationEventRepository {
  _ControlledReadCollaborationRepository({
    required this.event,
    required this.reconnectSnapshot,
  });

  final CollaborationEvent event;
  CollaborationReadCursorSnapshot reconnectSnapshot;
  StreamController<CollaborationReadCursorSnapshot>? _readController;

  void emitRead(CollaborationReadCursorSnapshot snapshot) {
    _readController?.add(snapshot);
  }

  void failRead(Object error) {
    _readController?.addError(error);
  }

  @override
  Stream<CollaborationEventSnapshot> observeRecent(
    String householdId, {
    int limit = 50,
  }) => Stream.value(
    CollaborationEventSnapshot(
      events: [event],
      isFromCache: false,
      droppedEventCount: 0,
    ),
  );

  @override
  Stream<CollaborationReadCursorSnapshot> observeReadCursor(
    String householdId,
    String memberId,
  ) {
    late final StreamController<CollaborationReadCursorSnapshot> controller;
    controller = StreamController(
      onListen: () => controller.add(reconnectSnapshot),
    );
    _readController = controller;
    return controller.stream;
  }

  @override
  Future<void> markRead(
    String householdId,
    String memberId,
    CollaborationReadCursor cursor,
  ) async {}

  @override
  Future<CollaborationEventPage> loadPage(
    String householdId, {
    int limit = 50,
    CollaborationPageCursor? after,
  }) async => const CollaborationEventPage(
    events: [],
    nextCursor: null,
    droppedEventCount: 0,
  );

  @override
  Future<void> stopObserving() async {
    await _readController?.close();
  }
}

final class _TestCollaborationPageCursor implements CollaborationPageCursor {
  const _TestCollaborationPageCursor();
}

class _FailingLocaleRepository implements LocaleRepository {
  @override
  Future<AppLocale> load() => Future.error(StateError('unavailable'));

  @override
  Future<void> save(AppLocale locale) async {}
}

class _SaveFailingLocaleRepository implements LocaleRepository {
  @override
  Future<AppLocale> load() async => AppLocale.english;

  @override
  Future<void> save(AppLocale locale) => Future.error(StateError('full'));
}

Widget _testApp({
  required BootstrapRepository bootstrap,
  LocaleRepository? localeRepository,
  HouseholdRepository? householdRepository,
  CareTaskRepository? careTaskRepository,
  CareTaskMutationRepository? careTaskMutationRepository,
  HouseholdSyncRepository? householdSyncRepository,
  PetRepository? petRepository,
  MedicationRepository? medicationRepository,
  NotificationRepository? notificationRepository,
  NotificationDeviceRepository? notificationDeviceRepository,
  NotificationPreferencesRepository? notificationPreferencesRepository,
  NotificationInboxRepository? notificationInboxRepository,
  NotificationDeliveryEvidenceRepository? notificationDeliveryRepository,
  NotificationInteractionRepository? notificationInteractionRepository,
  NotificationLifecycleSource? notificationLifecycleSource,
  HealthRepository? healthRepository,
  HandoffRepository? handoffRepository,
  HandoffSessionRepository? handoffSessionRepository,
  TaskResponsibilityRepository? taskResponsibilityRepository,
  MembershipExitRepository? membershipExitRepository,
  ReportShareRepository? reportShareRepository,
  CollaborationEventRepository? collaborationEventRepository,
}) {
  final resolvedNotification =
      notificationRepository ?? _FakeNotificationRepository();
  return ProviderScope(
    overrides: [
      bootstrapRepositoryProvider.overrideWithValue(bootstrap),
      localeRepositoryProvider.overrideWithValue(
        localeRepository ?? FakeLocaleRepository(AppLocale.english),
      ),
      householdRepositoryProvider.overrideWithValue(
        householdRepository ?? FakeHouseholdRepository(),
      ),
      localTimeZoneRepositoryProvider.overrideWithValue(
        const _FakeLocalTimeZoneRepository(),
      ),
      householdSyncRepositoryProvider.overrideWithValue(
        householdSyncRepository ?? _FakeHouseholdSyncRepository(),
      ),
      careTaskRepositoryProvider.overrideWithValue(
        careTaskRepository ?? _FakeCareTaskRepository(),
      ),
      careTaskMutationRepositoryProvider.overrideWithValue(
        careTaskMutationRepository ?? _FakeCareTaskMutationRepository(),
      ),
      petRepositoryProvider.overrideWithValue(
        petRepository ?? _FakePetRepository(),
      ),
      medicationRepositoryProvider.overrideWithValue(
        medicationRepository ?? _FakeMedicationRepository(),
      ),
      notificationRepositoryProvider.overrideWithValue(resolvedNotification),
      notificationDeviceRepositoryProvider.overrideWithValue(
        notificationDeviceRepository ??
            LegacyNotificationDeviceRepository(resolvedNotification),
      ),
      notificationPreferencesRepositoryProvider.overrideWithValue(
        notificationPreferencesRepository ??
            FakeNotificationPreferencesRepository(
              const NotificationPreferencesSnapshot(
                preferences: null,
                authority: NotificationPreferenceAuthority.missingDefaults,
              ),
            ),
      ),
      notificationInboxRepositoryProvider.overrideWithValue(
        notificationInboxRepository ?? FakeNotificationInboxRepository(),
      ),
      notificationDeliveryEvidenceRepositoryProvider.overrideWithValue(
        notificationDeliveryRepository ??
            FakeNotificationDeliveryEvidenceRepository(
              const NotificationProviderEvidenceSnapshot(
                evidence: NotificationProviderEvidence
                    .notVerifiedForCurrentInstallation,
                authority: NotificationObservationAuthority.serverConfirmed,
                updatedAt: null,
                attemptCount: 0,
              ),
            ),
      ),
      notificationInteractionRepositoryProvider.overrideWithValue(
        notificationInteractionRepository ??
            FakeNotificationInteractionRepository(),
      ),
      if (notificationLifecycleSource != null)
        notificationLifecycleSourceProvider.overrideWithValue(
          notificationLifecycleSource,
        ),
      healthRepositoryProvider.overrideWithValue(
        healthRepository ?? _FakeHealthRepository(),
      ),
      handoffRepositoryProvider.overrideWithValue(
        handoffRepository ?? _FakeHandoffRepository(),
      ),
      handoffSessionRepositoryProvider.overrideWithValue(
        handoffSessionRepository ?? FakeHandoffSessionRepository(),
      ),
      taskResponsibilityRepositoryProvider.overrideWithValue(
        taskResponsibilityRepository ?? FakeTaskResponsibilityRepository(),
      ),
      membershipExitRepositoryProvider.overrideWithValue(
        membershipExitRepository ?? FakeMembershipExitRepository(),
      ),
      reportShareRepositoryProvider.overrideWithValue(
        reportShareRepository ?? _FakeReportShareRepository(),
      ),
      collaborationEventRepositoryProvider.overrideWithValue(
        collaborationEventRepository ?? FakeCollaborationEventRepository(),
      ),
    ],
    child: const CopawApp(),
  );
}

final class _FakeNotificationRepository implements NotificationRepository {
  _FakeNotificationRepository({
    this.status = NotificationPermissionStatus.authorized,
    NotificationPermissionStatus? requestedStatus,
    this.disableError,
  }) : requestedStatus = requestedStatus ?? status;

  NotificationPermissionStatus status;
  final NotificationPermissionStatus requestedStatus;
  final Object? disableError;
  int settingsCalls = 0;
  int disableCalls = 0;

  @override
  Future<NotificationPermissionStatus> configure(String householdId) async =>
      status;

  @override
  Future<NotificationPermissionStatus> requestPermission(
    String householdId,
  ) async {
    status = requestedStatus;
    return status;
  }

  @override
  Future<void> openSettings() async {
    settingsCalls += 1;
  }

  @override
  Future<void> disable() async {
    disableCalls += 1;
    if (disableError case final error?) throw error;
  }

  @override
  Future<void> stop() async {}
}

final class _FakeHealthRepository implements HealthRepository {
  _FakeHealthRepository({this.snapshot = const HealthSnapshot([])});

  final HealthSnapshot snapshot;
  String? createdPetId;
  HealthRecordType? createdType;
  String? createdDetail;
  double? createdWaterMilliliters;
  DailyHealthCheckIn? createdDailyCheckIn;

  @override
  Stream<HealthSnapshot> observeHealth(String householdId) =>
      Stream.value(snapshot);

  @override
  Future<void> createRecord({
    required String householdId,
    required String petId,
    required String petName,
    required HealthRecordType type,
    required DateTime recordedAt,
    required String timeZoneIdentifier,
    required String? detail,
    required double? weightKilograms,
    double? waterMilliliters,
    DailyHealthCheckIn? dailyCheckIn,
    required String createdById,
    required String createdByName,
  }) async {
    createdPetId = petId;
    createdType = type;
    createdDetail = detail;
    createdWaterMilliliters = waterMilliliters;
    createdDailyCheckIn = dailyCheckIn;
  }

  @override
  Future<void> stopObserving() async {}
}

final class _FakeHandoffRepository implements HandoffRepository {
  _FakeHandoffRepository({
    this.snapshot = const HandoffSnapshot(
      handoff: null,
      isFromCache: false,
      hasPendingWrites: false,
    ),
    this.saveOutcomes = const [],
  });

  HandoffSnapshot snapshot;
  final List<Object?> saveOutcomes;
  final _controller = StreamController<HandoffSnapshot>.broadcast();
  String? savedCareInstructions;
  String? savedEmergencyContactName;
  String? savedUpdatedById;
  int? savedExpectedRevision;
  final savedExpectedRevisions = <int?>[];
  int saveCalls = 0;

  @override
  Stream<HandoffSnapshot> observeHandoff(String householdId) async* {
    yield snapshot;
    yield* _controller.stream;
  }

  void addSnapshot(HandoffSnapshot next) {
    snapshot = next;
    _controller.add(next);
  }

  @override
  Future<void> saveHandoff({
    required String householdId,
    required int? expectedRevision,
    required String careInstructions,
    required String emergencyContactName,
    required String emergencyContactPhone,
    required String veterinaryHospitalName,
    required String veterinaryHospitalPhone,
    required String updatedById,
    required String updatedByName,
  }) async {
    final callIndex = saveCalls;
    saveCalls += 1;
    savedExpectedRevision = expectedRevision;
    savedExpectedRevisions.add(expectedRevision);
    savedCareInstructions = careInstructions;
    savedEmergencyContactName = emergencyContactName;
    savedUpdatedById = updatedById;
    final outcome = saveOutcomes.isEmpty ? null : saveOutcomes[callIndex];
    if (outcome case final error?) throw error;
  }

  @override
  Future<void> stopObserving() async {}
}

final class _FakeReportShareRepository implements ReportShareRepository {
  _FakeReportShareRepository({this.remainingFailures = 0});

  int remainingFailures;
  int calls = 0;
  PetCareReport? report;

  @override
  Future<void> sharePdf({
    required PetCareReport report,
    required AppLocale locale,
    required Rect sharePositionOrigin,
  }) async {
    calls += 1;
    this.report = report;
    if (remainingFailures > 0) {
      remainingFailures -= 1;
      throw StateError('share unavailable');
    }
  }
}

const _session = HouseholdSession(
  household: Household(
    id: 'household-1',
    name: 'Mochi Family',
    inviteCode: 'ABC234',
    petName: 'Mochi',
    timeZoneIdentifier: 'Asia/Tokyo',
  ),
  caregiver: Caregiver(id: 'user-1', displayName: 'Alex'),
);

final class FakeHouseholdRepository implements HouseholdRepository {
  FakeHouseholdRepository({
    this.restoredSession,
    this.restoreError,
    this.joinError,
    this.leaveError,
  });

  final HouseholdSession? restoredSession;
  final Object? restoreError;
  final Object? joinError;
  final Object? leaveError;
  String? createdTimeZone;
  int leaveCalls = 0;

  @override
  Future<HouseholdSession> createHousehold({
    required String householdName,
    required String petName,
    required String caregiverName,
    required String timeZoneIdentifier,
  }) async {
    createdTimeZone = timeZoneIdentifier;
    return HouseholdSession(
      household: Household(
        id: 'household-1',
        name: householdName,
        inviteCode: 'ABC234',
        petName: petName,
        timeZoneIdentifier: timeZoneIdentifier,
      ),
      caregiver: Caregiver(id: 'user-1', displayName: caregiverName),
    );
  }

  @override
  Future<HouseholdSession> joinHousehold({
    required String inviteCode,
    required String caregiverName,
  }) async {
    if (joinError case final Object error) throw error;
    return _session;
  }

  @override
  Future<void> leaveHousehold() async {
    leaveCalls += 1;
    if (leaveError case final Object error) throw error;
  }

  @override
  Future<HouseholdSession?> restoreSession() async {
    if (restoreError case final Object error) throw error;
    return restoredSession;
  }
}

final class _FakeLocalTimeZoneRepository implements LocalTimeZoneRepository {
  const _FakeLocalTimeZoneRepository();

  @override
  Future<String> loadIdentifier() async => 'Asia/Tokyo';
}

final class _FakeHouseholdSyncRepository implements HouseholdSyncRepository {
  _FakeHouseholdSyncRepository({
    this.snapshot,
    this.observeError,
    this.recoverOnRetry = false,
    this.updateError,
  });

  final HouseholdSyncSnapshot? snapshot;
  final Object? observeError;
  final bool recoverOnRetry;
  Object? updateError;
  Completer<void>? updateCompleter;
  int stopCalls = 0;
  int observeCalls = 0;
  String? updatedHouseholdName;
  String? updatedCaregiverName;
  int updateCalls = 0;

  @override
  Stream<HouseholdSyncSnapshot> observeSession({
    required String householdId,
    required String userId,
  }) {
    observeCalls += 1;
    if (observeError case final Object error) {
      if (!recoverOnRetry || observeCalls == 1) return Stream.error(error);
    }
    return snapshot == null ? const Stream.empty() : Stream.value(snapshot!);
  }

  @override
  Future<void> stopObserving() async {
    stopCalls += 1;
  }

  @override
  Future<void> updateProfile({
    required String householdId,
    required String userId,
    required String householdName,
    required String petName,
    required String caregiverName,
  }) async {
    updateCalls += 1;
    if (updateError case final Object error) throw error;
    await updateCompleter?.future;
    updatedHouseholdName = householdName;
    updatedCaregiverName = caregiverName;
  }
}

final class _FakeCareTaskRepository
    implements CareTaskRepository, PetBoundCareTaskWriter {
  _FakeCareTaskRepository({
    this.failCreate = false,
    this.snapshot = const CareTaskSnapshot(
      routines: <CareRoutine>[],
      tasks: <CareTask>[],
    ),
    this.observeError,
  });

  final bool failCreate;
  final CareTaskSnapshot snapshot;
  final Object? observeError;
  String? createdTitle;
  String? createdRoutineTitle;
  CareCategory? createdCategory;
  DateTime? createdDueTime;
  CareRoutineFrequency? createdRoutineFrequency;
  List<int>? createdRoutineWeekdays;
  DateTime? createdRoutineStartDate;
  int? createdRoutineHour;
  int? createdRoutineMinute;
  int stopCalls = 0;
  int observeCalls = 0;
  String? createdPetId;
  String? createdPetName;

  @override
  Stream<CareTaskSnapshot> observeCare(String householdId) {
    observeCalls += 1;
    if (observeError case final Object error) return Stream.error(error);
    return Stream.value(snapshot);
  }

  @override
  Future<String> createOneOffTask({
    required String householdId,
    required String title,
    required CareCategory category,
    required DateTime dueTime,
    required CarePriority priority,
    required String createdById,
    required String createdByName,
  }) async {
    if (failCreate) throw StateError('offline');
    createdTitle = title;
    createdCategory = category;
    createdDueTime = dueTime;
    return 'task-1';
  }

  @override
  Future<String> createOneOffTaskForPet({
    required String householdId,
    required String petId,
    required String petName,
    required String title,
    required CareCategory category,
    required DateTime dueTime,
    required CarePriority priority,
    required String createdById,
    required String createdByName,
  }) async {
    createdPetId = petId;
    createdPetName = petName;
    return createOneOffTask(
      householdId: householdId,
      title: title,
      category: category,
      dueTime: dueTime,
      priority: priority,
      createdById: createdById,
      createdByName: createdByName,
    );
  }

  @override
  Future<String> createRoutine({
    required String householdId,
    required String title,
    required CareCategory category,
    required CarePriority priority,
    required CareRoutineFrequency frequency,
    required List<int> weekdays,
    required int hour,
    required int minute,
    required DateTime startDate,
    required String timeZoneIdentifier,
    required String createdById,
    required String createdByName,
  }) async {
    createdRoutineTitle = title;
    createdCategory = category;
    createdRoutineFrequency = frequency;
    createdRoutineWeekdays = List<int>.of(weekdays);
    createdRoutineStartDate = startDate;
    createdRoutineHour = hour;
    createdRoutineMinute = minute;
    return 'routine-1';
  }

  @override
  Future<String> createRoutineForPet({
    required String householdId,
    required String petId,
    required String petName,
    required String title,
    required CareCategory category,
    required CarePriority priority,
    required CareRoutineFrequency frequency,
    required List<int> weekdays,
    required int hour,
    required int minute,
    required DateTime startDate,
    required String timeZoneIdentifier,
    required String createdById,
    required String createdByName,
  }) async {
    createdPetId = petId;
    createdPetName = petName;
    return createRoutine(
      householdId: householdId,
      title: title,
      category: category,
      priority: priority,
      frequency: frequency,
      weekdays: weekdays,
      hour: hour,
      minute: minute,
      startDate: startDate,
      timeZoneIdentifier: timeZoneIdentifier,
      createdById: createdById,
      createdByName: createdByName,
    );
  }

  @override
  Future<void> stopObserving() async {
    stopCalls += 1;
  }
}

final class _FakePetRepository implements PetRepository {
  _FakePetRepository({
    this.snapshot = const PetSnapshot(
      pets: [
        Pet(
          id: legacyPrimaryPetId,
          name: 'Mochi',
          species: null,
          isArchived: false,
          createdAt: null,
          updatedAt: null,
        ),
      ],
    ),
    this.observeError,
  });

  final PetSnapshot snapshot;
  final Object? observeError;
  int observeCalls = 0;
  int stopCalls = 0;
  String? createdName;
  String? renamedPetId;
  String? archivedPetId;

  @override
  Stream<PetSnapshot> observePets(String householdId) {
    observeCalls += 1;
    if (observeError case final Object error) return Stream.error(error);
    return Stream.value(snapshot);
  }

  @override
  Future<String> createPet({
    required String householdId,
    required String name,
    required PetSpecies? species,
  }) async {
    createdName = name;
    return 'pet-new';
  }

  @override
  Future<void> renamePet({
    required String householdId,
    required String petId,
    required String name,
  }) async {
    renamedPetId = petId;
  }

  @override
  Future<void> archivePet({
    required String householdId,
    required String petId,
  }) async {
    archivedPetId = petId;
  }

  @override
  Future<void> stopObserving() async {
    stopCalls += 1;
  }
}

final class _FakeMedicationRepository implements MedicationRepository {
  _FakeMedicationRepository({this.snapshots = const [], this.actionError});

  final List<MedicationSnapshot> snapshots;
  final Object? actionError;
  int observeCalls = 0;
  int administerCalls = 0;

  @override
  Stream<MedicationSnapshot> observeMedication(String householdId) {
    final index = observeCalls < snapshots.length
        ? observeCalls
        : snapshots.length - 1;
    observeCalls += 1;
    return Stream.value(
      index < 0
          ? const MedicationSnapshot(
              medications: [],
              schedules: [],
              occurrences: [],
              isServerConfirmed: true,
            )
          : snapshots[index],
    );
  }

  @override
  Future<void> administer({
    required String householdId,
    required PlannedMedicationOccurrence occurrence,
  }) async {
    administerCalls += 1;
    if (actionError case final Object error) throw error;
  }

  @override
  Future<void> claim({
    required String householdId,
    required PlannedMedicationOccurrence occurrence,
  }) async {
    if (actionError case final Object error) throw error;
  }

  @override
  Future<String> createPlan({
    required String householdId,
    required String petId,
    required String medicationName,
    String? purpose,
    String? possibleSideEffects,
    required String effectiveFromLocalDate,
    required List<int> weekdays,
    required List<MedicationPlanSlotInput> slots,
  }) async => 'medication-1';

  @override
  Future<void> replacePlan({
    required String householdId,
    required Medication medication,
    required String medicationName,
    String? purpose,
    String? possibleSideEffects,
    required String effectiveFromLocalDate,
    required List<int> weekdays,
    required List<MedicationPlanSlotInput> slots,
  }) async {}

  @override
  Future<void> skip({
    required String householdId,
    required PlannedMedicationOccurrence occurrence,
    required MedicationSkipReasonCode reasonCode,
    String? reasonNote,
  }) async {}

  @override
  Future<void> stopObserving() async {}

  @override
  Future<void> stopPlan({
    required String householdId,
    required Medication medication,
    required String effectiveUntilLocalDate,
  }) async {}
}

MedicationSnapshot _medicationSnapshot({
  bool serverConfirmed = true,
  MedicationOccurrence? occurrence,
}) => MedicationSnapshot(
  medications: const [
    Medication(
      id: 'med-1',
      petId: legacyPrimaryPetId,
      displayName: 'Tablet A',
      purpose: 'Cardiac support',
      possibleSideEffects: 'Watch for appetite changes',
      isActive: true,
      currentScheduleVersion: 1,
      currentScheduleVersionId: 'v000001',
      revision: 0,
    ),
  ],
  schedules: [_todayMedicationSchedule()],
  occurrences: occurrence == null ? const [] : [occurrence],
  isServerConfirmed: serverConfirmed,
);

MedicationSnapshot _twoPetMedicationSnapshot() => MedicationSnapshot(
  medications: const [
    Medication(
      id: 'med-1',
      petId: legacyPrimaryPetId,
      displayName: 'Tablet A',
      purpose: 'Cardiac support',
      possibleSideEffects: 'Watch for appetite changes',
      isActive: true,
      currentScheduleVersion: 1,
      currentScheduleVersionId: 'v000001',
      revision: 0,
    ),
    Medication(
      id: 'med-luna',
      petId: 'pet-nori',
      displayName: 'Eye drops',
      isActive: true,
      currentScheduleVersion: 1,
      currentScheduleVersionId: 'v000001',
      revision: 0,
    ),
    Medication(
      id: 'med-past',
      petId: legacyPrimaryPetId,
      displayName: 'Antibiotic course',
      purpose: 'Past infection treatment',
      possibleSideEffects: 'Course completed',
      isActive: false,
      currentScheduleVersion: 1,
      currentScheduleVersionId: 'v000001',
      revision: 1,
    ),
  ],
  schedules: [
    _todayMedicationSchedule(),
    MedicationScheduleVersion(
      id: 'v000001',
      medicationId: 'med-luna',
      version: 1,
      petId: 'pet-nori',
      petNameSnapshot: 'Luna',
      medicationNameSnapshot: 'Eye drops',
      weekdays: const [1, 2, 3, 4, 5, 6, 7],
      slots: const [
        MedicationSlot(
          slotId: '0000',
          hour: 0,
          minute: 0,
          doseText: '1 drop',
          instructions: 'Left eye',
        ),
      ],
      timeZoneIdentifier: 'Asia/Tokyo',
      effectiveFromLocalDate: '2020-01-01',
      effectiveUntilLocalDate: null,
    ),
    MedicationScheduleVersion(
      id: 'v000001',
      medicationId: 'med-past',
      version: 1,
      petId: legacyPrimaryPetId,
      petNameSnapshot: 'Mochi',
      medicationNameSnapshot: 'Antibiotic course',
      weekdays: const [1, 2, 3, 4, 5, 6, 7],
      slots: const [
        MedicationSlot(
          slotId: '0800',
          hour: 8,
          minute: 0,
          doseText: '1 capsule',
          instructions: 'After breakfast',
        ),
      ],
      timeZoneIdentifier: 'Asia/Tokyo',
      effectiveFromLocalDate: '2026-07-01',
      effectiveUntilLocalDate: '2026-07-07',
    ),
  ],
  occurrences: const [],
  isServerConfirmed: true,
);

MedicationScheduleVersion _todayMedicationSchedule() {
  return MedicationScheduleVersion(
    id: 'v000001',
    medicationId: 'med-1',
    version: 1,
    petId: legacyPrimaryPetId,
    petNameSnapshot: 'Mochi',
    medicationNameSnapshot: 'Tablet A',
    weekdays: const [1, 2, 3, 4, 5, 6, 7],
    slots: const [
      MedicationSlot(
        slotId: '0000',
        hour: 0,
        minute: 0,
        doseText: '1 tablet',
        instructions: 'With food',
      ),
    ],
    timeZoneIdentifier: 'Asia/Tokyo',
    effectiveFromLocalDate: '2020-01-01',
    effectiveUntilLocalDate: null,
  );
}

MedicationScheduleVersion _longTodayMedicationSchedule({
  required String petName,
  required String medicationName,
  required String doseText,
  required String instructions,
}) => MedicationScheduleVersion(
  id: 'v000001',
  medicationId: 'med-1',
  version: 1,
  petId: legacyPrimaryPetId,
  petNameSnapshot: petName,
  medicationNameSnapshot: medicationName,
  weekdays: const [1, 2, 3, 4, 5, 6, 7],
  slots: [
    MedicationSlot(
      slotId: '0000',
      hour: 0,
      minute: 0,
      doseText: doseText,
      instructions: instructions,
    ),
  ],
  timeZoneIdentifier: 'Asia/Tokyo',
  effectiveFromLocalDate: '2020-01-01',
  effectiveUntilLocalDate: null,
);

String _todayMedicationId() {
  final tokyoNow = DateTime.now().toUtc().add(const Duration(hours: 9));
  final date =
      '${tokyoNow.year.toString().padLeft(4, '0')}-'
      '${tokyoNow.month.toString().padLeft(2, '0')}-'
      '${tokyoNow.day.toString().padLeft(2, '0')}';
  return 'med-1_v000001_${date}_0000';
}

MedicationOccurrence _medicationOccurrence({
  required MedicationOutcomeStatus outcome,
  required bool isServerConfirmed,
  MedicationSkipReasonCode? reason,
  String? reasonNote,
}) {
  final tokyoNow = DateTime.now().toUtc().add(const Duration(hours: 9));
  final dueAt = DateTime.utc(
    tokyoNow.year,
    tokyoNow.month,
    tokyoNow.day,
  ).subtract(const Duration(hours: 9));
  return MedicationOccurrence(
    id: _todayMedicationId(),
    medicationId: 'med-1',
    scheduleVersionId: 'v000001',
    scheduleVersion: 1,
    slotId: '0000',
    localDate: _todayMedicationId().split('_')[2],
    dueAt: dueAt,
    petId: legacyPrimaryPetId,
    petNameSnapshot: 'Mochi',
    medicationNameSnapshot: 'Tablet A',
    doseText: '1 tablet',
    instructions: 'With food',
    responsibilityStatus: MedicationResponsibilityStatus.unclaimed,
    responsibleById: null,
    responsibleByNameSnapshot: null,
    claimedAt: null,
    outcomeStatus: outcome,
    outcomeById: outcome == MedicationOutcomeStatus.unresolved
        ? null
        : 'user-1',
    outcomeByNameSnapshot: outcome == MedicationOutcomeStatus.unresolved
        ? null
        : 'Alex',
    outcomeAt: outcome == MedicationOutcomeStatus.unresolved
        ? null
        : dueAt.add(const Duration(minutes: 5)),
    skippedReasonCode: reason,
    skippedReasonNote: reasonNote,
    revision: outcome == MedicationOutcomeStatus.unresolved ? 0 : 1,
    isServerConfirmed: isServerConfirmed,
  );
}

final class _FakeCareTaskMutationRepository
    implements CareTaskMutationRepository {
  _FakeCareTaskMutationRepository({this.failActions = false});

  final bool failActions;
  int claimCalls = 0;
  String? lastTaskId;
  String? lastRecipientId;

  void _maybeFail() {
    if (failActions) throw StateError('offline');
  }

  @override
  Future<void> accept({
    required String householdId,
    required String taskId,
    required String actorId,
    required String requestId,
  }) async => _maybeFail();

  @override
  Future<void> cancel({
    required String householdId,
    required String taskId,
    required String actorId,
    required String requestId,
  }) async => _maybeFail();

  @override
  Future<void> claim({
    required String householdId,
    required String taskId,
    required String actorId,
    CareTask? taskIfMissing,
  }) async {
    claimCalls += 1;
    lastTaskId = taskId;
    _maybeFail();
  }

  @override
  Future<void> complete({
    required String householdId,
    required String taskId,
    required String actorId,
  }) async => _maybeFail();

  @override
  Future<void> decline({
    required String householdId,
    required String taskId,
    required String actorId,
    required String requestId,
  }) async => _maybeFail();

  @override
  Future<String> requestDirect({
    required String householdId,
    required String taskId,
    required String actorId,
    required String recipientId,
    CareTask? taskIfMissing,
  }) async {
    _maybeFail();
    lastRecipientId = recipientId;
    return 'request-direct';
  }

  @override
  Future<String> requestOpen({
    required String householdId,
    required String taskId,
    required String actorId,
    CareTask? taskIfMissing,
  }) async {
    _maybeFail();
    return 'request-open';
  }
}

CareTask _unclaimedTask() => CareTask(
  id: 'task-1',
  title: 'Evening walk',
  category: CareCategory.walking,
  dueTime: DateTime.now(),
  kind: CareTaskKind.oneOff,
  priority: CarePriority.normal,
  routineId: null,
  status: CareTaskStatus.unclaimed,
  assignmentRequest: null,
  assigneeId: null,
  assigneeNameSnapshot: null,
  claimedAt: null,
  createdById: 'user-1',
  createdBy: 'Alex',
  createdAt: DateTime.now(),
  completedById: null,
  completedBy: null,
  completedAt: null,
  revision: 0,
);

const _twoPetSnapshot = PetSnapshot(
  pets: [
    Pet(
      id: legacyPrimaryPetId,
      name: 'Mochi',
      species: PetSpecies.dog,
      isArchived: false,
      createdAt: null,
      updatedAt: null,
    ),
    Pet(
      id: 'pet-nori',
      name: 'Luna',
      species: PetSpecies.cat,
      isArchived: false,
      createdAt: null,
      updatedAt: null,
    ),
  ],
);

CareTask _claimedTask(DateTime dueAt) => CareTask(
  id: 'claimed-task',
  title: 'Evening walk',
  category: CareCategory.walking,
  dueTime: dueAt,
  kind: CareTaskKind.oneOff,
  priority: CarePriority.normal,
  routineId: null,
  status: CareTaskStatus.claimed,
  assignmentRequest: null,
  assigneeId: 'user-2',
  assigneeNameSnapshot: 'Sam',
  claimedAt: dueAt.subtract(const Duration(minutes: 10)),
  createdById: 'user-1',
  createdBy: 'Alex',
  createdAt: dueAt.subtract(const Duration(hours: 1)),
  completedById: null,
  completedBy: null,
  completedAt: null,
  revision: 1,
  petId: legacyPrimaryPetId,
  petNameSnapshot: 'Mochi',
);

CareTask _longTodayTask(
  DateTime dueAt, {
  required String title,
  required String caregiverName,
  required String petName,
}) => CareTask(
  id: 'long-today-task',
  title: title,
  category: CareCategory.walking,
  dueTime: dueAt,
  kind: CareTaskKind.oneOff,
  priority: CarePriority.urgent,
  routineId: null,
  status: CareTaskStatus.claimed,
  assignmentRequest: null,
  assigneeId: 'user-1',
  assigneeNameSnapshot: caregiverName,
  claimedAt: dueAt.subtract(const Duration(minutes: 5)),
  createdById: 'user-1',
  createdBy: caregiverName,
  createdAt: dueAt.subtract(const Duration(hours: 1)),
  completedById: null,
  completedBy: null,
  completedAt: null,
  revision: 1,
  petId: legacyPrimaryPetId,
  petNameSnapshot: petName,
);

CareTask _completedReportTask(DateTime completedAt) => CareTask(
  id: 'report-task',
  title: 'Morning meal',
  category: CareCategory.feeding,
  dueTime: completedAt.subtract(const Duration(minutes: 5)),
  kind: CareTaskKind.oneOff,
  priority: CarePriority.normal,
  routineId: null,
  status: CareTaskStatus.completed,
  assignmentRequest: null,
  assigneeId: 'user-1',
  assigneeNameSnapshot: 'Alex',
  claimedAt: completedAt.subtract(const Duration(minutes: 10)),
  createdById: 'user-1',
  createdBy: 'Alex',
  createdAt: completedAt.subtract(const Duration(days: 1)),
  completedById: 'user-1',
  completedBy: 'Alex',
  completedAt: completedAt,
  revision: 2,
  petId: legacyPrimaryPetId,
  petNameSnapshot: 'Mochi',
);

CareTask _petTask(
  String title,
  String petId,
  String petName,
  DateTime dueTime,
) => CareTask(
  id: 'task-$petId',
  title: title,
  category: CareCategory.feeding,
  dueTime: dueTime,
  kind: CareTaskKind.oneOff,
  priority: CarePriority.normal,
  routineId: null,
  status: CareTaskStatus.unclaimed,
  assignmentRequest: null,
  assigneeId: null,
  assigneeNameSnapshot: null,
  claimedAt: null,
  createdById: 'user-1',
  createdBy: 'Alex',
  createdAt: dueTime,
  completedById: null,
  completedBy: null,
  completedAt: null,
  revision: 0,
  petId: petId,
  petNameSnapshot: petName,
);
