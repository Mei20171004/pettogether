import 'package:copaw_flutter/src/bootstrap/firebase_emulator_configuration.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const _expectsLt7Ports = bool.fromEnvironment(
  'COPAW_EXPECT_LT7_ISOLATED_PORTS',
);

void main() {
  test('uses the Android host bridge for an Android emulator', () {
    expect(firebaseEmulatorHost(TargetPlatform.android), '10.0.2.2');
  });

  test('uses loopback for an iOS simulator', () {
    expect(firebaseEmulatorHost(TargetPlatform.iOS), '127.0.0.1');
  });

  test('keeps the app and CLI on the same demo project', () {
    expect(localFirebaseProjectId, 'demo-copaw');
    expect(
      localFirebaseOptionsForPlatform(TargetPlatform.android).projectId,
      localFirebaseProjectId,
    );
  });

  test('uses a syntactically valid non-secret local API key', () {
    expect(localFirebaseApiKey, hasLength(39));
    expect(localFirebaseApiKey, startsWith('AIza'));
  });

  test('uses platform-specific local app identifiers', () {
    expect(
      localFirebaseOptionsForPlatform(TargetPlatform.android).appId,
      '1:1:android:1',
    );
    expect(
      localFirebaseOptionsForPlatform(TargetPlatform.iOS).appId,
      '1:1:ios:1',
    );
  });

  test('keeps default ports while exposing isolated LT7 overrides', () {
    expect(localFirebaseAuthPort, _expectsLt7Ports ? 9199 : 9099);
    expect(localFirebaseFirestorePort, _expectsLt7Ports ? 8180 : 8080);
    expect(localFirebaseFunctionsPort, _expectsLt7Ports ? 5101 : 5001);
    expect(localFirebaseFunctionsRegion, 'asia-northeast1');
    expect(localFirebaseAuthPortDefine, 'COPAW_FIREBASE_AUTH_PORT');
    expect(localFirebaseFirestorePortDefine, 'COPAW_FIREBASE_FIRESTORE_PORT');
    expect(localFirebaseFunctionsPortDefine, 'COPAW_FIREBASE_FUNCTIONS_PORT');
  });
}
