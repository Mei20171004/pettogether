# pettogether (Flutter)

A Flutter app for shared pet care, without the guesswork — households,
recurring routines, task handoffs, invitation-based joining with owner
approval, and push notifications. This build merges the original
`pettogether` codebase with the unique features from the Kate/care-paw
rebuild (QR invitations, notifications, skip/restore, richer pet types,
multi-pet tasks, Pro page), plus the health-record features from the Mingze
rebuild (medication courses, medical history, vet visit pack).

## Overview

pettogether gives families and shared caregivers one place to coordinate recurring
routines and one-time needs, decide who is responsible, and see what has
already been done.

- Create a household with one or more pets (14 pet types with vector icons),
  or join one through a **one-time 24-hour invitation link/QR code** that the
  owner must approve
- Invitation preview before requesting: see the household name, pets and
  inviter, with **no task/history data shared until the owner approves**
- Owners review join requests inline (approve/decline), generate QR-code
  invitations, revoke them, and remove members
- Sync caregivers, routines, and tasks in real time (Firestore) — or fully
  offline against seeded demo data (`MockCareService`, demo invite `PAW123`)
- Add daily, selected-weekday, interval, nth-weekday, and one-time care tasks,
  assigned to one pet or several
- Claim tasks, open them to the household, or request a specific caregiver
- Accept, decline, or cancel assignment requests with protected state
  transitions; **skip a single routine occurrence** (e.g. "no walk today")
  without touching the routine, and restore it later
- Browse care plans in **Today**, **Calendar**, and **Activity** (charts)
  views, plus a per-pet care card with today's progress and routine list in
  the **Family** tab
- **Push notifications** (FCM + local notifications + Cloud Functions):
  task created/claimed/completed, direct/open assignment requests, join
  requests, and 10–25-minute routine reminders; per-member opt-in toggle
- Track **medication courses** per pet (medicine, form, purpose, side effects,
  dose times, explicit course start/end) — today's doses appear at the top of
  **Today**, and recording one tells the rest of the household so nobody
  double-doses. Skips carry a reason, mis-taps can be undone for 5 minutes, and
  each course shows a 7/30-day adherence breakdown of given / skipped /
  not-recorded
- Keep a **medical history** per pet — vet visits, vaccinations, deworming, lab
  results, surgery, symptoms, weight and notes. The form changes shape with the
  record type (clinic + diagnosis + treatment + cost for a visit; product, lot
  number and **next-due date** for a vaccination), events can be **backdated**,
  records can be **edited and deleted**, and photos of lab printouts or
  prescriptions attach to any record
- Vaccinations and dewormings with a next-due date surface on **Today** and the
  pet's health summary, and push a reminder a week out and on the day
- Build a **vet visit pack** for a pet over 7/30/90 days — current medication,
  how the doses actually went, symptoms, weight, past visits and vaccinations,
  with the empty sections named rather than silently dropped — and export it as
  a **shareable PDF**
- **Deep links**: `pettogether://invite/<id>` opens the invitation preview
- Switch between **English, Japanese, Chinese and Korean**
- pettogether Pro marketing page (purchases not connected yet)
- Keep household data private with member-scoped Security Rules

## Running

```sh
flutter pub get
flutter run
```

By default the app runs against `MockCareService`, an offline implementation
that seeds a demo household (`Mochi`, invite code `PAW123`, partner `Alex`) and
persists to `shared_preferences`. This means it works immediately with no
Firebase project. In mock mode invitations auto-approve so the demo stays
usable; the QR scanner is hidden (paste `PAW123` instead).

## Project structure

```text
lib/
├── main.dart                     # entry point + Firebase/mock selection
├── app.dart                      # root widget (providers, theme, deep links)
├── config/app_config.dart        # useFirebase switch
├── l10n/l10n.dart                # EN/JA/ZH/KO helper + language store
├── theme/app_theme.dart          # paw color palette + button styles
├── models/
│   ├── models.dart               # Household, Caregiver, Routine, Task, Invitation, …
│   └── health.dart               # MedicationPlan/Slot/Dose, PlannedDose, HealthRecord, …
├── services/
│   ├── care_service.dart         # service interface + typed errors
│   ├── mock_care_service.dart    # offline demo implementation
│   ├── firebase_care_service.dart# Firestore implementation
│   ├── vet_report_pdf.dart       # vet visit pack -> PDF -> share sheet
│   └── notification_service.dart # FCM + local notifications
├── store/care_store.dart         # ChangeNotifier shared state + actions
├── utils/                        # calendar math, uuid, extensions
└── views/
    ├── root_view.dart            # loading / welcome / tab shell
    ├── auth_gate.dart            # login gate (email/Google when Firebase is on)
    ├── login_view.dart
    ├── create_join_view.dart     # create (multi-pet) / join via link+QR+approval
    ├── invitation_scanner_view.dart
    ├── today_view.dart           # incl. skipped-today section
    ├── schedule_view.dart
    ├── activity_view.dart        # pet insights (fl_chart)
    ├── pet_insights_view.dart
    ├── pet_detail_view.dart
    ├── manage_household_view.dart# invitations QR, join requests, notifications, pets
    ├── pro_view.dart
    ├── add_task_view.dart        # multi-pet selector
    ├── health/                   # medication courses, medical records, vet pack
    └── widgets/                  # TaskCard, DoseCard, PetCard, CareIcon, …
```

## Firebase

- Project: `pettogether-76452`
- Auth: email/password + Google sign-in
- Firestore: `asia-northeast1`
- Storage: pet photos
- AI: Firebase AI Logic (Gemini) parses natural-language care instructions
- Cloud Messaging + Cloud Functions for notifications (task changes, join
  requests, routine reminders)

### Enabling Firebase

1. Flip `AppConfig.useFirebase` to `true` in `lib/config/app_config.dart`.
2. Add the generated config files:
   - iOS: `ios/Runner/GoogleService-Info.plist`
   - Android: `android/app/google-services.json`
3. Deploy rules, indexes and functions:

   ```sh
   npx firebase-tools deploy --only firestore:rules,firestore:indexes,functions --project pettogether-76452
   ```

4. Enable **Cloud Messaging** in the console and upload APNs / FCM
   credentials for push notifications.

`main.dart` initializes Firebase and selects `FirebaseCareService`; if the
config files are missing it falls back to the mock so the app still opens.

### API keys via environment variables

API keys are never hardcoded in `lib/firebase_options.dart`. Inject them at
build time with `--dart-define`:

```sh
flutter run --dart-define=FIREBASE_ANDROID_API_KEY=<android-key> \
            --dart-define=FIREBASE_IOS_API_KEY=<ios-key>
```

The native iOS/Android SDKs read their keys from
`GoogleService-Info.plist` / `google-services.json` (both gitignored), so the
defines are only required when initializing Firebase with explicit Dart
options (e.g. web).

## Data model notes

- Tasks and routines carry a `petIds` list (multi-pet); legacy documents with
  only `petID` keep working (`effectivePetIds` falls back to it). The
  serializer writes both fields.
- Task status includes `skipped` (single-occurrence skip); skipped tasks
  appear in Today/Skip sections and can be restored.
- Invitations live in a top-level `invitations/{id}` collection
  (`pettogether://invite/<id>` deep link), join requests under
  `households/{id}/joinRequests/{uid}`, and FCM device tokens under
  `members/{uid}/devices/{token}`. Owners create members only after an
  approved join request; `household.ownerID` gates owner actions.
- Routine occurrences use the id format `<routineID>_yyyy-MM-dd` — the
  reminder Cloud Function looks up the same ids to avoid duplicate alerts.
- Medication works the same way: a course lives in
  `households/{id}/medicationPlans/{planId}` and its doses are expanded on
  demand, so only doses somebody acted on get a document, at
  `medicationDoses/<planId>_yyyy-MM-dd_HHmm`. That id is deterministic, so two
  caregivers recording the same dose collide on one document and the later one
  is told who got there first, instead of both succeeding.
- Each recorded dose snapshots the medicine name and dose text, so editing a
  course never rewrites what actually happened. That is why there is no
  immutable schedule-version chain — the history lives in the doses.
- A dose that Firestore has not confirmed (cache read or pending write) is
  displayed as *not recorded*, never as given. Showing a stale "given" is the
  one failure that could leave an animal dosed twice or not at all.
- Medical records live in `households/{id}/healthRecords/{recordId}` with
  photos under `households/{id}/records/{recordId}/` in Storage. Saving a
  `weight` record also appends to `Pet.weightHistory`, so the existing trend
  chart picks it up without a second source of truth.
- Day boundaries for medication use the device-local calendar, the same as
  routines (see `lib/utils/care_calendar.dart`). Running two different notions
  of "today" in one app would be worse than the cross-timezone edge case;
  `timeZoneIdentifier` is still stored for the Cloud Functions' scheduling.
- `weekdays` is `1 = Sunday … 7 = Saturday` everywhere, including in
  `functions/index.js`.

## Porting notes

- **State:** the store is a `ChangeNotifier` (`CareStore`) exposed through
  `provider`.
- **Service layer:** the protocol-based `CareService` boundary is preserved as
  an abstract class, so mock and Firestore implementations are interchangeable.
- **Time zones:** the app uses the device-local calendar for day math (see
  `lib/utils/care_calendar.dart`) while storing `timeZoneIdentifier` for
  Firestore compatibility; the reminder function uses it for scheduling.
- **Dates:** JSON uses epoch milliseconds; Firestore uses native `Timestamp`s.

## Verification

```sh
flutter analyze
flutter test
```
