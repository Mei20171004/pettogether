import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runner isolates two devices, build trees, and Firebase ports', () {
    final runner = File('tool/run_lt7_two_process_ios.sh').readAsStringSync();

    expect(runner, contains('COPAW_LT7_DEVICE_A'));
    expect(runner, contains('COPAW_LT7_DEVICE_B'));
    expect(runner, contains('COPAW_FIREBASE_AUTH_PORT=9199'));
    expect(runner, contains('COPAW_FIREBASE_FIRESTORE_PORT=8180'));
    expect(runner, contains('COPAW_FIREBASE_FUNCTIONS_PORT=5101'));
    expect(runner, contains('mktemp -d'));
    expect(runner, contains('firebase_two_process_acceptance_test.dart'));
    expect(runner, contains('--flavor local'));
    expect(runner, contains('--no-uninstall'));
    expect(runner, contains('com.copaw.demo.local'));
    expect(
      runner,
      contains(
        'identitytoolkit.googleapis.com/v1/projects/demo-copaw/accounts:query',
      ),
    );
    expect(runner, contains("-X POST"));
    expect(runner, contains("Authorization: Bearer owner"));
    expect(runner, contains("Content-Type: application/json"));
    expect(runner, contains("--data '{}'"));
    expect(runner, contains('recordsCount'));
    expect(runner, isNot(contains('emulator/v1/projects/demo-copaw/accounts')));
    expect(runner, contains('COPAW_LT7_ISOLATED_EXPORT_CONFIRMED'));
    expect(runner, contains('COPAW_LT7_COORDINATED_RUN_AUTHORIZED'));
    expect(runner, contains('verify_identity_convergence'));
  });

  test('acceptance target separates clean bootstrap and session relaunch', () {
    final target = File(
      'integration_test/firebase_two_process_acceptance_test.dart',
    ).readAsStringSync();

    expect(target, contains('COPAW_LT7_ROLE'));
    expect(target, contains('COPAW_LT7_PHASE'));
    expect(target, contains('COPAW_LT7_RUN_ID'));
    expect(target, contains('COPAW_LT7_INVITE_CODE'));
    expect(target, contains("'bootstrap' =>"));
    expect(target, contains("'reconnect' =>"));
    expect(target, contains('restoreSession'));
    expect(target, contains('authStateChanges'));
    expect(target, contains('isFromCache'));
    expect(target, contains('hasPendingWrites'));
  });

  test('acceptance target names every frozen cross-process checkpoint', () {
    final target = File(
      'integration_test/firebase_two_process_acceptance_test.dart',
    ).readAsStringSync();

    for (final checkpoint in <String>[
      'identity',
      'lt2-daily',
      'lt4-events',
      'lt5-transfer',
      'lt5-handoff',
      'lt6-inbox',
      'offline-reconnect',
      'no-duplicates',
    ]) {
      expect(target, contains('checkpoint=$checkpoint'));
    }
    expect(target, contains('waterBasis=localDayToDate'));
    expect(target, contains('pinnedRevision=1 currentRevision=2'));
    expect(target, contains('providerAttempts=0'));
    expect(target, contains('deliveryCount=0'));
    expect(target, contains('tokenCount=0'));
    expect(target, contains('healthRetryIdentity=stable'));
    expect(target, contains('medicationRetryIdentity=stable'));
    expect(target, contains('privatePeerInbox=denied'));
    expect(target, contains('cache=non-authoritative server=confirmed'));
  });

  test(
    'runner gates generation-only and sequences source and offline phases',
    () {
      final runner = File('tool/run_lt7_two_process_ios.sh').readAsStringSync();

      expect(
        RegExp(r'Authorization: Bearer owner').allMatches(runner),
        hasLength(3),
      );
      expect(runner, contains('notificationIntentGenerationV2'));
      expect(runner, contains('notificationDispatchV2'));
      expect(runner, contains('run_phase source'));
      expect(runner, contains('run_phase offline'));
      expect(runner, contains('LT7_READY_OFFLINE'));
    },
  );
}
