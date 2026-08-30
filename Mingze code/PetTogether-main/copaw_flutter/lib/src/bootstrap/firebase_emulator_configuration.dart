import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

const localFirebaseProjectId = 'demo-copaw';
const localFirebaseApiKey = 'AIzaSy000000000000000000000000000000000';
const localFirebaseFunctionsRegion = 'asia-northeast1';
const localFirebaseAuthPortDefine = 'COPAW_FIREBASE_AUTH_PORT';
const localFirebaseFirestorePortDefine = 'COPAW_FIREBASE_FIRESTORE_PORT';
const localFirebaseFunctionsPortDefine = 'COPAW_FIREBASE_FUNCTIONS_PORT';
const localFirebaseAuthPort = int.fromEnvironment(
  localFirebaseAuthPortDefine,
  defaultValue: 9099,
);
const localFirebaseFirestorePort = int.fromEnvironment(
  localFirebaseFirestorePortDefine,
  defaultValue: 8080,
);
const localFirebaseFunctionsPort = int.fromEnvironment(
  localFirebaseFunctionsPortDefine,
  defaultValue: 5001,
);

FirebaseOptions localFirebaseOptionsForPlatform(TargetPlatform platform) {
  final platformName = switch (platform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS || TargetPlatform.macOS => 'ios',
    _ => 'web',
  };
  return FirebaseOptions(
    apiKey: localFirebaseApiKey,
    appId: '1:1:$platformName:1',
    messagingSenderId: '1',
    projectId: localFirebaseProjectId,
  );
}

String firebaseEmulatorHost(TargetPlatform platform) =>
    platform == TargetPlatform.android ? '10.0.2.2' : '127.0.0.1';

Future<void> configureLocalFirebaseEmulators() async {
  await Firebase.initializeApp(
    options: localFirebaseOptionsForPlatform(defaultTargetPlatform),
  );
  final host = firebaseEmulatorHost(defaultTargetPlatform);

  await FirebaseAuth.instance.useAuthEmulator(host, localFirebaseAuthPort);
  FirebaseFirestore.instance.useFirestoreEmulator(
    host,
    localFirebaseFirestorePort,
  );
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
  );
  FirebaseFunctions.instanceFor(
    region: localFirebaseFunctionsRegion,
  ).useFunctionsEmulator(host, localFirebaseFunctionsPort);
}
