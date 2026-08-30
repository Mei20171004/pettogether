import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bootstrap/bootstrap_repository.dart';
import 'data/care_task_repository.dart';
import 'data/household_repository.dart';
import 'data/household_sync_repository.dart';
import 'data/membership_exit_repository.dart';
import 'localization/app_locale.dart';
import 'localization/locale_repository.dart';

enum AppBootStatus { loading, ready, failed }

class AppSnapshot {
  const AppSnapshot({
    required this.status,
    required this.locale,
    this.failureKind,
    this.session,
  });

  final AppBootStatus status;
  final AppLocale locale;
  final BootstrapFailureKind? failureKind;
  final HouseholdSession? session;

  AppSnapshot copyWith({AppBootStatus? status, AppLocale? locale}) {
    return AppSnapshot(
      status: status ?? this.status,
      locale: locale ?? this.locale,
      failureKind: failureKind,
      session: session,
    );
  }
}

final appControllerProvider = AsyncNotifierProvider<AppController, AppSnapshot>(
  AppController.new,
);

class AppController extends AsyncNotifier<AppSnapshot> {
  Future<void> _localeWrite = Future<void>.value();
  var _initializationGeneration = 0;

  @override
  Future<AppSnapshot> build() async {
    AppLocale locale = AppLocale.japanese;
    try {
      locale = await ref.read(localeRepositoryProvider).load();
    } on Object {
      // Locale persistence is optional; startup remains usable in Japanese.
    }
    return _initialize(locale);
  }

  Future<AppSnapshot> _initialize(AppLocale locale) async {
    try {
      await ref.read(bootstrapRepositoryProvider).initialize();
      final session = await ref
          .read(householdRepositoryProvider)
          .restoreSession();
      return AppSnapshot(
        status: AppBootStatus.ready,
        locale: locale,
        session: session,
      );
    } on BootstrapException catch (error) {
      return AppSnapshot(
        status: AppBootStatus.failed,
        locale: locale,
        failureKind: error.kind,
      );
    } on HouseholdRepositoryException catch (error) {
      return AppSnapshot(
        status: AppBootStatus.failed,
        locale: locale,
        failureKind: switch (error.code) {
          HouseholdRepositoryErrorCode.network => BootstrapFailureKind.network,
          HouseholdRepositoryErrorCode.permission ||
          HouseholdRepositoryErrorCode.authentication =>
            BootstrapFailureKind.permission,
          HouseholdRepositoryErrorCode.malformedData =>
            BootstrapFailureKind.malformedData,
          _ => BootstrapFailureKind.service,
        },
      );
    } on Object {
      return AppSnapshot(
        status: AppBootStatus.failed,
        locale: locale,
        failureKind: BootstrapFailureKind.unknown,
      );
    }
  }

  Future<HouseholdSession> createHousehold({
    required String householdName,
    required String petName,
    required String caregiverName,
    required String timeZoneIdentifier,
  }) async {
    final session = await ref
        .read(householdRepositoryProvider)
        .createHousehold(
          householdName: householdName,
          petName: petName,
          caregiverName: caregiverName,
          timeZoneIdentifier: timeZoneIdentifier,
        );
    _setSession(session);
    return session;
  }

  Future<HouseholdSession> joinHousehold({
    required String inviteCode,
    required String caregiverName,
  }) async {
    final session = await ref
        .read(householdRepositoryProvider)
        .joinHousehold(inviteCode: inviteCode, caregiverName: caregiverName);
    _setSession(session);
    return session;
  }

  Future<void> disconnectThisDevice() async {
    await ref.read(householdRepositoryProvider).leaveHousehold();
    await _clearSessionAndObservers();
  }

  Future<HouseholdLeaveResult> leaveHousehold({
    required String householdId,
    required String clientMutationId,
  }) async {
    final result = await ref
        .read(membershipExitRepositoryProvider)
        .leaveHousehold(
          householdId: householdId,
          clientMutationId: clientMutationId,
        );
    if (!result.left) {
      throw const MembershipExitException(
        MembershipExitErrorCode.backendUnavailable,
      );
    }
    try {
      await ref.read(householdRepositoryProvider).leaveHousehold();
    } on Object {
      // Server membership is already revoked. Clear the in-memory session;
      // restore will remove any stale local marker on the next launch.
    }
    await _clearSessionAndObservers();
    return result;
  }

  Future<void> _clearSessionAndObservers() async {
    _setSession(null);
    try {
      await Future.wait([
        ref.read(householdSyncRepositoryProvider).stopObserving(),
        ref.read(careTaskRepositoryProvider).stopObserving(),
      ]);
    } on Object {
      // The local session is already cleared. Widget-owned subscriptions are
      // cancelled on disposal, so observer cleanup cannot reverse the leave.
    }
  }

  void applySyncedSession(HouseholdSyncSnapshot synced) {
    final current = state.value;
    final session = current?.session;
    if (session == null) return;
    _setSession(
      HouseholdSession(
        household: synced.household,
        caregiver: synced.caregiver,
        memberJoinedAt: synced.memberJoinedAt ?? session.memberJoinedAt,
        diagnostics: synced.diagnostics,
        localPersistence: session.localPersistence,
      ),
    );
  }

  void _setSession(HouseholdSession? session) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      AppSnapshot(
        status: AppBootStatus.ready,
        locale: current.locale,
        session: session,
      ),
    );
  }

  Future<void> retry() async {
    final current =
        state.value ??
        const AppSnapshot(
          status: AppBootStatus.loading,
          locale: AppLocale.japanese,
        );
    state = AsyncData(
      AppSnapshot(status: AppBootStatus.loading, locale: current.locale),
    );
    final generation = ++_initializationGeneration;
    final result = await _initialize(current.locale);
    if (generation == _initializationGeneration) {
      state = AsyncData(result);
    }
  }

  Future<void> setLocale(AppLocale locale) async {
    final current = state.value;
    if (current == null || current.locale == locale) {
      return;
    }

    final previousLocale = current.locale;
    state = AsyncData(current.copyWith(locale: locale));

    _localeWrite = _localeWrite.then((_) async {
      try {
        await ref.read(localeRepositoryProvider).save(locale);
      } on Object {
        final latest = state.value;
        if (latest?.locale == locale) {
          state = AsyncData(latest!.copyWith(locale: previousLocale));
        }
      }
    });
    await _localeWrite;
  }
}
