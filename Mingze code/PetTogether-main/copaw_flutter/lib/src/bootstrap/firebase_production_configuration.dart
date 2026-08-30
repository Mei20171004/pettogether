import 'package:firebase_core/firebase_core.dart';

FirebaseOptions? productionFirebaseOptions({
  String apiKey = const String.fromEnvironment('COPAW_FIREBASE_API_KEY'),
  String appId = const String.fromEnvironment('COPAW_FIREBASE_APP_ID'),
  String messagingSenderId = const String.fromEnvironment(
    'COPAW_FIREBASE_MESSAGING_SENDER_ID',
  ),
  String projectId = const String.fromEnvironment('COPAW_FIREBASE_PROJECT_ID'),
}) {
  final values = [apiKey, appId, messagingSenderId, projectId];
  if (values.any((value) => value.trim().isEmpty) ||
      projectId == 'demo-copaw') {
    return null;
  }
  return FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: messagingSenderId,
    projectId: projectId,
  );
}
