# copaw (Flutter)

A Flutter port of the **copaw** SwiftUI app — shared pet care, without the
guesswork. It recreates the same household/real-time experience as the
original in `../co-paw`, with a clean, layered Dart architecture.

## Overview

copaw gives families and shared caregivers one place to coordinate recurring
routines and one-time needs, decide who is responsible, and see what has
already been done.

- Create a household or join one with an invite code
- Sync caregivers, routines, and tasks in real time (Firestore) — or fully
  offline against seeded demo data (the default)
- Add daily, selected-weekday, one-time, and urgent care tasks
- Claim tasks, open them to the household, or request a specific caregiver
- Accept, decline, or cancel assignment requests with protected state
  transitions
- Browse care plans in **Today**, **Calendar**, and **Activity** views
- Switch between English and Japanese
- Keep household data private with member-scoped Security Rules (reused from
  the original repo)

## Running

```sh
flutter pub get
flutter run
```

By default the app runs against `MockCareService`, an offline implementation
that seeds a demo household (`Mochi`, invite code `PAW123`, partner `Alex`) and
persists to `shared_preferences`. This means it works immediately with no
Firebase project.

## Project structure

```text
lib/
├── main.dart                     # entry point + Firebase/mock selection
├── app.dart                      # root widget (providers + theme)
├── config/app_config.dart        # useFirebase switch
├── l10n/l10n.dart                # English/Japanese helper + language store
├── theme/app_theme.dart          # paw color palette + button styles
├── models/models.dart            # Household, Caregiver, Routine, Task, …
├── services/
│   ├── care_service.dart         # service interface + typed errors
│   ├── mock_care_service.dart    # offline demo implementation
│   └── firebase_care_service.dart# Firestore implementation
├── store/care_store.dart         # ChangeNotifier shared state + actions
├── utils/                        # calendar math, uuid, extensions
└── views/
    ├── root_view.dart            # loading / welcome / tab shell
    ├── create_join_view.dart
    ├── today_view.dart
    ├── schedule_view.dart
    ├── activity_view.dart
    ├── premium_view.dart
    ├── profile_edit_view.dart
    ├── add_task_view.dart
    └── widgets/                  # TaskCard, PetCard, CareIcon, …
```

## Enabling Firebase

1. Flip `AppConfig.useFirebase` to `true` in `lib/config/app_config.dart`.
2. Register an iOS app (bundle id `com.copaw.copawFlutter`) and/or an Android
   app in your Firebase project, enable **Anonymous** sign-in, and create a
   Cloud Firestore database.
3. Add the generated config files:
   - iOS: `ios/Runner/GoogleService-Info.plist`
   - Android: `android/app/google-services.json`
4. Deploy the Security Rules from the original repo
   (`../co-paw/firestore.rules`):

   ```sh
   npx firebase-tools deploy --only firestore:rules --project <your-project-id>
   ```

`main.dart` initializes Firebase and selects `FirebaseCareService`; if the
config files are missing it falls back to the mock so the app still opens.

The Firestore implementation writes the exact same document shape and
flattened assignment-request fields as the original, so it interoperates with
the existing data and rules.

## Porting notes

- **State:** the Swift `ObservableObject` store is a `ChangeNotifier`
  (`CareStore`) exposed through `provider`.
- **Service layer:** the protocol-based `CareService` boundary is preserved as
  an abstract class, so mock and Firestore implementations are interchangeable.
- **Time zones:** the original computes day boundaries in the household's time
  zone via `Calendar`. This port uses the device-local calendar for day math
  (see `lib/utils/care_calendar.dart`) while still storing
  `timeZoneIdentifier` for Firestore compatibility. Cross-timezone households
  will expand routines in the device's local time.
- **Dates:** JSON uses epoch milliseconds; Firestore uses native `Timestamp`s.

## Verification

```sh
flutter analyze
flutter test
```
