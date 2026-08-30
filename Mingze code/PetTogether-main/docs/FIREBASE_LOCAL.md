# Local Firebase development

CoPaw can run the complete Flutter application against a local-only Firebase
demo project. The local entry point connects Anonymous Auth, Firestore, and
callable Functions to the Firebase Emulator Suite. It does not use the real
`copaw-94a57` project.

## Start locally

Install the repository dependencies once:

```sh
npm ci
npm --prefix functions ci
cd copaw_flutter && flutter pub get
```

Use Node 22 for the Emulator Suite. With Node 24 the ports can appear online
while Functions source discovery times out, so an "On" card is not sufficient
evidence that callable functions loaded.

Set `JAVA_HOME` to a JDK 21 or later before starting the suite. Android
Studio's bundled JBR is supported; the startup script deliberately does not
commit a machine-specific JDK path.

Start Firebase from the repository root in the first terminal:

```sh
scripts/start_firebase_emulators.sh
```

Start the Flutter app in a second terminal. Pass a device ID when more than one
simulator is running:

```sh
scripts/run_flutter_emulator_app.sh -d DEVICE_ID
```

The Emulator Suite UI is available at <http://127.0.0.1:4000>. Android
emulators connect to the host through `10.0.2.2`; iOS simulators use
`127.0.0.1`.

Run the backend contract suites from the repository root:

```sh
npm run test:functions
npm run test:rules
```

When another Emulator Suite already owns the default ports, run the isolated
contract suites instead. They use `firebase.isolated.json` on Auth 9199,
Firestore 8180, and Functions 5101 without touching the interactive dataset:

```sh
npm run test:functions:isolated
npm run test:rules:isolated
npm run test:migration
```

With an Android emulator running against the same continuously running suite,
run the two-client Firebase SDK acceptance flow with:

```sh
cd copaw_flutter
flutter test integration_test/firebase_collaboration_test.dart -d DEVICE_ID
```

Do not run `npm --prefix functions test` by itself. Those tests require the
Auth, Firestore, and Functions emulators that `npm run test:functions` starts.

## Safety and limitations

- This runbook stops at local evidence. Environment promotion, migration,
  reconciliation, rollback, and authorization gates are defined separately in
  `docs/FIREBASE_PROMOTION_MIGRATION.md`.
- The local project ID is `demo-copaw`. Keep the CLI and app on this same ID so
  Authentication, Rules, Firestore, and Functions interoperate.
- Firestore persistence is disabled in the local entry point because emulator
  data is cleared when the suite stops; this prevents stale local cache from
  looking like current backend data.
- Cloud Messaging/APNs, App Check, Firebase Storage, deployed Rules, production
  indexes, IAM, billing, and physical-device behavior are not proven by this
  workflow.
- The local notification repository reports notifications as unsupported. No
  push token is requested or written while using `main_emulator.dart`.
- Use `lib/main.dart` only for a deliberately configured real Firebase build.
  It fails closed unless all four compile-time values are provided:
  `COPAW_FIREBASE_API_KEY`, `COPAW_FIREBASE_APP_ID`,
  `COPAW_FIREBASE_MESSAGING_SENDER_ID`, and `COPAW_FIREBASE_PROJECT_ID`.
  The production entry point rejects `demo-copaw`; real configuration files
  stay ignored and must never be committed.
- The local Functions emulator may warn when the host Node version differs
  from the declared Node 22 runtime. Use Node 22 for the interactive suite;
  Node 24 did not load the function definitions in the current environment.
- The iOS target no longer packages the ignored production
  `GoogleService-Info.plist`. Local `main_emulator.dart` builds therefore cannot
  initialize that file before Dart connects to `demo-copaw`; production builds
  use the explicit compile-time options above. Platform build and physical-
  device validation are still required before release.
- Firebase Installations is not emulated. The iOS Firebase plugins can still
  make a failed request for the `demo-copaw` project even though Auth,
  Firestore, and callable Functions use loopback. This workflow is isolated
  from the real project, but it is not fully offline.
