import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local scheme targets the isolated Flutter entry and build config', () {
    final scheme = _read(
      'ios/Runner.xcodeproj/xcshareddata/xcschemes/local.xcscheme',
    );
    final config = _read('ios/Flutter/Debug-local.xcconfig');

    expect(scheme, contains('buildConfiguration = "Debug-local"'));
    expect(scheme, contains('BlueprintName = "Runner"'));
    expect(config, contains('#include "Debug.xcconfig"'));
    // A pinned FLUTTER_TARGET also overrides the entry point that
    // `flutter test` generates, which silently launches the real app instead
    // of the integration test, so the local entry point is passed explicitly.
    expect(config, isNot(contains('FLUTTER_TARGET=')));
    expect(config, contains('--target lib/main_emulator.dart'));
  });

  test('local plist disables Messaging and remote notification activation', () {
    final plist = _read('ios/Runner/Info-Local.plist');

    expect(plist, contains('<key>FirebaseMessagingAutoInitEnabled</key>'));
    expect(plist, contains('<key>FirebaseAppDelegateProxyEnabled</key>'));
    expect(
      RegExp(
        r'<key>FirebaseMessagingAutoInitEnabled</key>\s*<false/>',
      ).hasMatch(plist),
      isTrue,
    );
    expect(
      RegExp(
        r'<key>FirebaseAppDelegateProxyEnabled</key>\s*<false/>',
      ).hasMatch(plist),
      isTrue,
    );
    expect(plist, isNot(contains('remote-notification')));
    expect(plist, isNot(contains('GoogleService-Info.plist')));
  });

  test('only the local plist opens plaintext loopback for the Emulator', () {
    final localPlist = _read('ios/Runner/Info-Local.plist');
    final productionPlist = _read('ios/Runner/Info.plist');

    // The Emulator suite speaks plaintext HTTP on loopback, which App Transport
    // Security blocks by default. Without this exception the local build starts
    // and then silently reaches no Firebase surface at all.
    expect(
      RegExp(
        r'<key>NSAllowsLocalNetworking</key>\s*<true/>',
      ).hasMatch(localPlist),
      isTrue,
    );
    expect(localPlist, isNot(contains('NSAllowsArbitraryLoads')));
    expect(productionPlist, isNot(contains('NSAppTransportSecurity')));

    // Flutter reaches the Dart VM Service over Bonjour on the local network.
    // Without these debug-only keys the local build launches and then hangs on
    // "Waiting for VM Service port", so no integration phase ever runs.
    expect(localPlist, contains('_dartVmService._tcp'));
    expect(localPlist, contains('<key>NSLocalNetworkUsageDescription</key>'));
    expect(productionPlist, isNot(contains('_dartVmService._tcp')));
  });

  test('local target has a distinct bundle and no APNs entitlement', () {
    final project = _read('ios/Runner.xcodeproj/project.pbxproj');
    final entitlements = _read('ios/Runner/Runner-Local.entitlements');

    expect(
      project,
      contains('PRODUCT_BUNDLE_IDENTIFIER = com.copaw.demo.local;'),
    );
    expect(project, contains('INFOPLIST_FILE = "Runner/Info-Local.plist";'));
    expect(
      project,
      contains('CODE_SIGN_ENTITLEMENTS = "Runner/Runner-Local.entitlements";'),
    );
    expect(
      project,
      contains('EXCLUDED_SOURCE_FILE_NAMES = GoogleService-Info.plist;'),
    );
    expect(project, contains('name = "Debug-local";'));
    expect(entitlements, isNot(contains('aps-environment')));
    expect(project, isNot(contains('GoogleService-Info.plist in Resources')));
  });

  test(
    'notification callables use the configured regional Functions instance',
    () {
      final gateway = _read(
        'lib/src/data/firebase_notification_center_gateway.dart',
      );

      expect(gateway, contains('FirebaseFunctions.instanceFor'));
      expect(gateway, contains("region: 'asia-northeast1'"));
      expect(
        gateway,
        isNot(
          contains('_functions = functions ?? FirebaseFunctions.instance;'),
        ),
      );
    },
  );
}

String _read(String path) => File(path).readAsStringSync();
