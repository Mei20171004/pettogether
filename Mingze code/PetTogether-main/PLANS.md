# CoPaw Flutter migration execution plan

Status: UI/UX Phases 2 and 3 pass their local gates; external provider, secure photo sync, system share-sheet, and physical-device acceptance remain open
Branch: `codex/flutter-migration`
Baseline: `origin/main` at `61c685bf682867ed153e9d5df98e6db48074bf74`
Started: 2026-08-12

## Working assumptions

- Preserve legacy Firebase data.
- iOS-first Beta; Android must build and run in an emulator.
- Keep Anonymous Auth and English/Japanese; new installs default to Japanese while saved preferences persist.
- No RevenueCat, paywall, remote deployment, production migration, or SwiftUI removal in this plan without a later explicit boundary decision.

## Baseline evidence

| Check | Observed result | Classification |
| --- | --- | --- |
| Source branch | Independent worktree created from refreshed `origin/main` at `61c685b`; original checkout remains on `codex/50s-demo-flow` | Pass |
| Latest main capability | Main contains profile/rejoin/leave and the collaborative selected-day/open-assignment demo flow | Pass |
| `npm ci` | Installed locked dependencies; npm reports six moderate dependency advisories | Pass with follow-up |
| `npm run test:rules` | Passed 17/17 using Android Studio's bundled JDK explicitly through `JAVA_HOME` | Pass |
| Swift iOS Simulator build | Passed on iPhone 17 Pro / iOS 26.5 after copying the ignored local Firebase plist; the earlier linker failure was a secondary configuration failure | Pass |
| Flutter/Dart | Flutter 3.44.9 stable and Dart 3.12.2 installed | Pass |
| CocoaPods / Android SDK | CocoaPods 1.17.0 installed; all Android SDK licenses accepted | Pass |
| `flutter doctor -v` | All configured Flutter, Android, Xcode, Chrome, device-discovery, and network checks passed | Pass |
| Devices | iOS simulators available; no physical iPhone/Android connected | Physical acceptance pending |

## Phase gates

### Phase 0 — contract and environment

Status: Code complete; Android provider acceptance pending

- [x] Refresh latest `origin/main` and create isolated migration worktree.
- [x] Freeze product scope and recommended defaults.
- [x] Create repository working agreement and acceptance contract.
- [x] Copy ignored iOS Firebase config locally without tracking or printing it.
- [x] Resolve Java, CocoaPods, and Android SDK licenses required by the current platform baseline.
- [x] Re-run Swift build and Rules baseline; record exact results.
- [x] Capture the current Swift/Firestore schema and state-machine contract in `docs/legacy-firestore-contract.md`.
- [ ] Add executable legacy schema fixtures and contract tests.

Exit: baseline failures are classified; AC-001 through AC-009 have concrete implementation/test mappings.

### Phase 1 — Flutter platform skeleton

Status: Code complete; Android production Firebase configuration still pending

- [x] Create `copaw_flutter` for iOS and Android beside SwiftUI.
- [x] Add Riverpod, GoRouter, localization, Firebase core/auth/firestore, warm theme, and deterministic fake bootstrap/locale repositories.
- [x] Implement boot/loading/no-session shell with testable Firebase initialization failure and retry.
- [x] Verify formatting, full analysis, 7 Dart/widget tests, iOS Simulator build, and Android debug APK build.
- [x] Launch and inspect the iOS Simulator UI with the ignored local Firebase configuration; observed the expected no-household shell.
- [x] Launch Android API 36 Google APIs emulator; observed a configuration-specific recovery screen with safe diagnostic log and no app crash.
- [x] Add legacy-compatible Dart household/member/task/routine models and observable legacy diagnostics; Flutter model/data/widget suite is 42/42.
- [x] Implement household session repository with Anonymous Auth, create/join/rejoin transactions, SharedPreferences restoration, and local-only leave.
- [x] Wire create/join forms, device IANA timezone lookup, restored-session shell, actionable errors, and local leave into the Flutter UI.
- [x] Harden member/household/invite creation with bound three-document writes, legacy invite handling, server-side input limits, and missing-household protection; Rules suite is 29/29.
- [x] Re-run the iOS Simulator after UI/data wiring. A first launch exposed eager Firebase repository construction (`core/no-app`); changed it to lazy construction and verified a clean install now reaches the create/join form.
- [x] Exercise Flutter Auth/Firestore gateways through the real Dart SDK against local Android Auth/Firestore emulators: create, join, one-off create, claim, and complete pass through Rules.
- [ ] Real Firebase create/join is intentionally not claimed yet; running it leaves persistent QA documents under the current no-delete Rules.
- [x] Add write-ahead/reconciliation for ambiguous household creation, member-first stale-session recovery, clean-install no-auth startup, conditional pending-marker cleanup, and leave cleanup across active/pending local keys.
- [x] Add household/member realtime sync and atomic profile-update repositories with listener cancellation and observable codec diagnostics; fake/payload tests pass, real listener behavior remains unverified.
- [x] Port routine occurrence derivation to Dart with household timezone, selected weekdays, start boundary, DST, stable IDs, and persisted-over-virtual precedence tests.
- [x] Complete independent Phase 1 code review and resolve findings for Android plugin wiring, build-output privacy, error taxonomy, actual Material locale, locale save rollback, and product display name.
- [ ] Obtain/register the Android Firebase app configuration and verify the Android ready/provider path.

Exit: AC-009 and AC-026 platform foundations pass without claiming Firebase parity.

### Phase 2 — current collaboration parity

Status: Local automation complete; latest visible/physical acceptance pending

- [x] Port legacy-compatible Dart models/codecs with observable repair diagnostics and canonical writers (19 domain tests).
- [x] Port household/session repository interface and Firebase implementation.
- [x] Port create/join/restore/profile/leave/rejoin and household/member roster snapshot lifecycle.
- [x] Port task/routine derivation and self-claim, direct/open request, accept, decline, cancel, and assignee-only completion transactions.
- [x] Port Today, Calendar, Activity, one-time/daily/selected-day creation, Profile, English/Japanese, error/retry, legacy repair, timezone repair, foreground, and household-midnight refresh states.
- [x] Add unit, widget, Rules, and real Dart SDK repository-emulator coverage; the latest consolidated evidence is recorded under Phase 5, and the Android emulator collaboration/medication SDK flows remain green.
- [x] Run a simultaneous two-client transaction conflict and realtime convergence flow through two independent Firebase app instances on the Android emulator.
- [ ] Complete independent review and clean iOS/Android visible acceptance after the latest navigation/routine changes.

Exit: AC-001 through AC-009 pass in automation/two clients; physical iPhone evidence remains an explicit later gate.

### Phase 3 — multi-pet and legacy migration

Status: Local implementation complete; migration reconciliation and device acceptance pending

- [x] Add pets schema/Rules and deterministic legacy pet mapping.
- [x] Dual-read old `petName`/no-`petID` data; new writes include `petID`.
- [x] Add pet profile, selection, filtering, editing, and archive behavior.
- [x] Cover member-only pet writes, archived/cross-household targets, historical task access, legacy-primary synthesis, listener replacement, and pet-filtered UI in deterministic tests (AC-010 through AC-013 local layers).
- [ ] Prepare idempotent migration dry-run and before/after reconciliation; do not execute production migration.
- [ ] Verify two-client pet filtering/archive behavior and legacy fixture counts in the acceptance environment.

Exit: AC-010 through AC-013 pass and old task/activity counts reconcile.

### Phase 4 — safe medication

Status: Local implementation complete; real-provider, fault, and physical-device acceptance pending

- [x] Add medication, versioned schedule, deterministic occurrence, and terminal outcome schemas/Rules.
- [x] Add plan editor, Today dose cards, responsibility, administered/skipped/reason, overdue, and Activity history UI.
- [x] Keep responsibility separate from outcome and render terminal outcomes only from non-cache, non-pending server snapshots (AC-015, AC-016, AC-018 local layers).
- [x] Preserve household-timezone occurrence identity, version boundaries, historical pet/medication/dose snapshots, trusted actor/time, monotonic revision, ambiguous-retry idempotence, and listener cleanup (AC-014, AC-019 local layers).
- [x] Persist only a SHA-256 request fingerprint and mutation ID across restart so an ambiguous create-plan response cannot produce a duplicate plan; clear it after an authoritative or unambiguous response.
- [x] Pass the Android Auth/Firestore/Functions emulator SDK flow with two independent Firebase app instances racing administer versus skip: exactly one terminal result wins, both listeners converge, and replacing the plan preserves the old occurrence (AC-015 through AC-019 emulator layers).
- [x] Pass the medication local gates; the later Phase 5 consolidated rerun supersedes the earlier 131 Flutter / 43 Rules / 11 callable counts.
- [ ] Run a visible latest-medication UI pass and real network fault/reconnect/restart cases.
- [ ] Configure and verify Flutter App Check plus the ignored Android Firebase configuration before claiming live medication callables.
- [ ] Run the conflict and recovery flow on two physical iPhones; reconcile the planned denominator again when the report phase exists.

Exit: AC-014 through AC-019 pass at their required provider/device layers. The local code milestone is closed, but the phase exit remains open for the unchecked acceptance items above.

### Release checkpoint A

Status: Independent local review complete; external acceptance pending

Flutter parity + multi-pet + safe medication is the first coherent Beta. Run independent design, data/security, and acceptance review before advancing.

### Phase 5 — reliable notifications

Status: Local implementation and deterministic gates complete; provider/device exit pending

- [x] Add private per-installation token registration, permission/status/recovery UI, refresh-listener cleanup, denied/leave disable behavior, and serialized token mutations (AC-021 local layers).
- [x] Add household-timezone due/+15m/+30m dispatch, cross-midnight evaluation, effective-version boundaries, terminal suppression, concurrent scheduler leases, unique-device deduplication, invalid-token disable, short provider expiry, and redacted lock-screen payloads (AC-020 local layers).
- [x] Add iOS foreground presentation configuration plus Android/iOS platform declarations; Android foreground system presentation remains device/provider work.
- [x] Pass current local gates after the final notification changes: Dart format, `flutter analyze`, 142 Flutter tests, 45 Rules tests, 17 Auth/Firestore/Functions emulator tests, Android debug APK, and iOS Simulator build.
- [x] Complete independent data/security and acceptance audits; resolved denied-token re-enable, in-flight disable ordering, missing-token status, duplicate token delivery, cross-midnight, and terminal recheck findings.
- [ ] Verify real APNs/FCM permission, token registration/rotation, foreground/background/killed delivery, notification click, settings recovery, provider invalid-token response, and due/+15m/+30m cancellation on devices.
- [ ] Verify the deployed scheduler identity/permissions and App Check/provider configuration; no deployment is authorized in this worktree.
- [ ] Decide and acceptance-test the provider failure policy: FCM/APNs does not offer an atomic transaction with Firestore, so collapse IDs and short expiry reduce but cannot prove user-visible exactly-once delivery after an ambiguous provider acceptance.

Exit: AC-020 and AC-021 pass at the claimed device/provider layer.

### Phase 6 — health timeline

Status: Local implementation and AC-022 deterministic gates complete; visible/provider release acceptance pending

- [x] Add immutable, member-only, pet-scoped weight, appetite, energy, stool/observation, symptom, visit, vaccine, and note records with trusted creator/time snapshots.
- [x] Add per-pet/type filters, a limited weight trend, empty/cache/error/retry states, and explicit non-diagnostic copy without photos.
- [x] Keep pending writes hidden, expose cache state, reject malformed records, clean up replaced listeners, and reuse a persisted content-free mutation ID after an ambiguous retry.
- [x] Pass AC-022 Rules boundaries for member/outsider list/read/write, two pets/two households, archived history, all record types, field limits, future-time limits, immutable records, and server timestamps; current Rules suite is 50/50.
- [x] Pass the pet-switching widget flow and health repository tests inside the current 148/148 Flutter suite; Dart format and `flutter analyze` also pass.
- [x] Pass one Android Auth/Firestore/Functions emulator SDK flow with two independent Firebase app instances: two caregivers create records for two pets and both listeners converge without cross-pet mixing.
- [x] Build the final health source as an Android debug APK and iOS Simulator `Runner.app`; scan Android runtime logs and source references without finding synthetic pet/health fixture content in logs.
- [ ] Run a visible latest-health UI pass on configured clients and the full privacy/cache review with real user data before release.
- [ ] Add recoverable sign-in/account linking before treating Anonymous Auth health data as production-ready; this remains outside the current Beta scope.

Exit: AC-022 passes at the required Rules/two-client deterministic layer and the local privacy/log check is clean. Production readiness remains open for visible configured-device evidence and recoverable sign-in.

### Phase 7 — household handoff and reports

Status: Local implementation and deterministic AC-023 through AC-025 gates complete; real system-share/device acceptance pending

- [x] Add one current household handoff document with care instructions, emergency contact, veterinary hospital, monotonic revision, trusted actor/time snapshots, strict codecs, cache/pending states, listener cleanup, and member-only Rules (AC-023).
- [x] Pass four focused handoff repository tests, one handoff widget flow, Rules member/outsider/revision/field-boundary coverage, and the Android two-Firebase-app flow where client A creates, client B updates, and both converge on revision 2 (AC-023).
- [x] Add selected-pet 7/30-day reports using household-local day boundaries, routine and one-off care sources, every immutable medication schedule version, server-confirmed terminal outcomes, and pet/range-filtered health records (AC-024).
- [x] Reconcile planned/completed/administered/skipped/unresolved/late counts and trusted actor/time source events in three deterministic report-service fixtures and the in-app Activity report widget; retain explicit non-diagnostic copy (AC-024).
- [x] Add explicit local PDF sharing with a bundled OFL-licensed Noto Sans JP font, generic filename, no automatic upload, selected-pet/range report input, system share adapter, and visible failure/retry state (AC-025).
- [x] Render and inspect a one-page Japanese PDF, verify embedded Japanese pet/event/actor text and the non-diagnostic statement, and pass the Unicode PDF structure test plus explicit share failure/retry widget flow (AC-025 local layer).
- [x] Pass final Phase 7 local gates: Dart format, `flutter analyze`, 158 Flutter tests, 52 Rules tests, 17 Auth/Firestore/Functions emulator tests, one Android two-Firebase-app SDK integration, Android debug APK, and iOS Simulator build from the documented clean `/tmp` mirror.
- [ ] Exercise and visually inspect the real iOS and Android system share sheets with the latest app on configured devices; confirm the received PDF against current in-app provider data before claiming full AC-025.

Exit: AC-023 through AC-025 pass with source-data and rendered-output comparison.

### Phase 8 — full acceptance and handoff

Status: Local CI-equivalent and privacy gates complete; release exit blocked by configured provider clients, clean Git state, and two physical iPhones

- [x] Run `flutter clean`, resolve locked dependencies, then pass Dart format, `flutter analyze`, all 158 Flutter tests (including legacy dual-read fixtures), Android debug APK, and an iOS Simulator build from an extension-attribute-free `/tmp` source mirror (AC-026 local layer).
- [x] Re-run 52/52 Firestore Rules, 17/17 Auth/Firestore/Functions emulator tests, and the 1/1 Android two-Firebase-app SDK collaboration flow before final closure (AC-026 local layer).
- [x] Install the latest Android APK and visibly confirm the safe configuration-recovery screen when the intentionally ignored Android Firebase file is absent; the app stays running and exposes retry/language actions (AC-026 environment evidence).
- [x] Review logs, source log calls, ignored Firebase files, Git-visible untracked scope, large assets/licenses, diff whitespace, and secret/path patterns; remove temporary PDF artifacts and the machine-specific handoff path (AC-027 local preflight).
- [x] After explicit user authorization, committed the reviewed migration scope locally as `329b52c`; Firebase configuration remained ignored and no remote action occurred (AC-026 local Git layer).
- [ ] Run two physical iPhones through clean install, real Firebase create/join/assign, medication conflict, notification matrix, restart, reconnect, handoff, health, and report/share; compare both clients with authoritative server state (AC-028).
- [ ] Record provider identity, deployed Rules, App Check, APNs/FCM, account recovery, and received-PDF evidence; Android physical-device acceptance remains outside the current iOS-first Beta unless promoted.
- [x] Do not push, deploy, migrate production data, publish, or add RevenueCat/paywalls during this task.

Exit: AC-026 through AC-028 and every earlier case have authoritative evidence; no required blocker remains for the agreed Beta scope.

### Phase 9 — household dashboard UI/UX refresh

Status: Local UI, widget, build, and iOS Simulator visual gates complete; provider and physical-device acceptance remain outside this phase

- [x] Make Today, Medications, Calendar, Health, and Activity household-wide by default with one optional pet filter, accessible pet avatars, and household-time chronological records (AC-011, AC-029).
- [x] Unify task assignment controls and make claimed/completed responsibility states visually distinct without changing the protected transaction flow (AC-030).
- [x] Replace the generic calendar presentation with marked dates and a compact selected-day agenda (AC-031).
- [x] Replace the flat Activity list/report chips with an exact event timeline and prominent care/medication rates derived from the existing reconciled report (AC-032).
- [x] Move invite code, language preference, notification status, and handoff into a coherent Profile hierarchy; default only clean installs to Japanese (AC-033).
- [x] Pass Dart format on 83 files, `flutter analyze`, and 163/163 Flutter tests; build the `main_demo.dart` Android debug APK and isolated iOS Simulator app; visibly inspect Today, Medications, Calendar, Health, Activity, and Profile in CoPaw B with both Mochi and Luna present where records exist (AC-029 through AC-033 local gates).
- [x] Keep pet/medication photo upload, health voice capture, care-task push, and onboarding routine recommendations deferred to separately authorized contracts.

Evidence boundary: this pass used deterministic fake/in-memory demo data and did not run or change Firebase Rules, Functions, real provider sync, notification delivery, system share sheets, or physical-device acceptance.

Exit: AC-029 through AC-033 pass their local widget/visual gates without regressing AC-003 through AC-025 or claiming provider/device acceptance.

### Phase 10 — UI/UX Phase 2: identity, Japanese medication, and notification policy

Status: Local gate complete; provider/device claims remain unchanged

- [x] Add rabbit as a canonical pet species and make dog/cat/rabbit symbols plus deterministic per-pet colors consistent across filters, care cards, calendar, medication, and profile (AC-034).
- [x] Remove duplicate pet/category symbolism from care cards and use task-category icons only for the action (AC-034).
- [x] Replace seeded English care, medication, dose, instruction, and health content with Japanese while preserving arbitrary user-entered text (AC-035).
- [x] Make Medication an archive with today status plus separate active/stopped medicines; add tappable purpose, possible-side-effect, dose/frequency/timing/instruction, schedule-history, and unavailable-photo details while preserving server-confirmed outcomes (AC-036).
- [x] Explain the current notification policy and distinguish implemented medication escalation from planned urgent/assignment alerts without implying provider delivery (AC-037).
- [x] Pass Dart formatting on 83 files, `flutter analyze`, 166 Flutter tests, 52 Firestore Rules tests, and 17 Auth/Firestore/Functions emulator tests; build the demo iOS Simulator app and Android debug APK from one clean `/tmp` mirror after the Documents file-provider metadata blocked in-place codesign/shader execution; visibly verify the Japanese Today and Medication archive on CoPaw B, including dog/rabbit identity, current/past medicines, and no false terminal medication state (AC-034 through AC-037 local layers).

Evidence boundary: notification policy copy distinguishes implemented deterministic reminder scheduling from provider delivery. No FCM/APNs delivery, Firebase Storage upload, deployed Rules/Functions, or physical-device behavior was exercised.

Exit: AC-034 through AC-037 pass locally; no photo upload or new notification provider claim is made.

### Phase 11 — UI/UX Phase 3: medical record and doctor-readable report

Status: Local data/UI/PDF gate complete; remote photos, system share sheet, and device acceptance remain open

- [x] Reframe Health as the complete pet medical record with visit/diagnosis/prescription/veterinarian-instruction and mood prompts plus photo attachment affordances (AC-038).
- [x] Add structured water-intake milliliters through models, repository, Rules, UI, and report aggregation without inferring missing values (AC-038, AC-039).
- [x] Replace vague report buckets with exact care events, medication names/doses/outcomes, water source values, basis-safe daily summaries, and dated health observations in both Activity and the explicit-share PDF (AC-039, LT2-AC02).
- [x] Keep medical copy non-diagnostic and make every unavailable source or remote-photo capability explicit (AC-038, AC-039).
- [x] Pass the consolidated 166 Flutter / 52 Rules / 17 Functions gates and both isolated demo platform builds; generate the Japanese PDF fixture, extract the exact medicine/dose, 420 ml water, visit detail, and missing-data disclaimer with `pdfplumber`, and render/inspect its single A4 page without clipping, overlap, or broken Japanese glyphs (AC-038, AC-039 local layers).

Evidence boundary: Health photo controls explicitly report secure sync as unavailable. The report was rendered and text-reconciled locally; the real iOS/Android system share sheet, receiving app, Firebase Storage privacy/Rules, configured provider, and physical devices remain unverified.

Exit: AC-038 and AC-039 pass at the local data/UI/PDF layers; Firebase Storage, provider delivery, system share-sheet, and physical-device acceptance remain open.

### Phase 12 — unified Today and daily health check-in

Status: Local repository/Rules/widget/build and Android-emulator visual gates complete; configured-provider, concurrent same-day two-client, remote-photo, and physical-device evidence remain open

- [x] Merge routine care and medication doses into one household-time chronological Today list without weakening confirmed medication outcomes (AC-040).
- [x] Add one structured daily health template for water, appetite, urination, stool, energy, and mood/behavior, with optional measured water and notes and an honest unavailable-photo state (AC-041).
- [x] Keep the Medication tab focused on current/past medicine records and confirmed administration history, and keep medical reports source-only with no inferred normal values (AC-040, AC-041).
- [x] Pass `flutter analyze`, 173 Flutter tests, 7 focused Firebase health repository tests, and 53 Firestore Rules tests using Android Studio's bundled JBR; after the final narrow-screen layout adjustment, rerun the combined UI/health repository selection with 58/58 passing; build `main_demo.dart` as an Android debug APK and install/launch it on the API 36 `copaw_api36` emulator.
- [x] Visibly inspect the unified Today list, Medication current/past/outcome-history sections, Health daily status, and the Japanese daily-entry dialog; confirm the final narrow Android layout has no observed Flutter exception or RenderFlex overflow.

Evidence boundary: the daily template uses household-local display dates and prevents a second entry in the deterministic single-client UI flow. A configured-provider two-client race could still create duplicate same-day records because server-enforced daily idempotency was not added in this phase. Secure health-photo sync and physical-device behavior remain unverified. A separate authorized task owns the local Firebase bootstrap files and will rerun the consolidated Rules/Functions/two-client gates after this UI phase.

Exit: AC-040 passes at the deterministic and Android-emulator layers. AC-041 passes at the deterministic single-client and Android-emulator layers; concurrent two-client idempotency remains an explicit provider-layer follow-up rather than a release-ready claim.

### Phase 13 — local Firebase full-app wiring

Status: Local Auth/Firestore/Functions development loop complete; production provider and physical-device gates unchanged

- [x] Add an isolated `main_emulator.dart` entry point using the `demo-copaw` project with explicit non-secret platform options, Android `10.0.2.2`/iOS `127.0.0.1` routing, disabled Firestore persistence, and no Cloud Messaging token registration (AC-042).
- [x] Correct the Emulator Suite port configuration, add repeatable start/run scripts and a local runbook, and keep real Firebase configuration ignored (AC-027, AC-042).
- [x] Start the final Auth/Firestore/Functions suite successfully, launch the full emulator entry point on the API 36 Android emulator without `google-services.json`, and observe the real create/join start shell rather than the fake demo app (AC-042).
- [x] Pass Dart formatting, `flutter analyze`, 174 Flutter tests, 17 Functions emulator tests, 53 Rules tests, and the Android two-Firebase-app SDK collaboration flow against the final Phase 12 schema/Rules (AC-026, AC-042).
- [x] On 2026-08-16, launch Android and an isolated iOS Simulator build against one restored `demo-copaw` Firestore dataset; create `CoPawLocalHome` and `Mochi`, join iOS from Android with the invite code, create `EveningMeal` on Android, and observe it on both clients after an emulator export/restart/import.
- [x] Replace the invalid five-character local API key placeholder with a syntactically valid non-secret demo key and add a focused regression test; the five local bootstrap tests pass.

Evidence boundary: this proves local emulator wiring and visible Android/iOS Firestore synchronization. The current iOS run required an isolated build that excluded the ignored production plist; a dedicated reproducible iOS-local scheme is still open. The devices reused persisted anonymous credentials while the restarted Auth emulator had no accounts, so a clean two-client Auth lifecycle remains unverified. Callable Functions loaded under Node 22; the scheduled reminder was ignored because Pub/Sub was not running. Firebase Installations is not emulated and made a failed request for `demo-copaw`, so the iOS path is isolated from production but not fully offline. This does not deploy or inspect the real Firebase project, prove App Check/FCM/APNs, enforce concurrent same-pet same-day health-check-in idempotency, or replace AC-028 physical-iPhone acceptance.

Exit: AC-042 passes at the local Android/emulator layer without production writes or secrets.

### Long task Phase 0 — preserved local checkpoint

Status: Verified local WIP checkpoint; not release-safe and not authorized for push or deployment

- [x] Record the exact branch, dirty scope, existing simulators, Firebase ports, toolchain, and unverified provider/device paths before editing.
- [x] Pass Dart format on 86 files, `flutter analyze`, 175 Flutter tests, 17 Functions tests under Node 22, 53 Rules tests with the Android Studio JBR, the Android two-Firebase-app SDK flow, and an Android debug build.
- [x] Reproduce the saved-worktree iOS FileProvider/SPM failure, then pass an isolated `/tmp` iOS Simulator build after excluding the ignored production Firebase plist and its resource reference.
- [x] Export the existing `demo-copaw` Emulator data before backend/integration tests and restore that exact export afterward; confirm all seven callable definitions load under Node 22.
- [x] Remove the machine-specific JDK path from the startup script, fail fast outside Node 22, document the two-client integration command, and refresh `HANDOFF.md` evidence.
- [ ] Close daily check-in cross-client idempotency, water-total semantics, exact legacy health-write compatibility, handoff stale-form conflict handling, and the dedicated iOS-local scheme in Long task Phases 1–2.

Evidence boundary: this checkpoint intentionally preserves the previous Phase 9–13 work as one locally verified WIP state. It does not prove production Firebase, App Check, APNs/FCM, recoverable accounts, physical devices, system-share receipt, or release readiness. The current iOS source still references an ignored production plist and must not be launched as a local-emulator build until the dedicated scheme is implemented.

### Long task roadmap

| Long task phase | Outcome |
| --- | --- |
| LT-1 | Freeze the canonical Firestore schema, legacy dual-read/write policy, indexes, migration, and local-to-staging contract. |
| LT-2 | Fix Calendar, shared pet selection, handoff compare-and-set, daily health idempotency, and report-source correctness. |
| LT-3 | Move to five primary tabs and repair Today, Profile, narrow-screen, contrast, Dynamic Type, and semantics. |
| LT-4 | Add an append-only collaboration event ledger, Updates, and separated Activity timeline/report surfaces. |
| LT-5 | Add release/reassign/takeover plus accepted and closed household handoff sessions. |
| LT-6 | Route notifications by responsibility/backup with stable installation dedupe, deep links, inbox, preferences, and summaries. |
| LT-7 | Complete clean local Firebase, migration, Node 22, iOS-local, and two-client acceptance. |
| LT-8 | After explicit authorization, promote to an independent Firebase staging project and run provider/device acceptance. |
| LT-9 | Built, no paywall: long-term search, custom report ranges/sections, source-attributed visit pack, care coverage summary. Whether anyone would pay is still unvalidated. |
| LT-10 | After explicit data-transfer approval, add source-grounded AI organization without diagnosis or treatment advice. |
| LT-11 | Run full regression, independent review, privacy/outgoing-scope checks, and evidence handoff. |

### Long task Phase 1 (LT-1) — schema and promotion contract

Status: Local contract, callable writers, guarded classifier, and safety gates
implemented; migration apply/rollback, retained-client rollout, staging, and
production evidence remain open

- [x] Draft `docs/firestore-schema.md` as the canonical target, explicitly
  separating the last accepted Health v1 baseline from the local LT-2 Health v2
  work-in-progress and its evidence-based v1 read-only compatibility window.
- [x] Define immutable `recordedLocalDate` and
  `recordedTimeZoneIdentifier` semantics, deterministic daily identity, and
  `singleIntake`, `localDayToDate`, reserved `fullLocalDay`, and reader-derived
  `legacyUnknown` water semantics without inventing a basis for Health v1
  records (LT2-AC01, LT2-AC02 contract layer only).
- [x] Add `docs/FIREBASE_PROMOTION_MIGRATION.md` with synthetic Emulator
  fixtures, independent staging, production's four authorization gates,
  reader-first/zero-rewrite default, reconciliation receipts, preconditioned
  rollback, privacy boundaries, notification kill switch, and stop conditions
  (LT1-AC02 through LT1-AC08 contract layer only).
- [x] Add the five-class legacy migration matrix to
  `docs/legacy-firestore-contract.md`; no field, document, or production repair
  is authorized by classification alone.
- [x] Register the versioned `firestore.indexes.json` artifact in
  `firebase.json` with an intentionally empty composite-index baseline. The
  target project's Console indexes must be inventoried and reviewed before any
  index deployment; this file must not be used to delete remote indexes.
- [x] Record LT1-AC01 through LT1-AC08 and the LT-2 daily/water acceptance
  contracts in `BUILD_SPEC.md` without claiming executable or provider proof.
- [x] Independently review the schema contract against Rules, Functions, Dart,
  the retained clients, and live queries; fix the breaking deployment order,
  default production alias, ordinary/daily writer authority, and random-ID v1
  daily conflict boundary. Retained-client rollout evidence is still required
  before writer-closing Rules may be deployed (LT1-AC01).
- [x] Add deterministic synthetic fixtures and an Emulator-only, dry-run-only
  classifier with exact path/class assertions and a content-free deterministic
  receipt. It deliberately refuses apply mode (partial LT1-AC02).
- [ ] Implement the reviewed apply plan, protected before-image manifest,
  second-run zero-write proof, reconciliation, and rollback drill before
  LT1-AC02 can pass.
- [x] Implement and test a project-bound, server-controlled notification
  dispatch kill switch that defaults off and fails closed. Provider activation
  remains separately authorized under LT1-AC08.
- [ ] Inspect an explicitly authorized independent staging project and its
  existing indexes before deployment; no staging or production access is
  authorized by this phase.

Evidence boundary: local contract and implementation evidence does not prove a
safe retained-client rollout. The current Rules close direct Health writes, so
Functions and dual-read/all-writes-callable clients must be adopted before
those Rules can be promoted. No migration apply, backup, rollback, Firebase CLI
deployment, remote index comparison, staging/production access, notification
activation, or physical-device flow was performed. The empty index manifest is
not deployed evidence.

Exit criterion: LT1-AC01 requires final consolidated local review;
LT1-AC02 requires apply/idempotence/reconciliation/rollback; LT1-AC03 through
LT1-AC05 require separately authorized staging evidence. LT1-AC06 through
LT1-AC08 remain production/provider authorization gates. This phase must not be
reported complete before those exact layers pass.

### Long task Phase 2 (LT-2) — collaboration correctness and source truth

Status: Consolidated local implementation, Emulator/build acceptance, and
independent closure review pass; provider/device layers remain open

- [x] Align Monday-first Calendar headers with the Monday-first date grid and
  assert header/date column coordinates in English and Japanese.
- [x] Preserve one selected-pet filter across Today, Medications, Calendar,
  Health, and Activity; test both filtered data and reset to all pets.
- [x] Add handoff compare-and-set with `expectedRevision`; a stale save shows a
  conflict and keeps the user's form values instead of overwriting revisioned
  data.
- [x] Route ordinary and daily Health v2 writes through authenticated callables;
  server-author date/timezone/pet/actor snapshots, use deterministic request
  receipts, and block legacy random-ID daily duplicates.
- [x] Treat malformed Health documents as an incomplete source: Health and
  Activity show a count, and report/PDF sharing is disabled until the source is
  repaired.
- [x] Reduce water only by declared basis: sum separate intakes, prefer the
  latest day-to-date value unless a reviewed full-day value exists, keep every
  source record visible, and label excluded overlap/legacy values.
- [x] Re-run the full Flutter, Rules, Node 22 Functions, two-client Android,
  Android build, isolated iOS build, rendered PDF, privacy, and diff gates; then
  obtain independent data/security and UI closure review. Current evidence is
  Dart format on 88 files, clean analysis, 188 Flutter tests, 56 Rules tests, 29
  Functions tests, the Android two-Firebase-app collaboration test, both
  platform builds, and three deterministic migration tests. The exact Phase 0
  Emulator export was restored after the mutating acceptance flow.

Independent data/security and UI reviews found no remaining local P0. The
latest Japanese PDF rendered normally in both Poppler and Apple Quick Look, but
Android/third-party receiver compatibility and a fixed raster regression remain
open P1 evidence rather than a claimed pass.

Evidence boundary: local unit/widget/Functions/Rules and rendered PDF checks do
not prove retained-client deployment, App Check, remote Firebase, APNs/FCM,
system share-sheet completion, recoverable accounts, or two physical iPhones.

Exit criterion: LT2-AC01 and LT2-AC02 must have current consolidated local
evidence and no open P0 review findings. Staging/provider/device portions remain
explicitly open for LT-8.

### Long task Phase 3 (LT-3) — five destinations and accessible surfaces

Status: Local implementation checkpoint complete; release/device acceptance open

- [x] Replace the six-destination bar with Today, Calendar, Updates, Records,
  and Profile without losing Medication, Health, factual history, report, or
  household-setting reachability.
- [x] Give Records explicit secondary destinations for medication, health,
  factual timeline, and 7/30-day reports; do not use the collaboration ledger as
  a report source.
- [x] Verify Today and Profile at 320–430 logical pixels, English/Japanese, text
  scales 1.0/2.0/3.0, and software-keyboard/error states.
- [x] Add semantics, touch-target, selected-state, and contrast evidence; keep
  status text explicit rather than color-only.
- [x] Re-run protected medication, shared pet filter, Monday-first Calendar,
  malformed Health, exact report, and locale-persistence regressions
  (LT3-AC01 through LT3-AC06).

Local evidence: complete 320×568/390×844 × English/Japanese × 1.0/2.0/3.0
Today matrix; keyboard/failure/retry Profile tests; navigation/row/control
semantics; exact-surface contrast; Flutter 219/219; Android debug and clean-mirror
iOS Simulator builds. Physical visual and VoiceOver/TalkBack review remains open.

Evidence boundary: local widget and visual evidence cannot prove VoiceOver or
TalkBack on physical devices. The navigation change must not activate provider,
AI, payment, or remote-photo behavior.

### Long task Phase 4 (LT-4) — append-only Updates and factual Records

Status: Local implementation checkpoint complete; release/provider acceptance open

- [x] Add an immutable member-readable/server-written event ledger with
  deterministic source/revision/transition identity, trusted actor/time, and
  historical pet/task snapshots.
- [x] Emit zero events for rejected/stale mutations and at most one for accepted
  retry/replay/race paths; preserve the authoritative source document as truth.
- [x] Add paged Updates with deterministic order, explicit cache/incomplete/error
  states, legacy-start boundary, and per-member read cursor.
- [x] Keep collaboration Updates separate from factual pet history and 7/30-day
  reports; reconcile shared source references without changing report counts.
- [x] Verify Rules, Functions/repository concurrency, two-client convergence,
  privacy redaction, and LT4-AC01 through LT4-AC04 before closure.

Local evidence: Functions 35/35; Rules 62/62 with zero expression-budget/call-stack
warnings; Flutter repository/widget coverage within 219/219; Android two-client
Firebase SDK integration 1/1; deterministic replay, opaque pagination, private
read cursor, conservative offline/error UI, and medication text redaction. Real
offline/provider deployment, retained-client retirement, and physical devices
remain open.

Evidence boundary: Cloud Functions trigger delivery is not assumed exactly once.
Any non-transactional projection must be idempotent and the UI must not describe
a temporarily missing event as proof that no transition occurred.

### Long task Phase 5 (LT-5) — consented responsibility and handoff sessions

Status: Local implementation checkpoint verified; two-client/provider/device
acceptance remains open

- [x] Keep the canonical task status values `unclaimed`, `claimed`, and
  `completed`; do not add a retained-client-breaking task status.
- [x] Add callable-only self-release plus consented reassign/takeover proposals.
  Reassign transfers only after the target accepts; takeover transfers only
  after the current assignee accepts. No member gets unilateral takeover power.
- [x] Store pending transfer authority in a server-owned sidecar/control record
  so old task decoders stay compatible; block retained direct writers from
  mutating a task while a transfer is pending.
- [x] Move the new client's completion path to the same expected-revision,
  receipt-backed server authority needed to race safely with LT-5 transitions.
- [x] Keep `handoff/current` as the editable template; create immutable handoff
  versions and server-owned offered/accepted/closed sessions with one active
  pointer per household.
- [x] Add household-wide planned start/end, participants, trusted transition
  times, template-version reference, terminal states, and source-derived close
  reconciliation without copying handoff content into ledger/receipts/logs.
- [x] Split true membership revocation from local device disconnect. True leave
  must disable that member's household installations and reject owners or
  members with unresolved responsibility/session obligations with actionable
  copy.
- [x] Version the collaboration projection for task responsibility and handoff
  session facts while keeping task/session source documents authoritative and
  reports independent of the ledger.
- [ ] Pass LT5-AC01 through LT5-AC12 with Functions/Rules/repository/widget,
  legacy, race/retry, privacy, and two-client Emulator evidence; obtain an
  independent closure review before the local checkpoint.

Local evidence (2026-08-17): Dart format checked 112 files with zero changes;
Flutter analyze passed; Flutter tests passed 252/252; isolated Functions passed
49/49; isolated Rules passed 65/65 with zero expression-budget/call-stack
warnings; Android debug and a clean temporary-mirror iOS Simulator build both
passed. Independent server and Flutter reviews closed all discovered local
P0/P1 findings, including pinned handoff-version consent, orphan authority,
leave/rejoin races, notification-claim draining, and recoverable 501-token
revocation. The final checklist item remains open because a clean Flutter
two-client Emulator run and physical/provider follow-up have not run.

Decision: LT-5 uses a consent-first model. A forced direct reassignment or
unilateral takeover is explicitly out of scope until household roles and
administrator authority are separately designed and approved.

Evidence boundary: a local checkpoint does not authorize App Check/provider
deployment, retained-client retirement, sensitive production handoff data,
recoverable-account release, or physical-device acceptance.

### Long task Phase 6 (LT-6) — routed reminders and private inbox

Status: Bounded local implementation and independent P0/P1 review complete;
real provider, remote Firebase, two-client, and physical-device acceptance pending

- [x] Separate OS permission, CoPaw category preferences, stable installation
  readiness, and provider verification in the domain and UI.
- [x] Generate deterministic private reminder intents from authoritative task,
  medication, handoff, membership, and preference state; never from ledger or
  inbox state.
- [x] Route claimed medication to the responsible member and explicit backups,
  route unclaimed/direct/urgent cases by documented opt-in rules, and suppress
  terminal/cancelled/closed sources immediately before dispatch.
- [x] Extend true-leave authority checks so an unresolved claimed medication
  whose due/+15/+30 window is future or active cannot retain a departed
  responsible member.
- [x] Use source/level/recipient-membership-epoch intent identity and one-time
  materialized stable installation identities for delivery; token rotation or
  duplicate-token canonical drift must not create a second semantic delivery.
  Keep provider-acceptance ambiguity explicit.
- [x] Add a private paged Reminders inbox, per-member monotonic read cursor,
  conservative cache/error unread state, and Changes/Reminders separation under
  Updates without affecting Activity/report/PDF.
- [x] Add typed generic deep-link recovery for foreground/background/killed,
  repeated, expired, offline, and wrong-household clicks after Auth/session and
  membership validation. No click may execute a care mutation.
- [x] Add household-timezone preferences, quiet hours, summary/burst coalescing,
  and backup opt-in; medication and urgent reminders are not silently delayed.
- [x] Keep intent generation and provider dispatch behind separate project-bound
  default-off switches; main emulator remains provider-free.
- [x] Pass LT6-AC01 through LT6-AC08 locally and retain LT6-AC09 as the separately
  authorized APNs/FCM staging/physical-device gate.

Evidence boundary: this phase may implement deterministic local contracts and
fake messaging only. It must not configure, deploy, enable, or claim APNs/FCM,
remote schedulers, App Check, production tokens, sounds, badges, background
delivery, or exactly-once display.

Local evidence (2026-08-17): Dart format checked 128 files with zero changes;
Flutter analyze passed; Flutter tests passed 321/321; isolated Functions passed
73/73 sequentially; isolated Rules passed 72/72 with no expression-budget or
call-stack warning; Android debug APK and an iOS Simulator app from a clean
`/tmp` mirror both built. Independent server/data and Flutter/UI reviewers
closed all discovered local P0/P1 findings, including provider-start authority,
digest recovery, medication effective-version semantics, membership-epoch
isolation, notification lifecycle races, exact failed-page retry, stale provider
evidence, compact semantics, and actual Material surface contrast.

Evidence boundary: the v2 generation and dispatch gates were not created or
enabled, provider calls used deterministic fakes, and no Rules/indexes/Functions
were deployed. Node 22 runtime parity, clean local two-client Firebase flows,
real APNs/FCM, foreground/background/killed provider behavior, remote indexes,
physical-device notification presentation, VoiceOver/TalkBack, and LT6-AC09
remain unverified.

### Long task Phase 7 (LT-7) — repeatable local Firebase acceptance

Status: Local tooling, preservation, timezone, and iOS-local entry accepted;
two-process source/offline phases still open

- [x] Add one repository-pinned Node 22 entry point used by Emulator, Rules,
  Functions, migration, export, and restore commands; reject other majors and
  missing/old Java before opening a Firebase port (LT7-AC01).
- [x] Freeze and test the exact 24 Functions exports under Node 22, then prove
  successful Emulator source discovery without a runtime-major warning or
  discovery timeout (LT7-AC02).
- [ ] Parameterize an isolated local Firebase acceptance environment and run
  two independent Flutter OS processes/app sandboxes from clean Auth/session
  state through create, invite/join, restart, and realtime convergence
  (LT7-AC03).
- [x] Add a versioned synthetic canonical-plus-legacy seed manifest and guarded
  Auth/Firestore export/import reconciliation with content-free fingerprints;
  cover the exact LT4 ledger/cursor, LT5 transfer/session/pointer, and LT6
  preference/inbox/cursor/delivery sentinels as well as earlier sources; never
  import production data or operate on a non-demo project (LT7-AC04).
- [x] Extend only the read-only migration path so the approved migration-scope
  Emulator fixture produces two identical content-free dry-run receipts, zero
  planned/applied writes, and an unchanged before/after fingerprint. Keep
  the five-class denominator limited to the frozen legacy migration paths,
  report other canonical paths as excluded-by-scope, and keep apply, rollback,
  staging, and production paths unavailable (LT7-AC05).
- [x] Add a committed shared iOS-local scheme/config for
  `lib/main_emulator.dart` with a distinct local bundle, no production plist or
  APNs entitlement, Messaging native auto-init/proxy disabled, and static plus
  runtime proof that remote-notification registration/token writes stay off
  while Auth/Firestore/Functions use loopback (LT7-AC06).
- [ ] Exercise offline/restart/import-restart/reconnect/cache and retry identity
  across the independent clients; require server-authoritative convergence with
  medication outcome and Health identities retained until authoritative
  resolution, no duplicate collaboration source/event/listener, and no
  optimistic safety claim (LT7-AC07).
- [x] Reconcile the frozen legacy matrix and household-timezone behavior across
  Tokyo midnight and New York DST gap/fold: routine gaps and medication reject
  policy reject invalid wall time, notification quiet gaps/folds use their
  frozen first-valid/first-occurrence rules, and Health persists the local date
  derived from a trusted instant. Invalid/malformed sources remain visible
  diagnostics and never trigger inferred repair writes (LT7-AC08).
- [ ] Obtain independent server/data and Flutter/iOS closure reviews, rerun the
  current deterministic suites and both platform builds, and record all
  unverified provider/physical-device boundaries before a local checkpoint.

Findings from the first real two-process run (recorded, not yet fixed):

1. The iOS-local entry point could never run an integration test. Three
   committed defects had to be fixed before any coordinated phase executed:
   a missing App Transport Security exception for the Emulator's plaintext
   loopback traffic, missing Bonjour/local-network keys for Dart VM Service
   discovery, and a pinned `FLUTTER_TARGET` in `Debug-local.xcconfig` that
   overrode the entry point `flutter test` generates, so the local build
   launched the real app and every phase hung on a handshake that never came.
2. Confirmed Rules defect, still open. `notificationInbox` and
   `notificationDeliveries` authorize `list` per document by membership epoch,
   but a list rule that touches `resource` cannot be evaluated when the query
   matches nothing, so a real client listing an empty collection is denied with
   an evaluation error. `tests/firestore.rules.test.mjs` carries this as a
   `todo`. The fix is to encode the membership epoch in the path so the rule can
   authorize from path variables; relaxing the epoch check would let a rejoined
   member list their previous membership's notifications.
3. Pre-existing suite defect, not introduced by LT-7 and reproduced with the
   LT-7 changes stashed: `functions/test/notifications_v2.test.mjs` "P1 generator
   resolves recipients..." fails in the full run (materialized 3, expected 1)
   while passing in isolation, so that suite is order-dependent.
4. Routines reject nonexistent wall time but accept the ambiguous fall-back
   hour, unlike medication's `dstPolicy = reject`. The current behavior is now
   locked by a test; aligning the two policies is a product decision.
5. This machine cannot build both iOS clients at once. The harness warms each
   client up serially, then runs bootstrap concurrently (both sides must be
   live) and later phases staggered.

Decision: LT-7 "second migration run" means a second read-only dry-run over
the identical approved synthetic Emulator scope. It does not implement or
claim migration apply idempotence, before-image manifests, rollback, staging,
production inventory, or zero production writes. The only zero-write claim is
that the local read-only runner refuses non-`demo-copaw`/non-Emulator inputs and
leaves the local before/after fingerprint unchanged.

Evidence boundary: LT7-AC03 is partially verified. Two independent Flutter OS
processes on two iOS Simulators reached server-authoritative convergence through
the bootstrap and reconnect phases (distinct persisted UIDs, one shared
household, two members, stable across a process restart). The source and offline
phases did not pass: the source phase is blocked by finding 2 above. LT7-AC07 is
therefore unverified. The existing single-process second `FirebaseApp`
integration test remains useful SDK concurrency coverage but cannot satisfy
LT7-AC03. Two
independent Flutter OS processes with separate sandboxes are required. LT-7
does not authorize deploy, remote index creation, production exports, App Check,
APNs/FCM, RevenueCat, or physical-device claims. Anonymous UID persistence
across a process restart is not account linking, cross-install recovery, or
recoverable sign-in evidence.

### Long task Phase 9 (LT-9) — Plus-tier features, built without a paywall

Status: All four features implemented and available to everyone

`PlusFeature` records which features are planned for a future paid tier. There
is no billing, entitlement check, usage cap, or paywall, and nothing in the
interface mentions payment. Introducing a tier means replacing
`PlusFeatureAccess`, not rewriting each feature.

- [x] Long-term search across health, medication outcomes, and tasks, filtered
  by pet, inclusive household-local date range, kind, and stored text. Records
  whose local day cannot be determined are reported separately instead of being
  placed on a guessed date.
- [x] Custom report ranges up to a year and per-section selection. Excluding a
  section removes it from the rendered report and PDF while the summaries stay
  computed from real sources, so an excluded section never reads as a zero.
- [x] Source-attributed visit pack for a veterinarian or a stand-in caregiver.
  Every line carries who recorded it and when; unresolved doses are never
  reported as outcomes, and a section with nothing recorded says so.
- [x] Care coverage summary naming doses without an owner, doses without a
  recorded outcome, overdue unassigned tasks, and days without a health record.
  Responsibility is not treated as an outcome.

Evidence boundary: these are local implementations verified by unit and widget
tests. Whether any of them is worth paying for is unvalidated: no pricing
research, no user interviews, and no willingness-to-pay signal were collected.
That validation, not the implementation, is what LT-9 originally asked for.

## Agent responsibility pattern

For each implementation phase:

1. One bounded implementer owns the phase-specific files.
2. One independent reviewer inspects schema, state, Rules, privacy, and changed-line scope without relying on implementer conclusions.
3. One acceptance runner exercises a clean environment and records scenario, observation, evidence, and unverified paths.
4. The primary agent resolves review findings, updates this plan, and decides whether the phase gate is actually met.

## Failure log

Use one of: `SPEC_TRANSLATION`, `IMPLEMENTATION`, `ENVIRONMENT`, `NETWORK_OR_PROVIDER`, `TEST_ORACLE`.

| Acceptance ID | Observation | Class | Narrowest next action | Status |
| --- | --- | --- | --- | --- |
| Baseline | Rules Emulator initially could not run because shell Java was missing | ENVIRONMENT | Reused Android Studio JDK explicitly; 17/17 Rules tests passed | Resolved |
| Baseline | Swift worktree build initially lacked ignored Firebase plist; linker also failed in the same run | ENVIRONMENT | Copied ignored local plist and reran in clean DerivedData; build passed | Resolved |
| Phase 1 | Android has no local `google-services.json`, so real Firebase initialization cannot yet be verified | ENVIRONMENT | Keep failure visible; obtain ignored Android Firebase config before Android provider acceptance | Open |
| Phase 1 | iOS build initially failed because Firebase Flutter packages require iOS 15 while the template used iOS 13 | ENVIRONMENT | Raised Flutter Runner deployment target to iOS 15; next build reached signing and later passed | Resolved |
| Phase 1 | Flutter SDK and project under Documents/FileProvider attach extended attributes to copied `Flutter.framework`, which codesign rejects | ENVIRONMENT | Pointed ignored `build/` to an isolated `/tmp` output; iOS Simulator build passed | Resolved for local verification; document environment workaround |
| Phase 1 | New Android API 36 AVD initially raised a System UI ANR during first boot | ENVIRONMENT | Waited for cold-start completion, dismissed the System UI dialog, launched the activity explicitly, and captured the live configuration-error screen with no app crash | Resolved |
| AC-014–AC-019 | A strict Dart occurrence check compared `DateTime` representation instead of the represented instant and rejected a valid Firestore timestamp | IMPLEMENTATION | Compare with `isAtSameMomentAs`, add a repository regression test, and rerun the Android SDK flow | Resolved |
| AC-017 | Android emulator briefly went offline during an integration install | ENVIRONMENT | Confirmed ADB recovery and reran the full Auth/Firestore/Functions SDK flow | Resolved |
| AC-018 / AC-021 | Medication callables enforce App Check outside emulators, while the Flutter app has no activated App Check provider yet | NETWORK_OR_PROVIDER | Configure platform providers and verify real callable requests only with explicit Firebase-project access; do not deploy from this phase | Open |
| AC-018 / AC-028 | No physical iPhone is connected, so network fault, restart/reconnect, and two-device medication acceptance cannot be claimed | ENVIRONMENT | Run the recorded flows on two physical iPhones when available | Open |
| AC-020 / AC-021 | Local dispatch and UI gates pass, but real APNs/FCM configuration, scheduler execution, token lifecycle, foreground/background/killed delivery, and notification clicks are not available in the emulator-only evidence | NETWORK_OR_PROVIDER | Configure ignored platform provider files and run the recorded notification matrix without deploying from this task | Open |
| AC-020 | Firestore delivery state and FCM/APNs acceptance cannot be committed atomically; collapse IDs and a 14-minute expiry reduce stale/duplicate display but do not prove exactly-once after ambiguous provider acceptance | NETWORK_OR_PROVIDER | Choose and document the acceptable retry tradeoff, then verify duplicate/missed-delivery behavior with real provider fault injection | Open |
| AC-021 | Android has no provider configuration and foreground notification-message presentation is not implemented as an Android system banner | ENVIRONMENT | Obtain ignored Android Firebase configuration and validate whether visible in-app overdue state is sufficient or add a privacy-safe local foreground presentation in the device phase | Open |
| AC-022 | Android device time was about 117 ms ahead of the Firestore emulator, so a strict `recordedAt <= request.time` rule rejected a valid “record now” write | IMPLEMENTATION | Allow at most five seconds of clock skew in Rules and the Dart decoder; keep +60-second future writes rejected and add regression coverage | Resolved |
| AC-022 | The Android AVD twice went offline while starting the integration test and one shader compiler process exited with `-9` | ENVIRONMENT | Cold-started the AVD, waited for boot completion, then reran the full SDK flow successfully | Resolved |
| AC-022 | Anonymous Auth has no uninstall/other-device account recovery and the latest health UI has not been visibly exercised with a configured provider client | ENVIRONMENT | Keep local AC-022 evidence separate; add account linking before production health release and run configured-device acceptance when available | Open |
| AC-025 | Local PDF rendering/text/visual checks and share failure recovery pass, but the system share sheet and received file have not been inspected on a configured device | ENVIRONMENT | Open the latest report on a configured iPhone and Android emulator, share explicitly, then compare the received PDF with the selected pet/range in-app data | Open |
| AC-026 | A clean Flutter rebuild again exposed FileProvider `com.apple.provenance` on `Flutter.framework`, which simulator codesign rejects | ENVIRONMENT | Copy the exact source without extended attributes to an isolated `/tmp` mirror; the iOS Simulator build passed there after clean dependency resolution | Resolved for local verification |
| AC-026 | The long-task baseline and LT1–LT2 changes needed recoverable local checkpoints without authorizing remote transfer | ENVIRONMENT | After user approval, reviewed exact staged scope and created local commits `3cde6ee` and `9a3845a`; no push or deployment occurred | Resolved locally; outgoing history review remains required before any remote action |
| AC-028 | Current environment has no two physical iPhones or configured real-provider Android client | ENVIRONMENT | Run the recorded two-device/provider matrix when hardware and ignored provider configuration are available | Open |
| AC-042 | Running the Functions tests without the required emulators produced Auth network and local-credential failures | ENVIRONMENT | Added and used `npm run test:functions`, which starts Auth/Firestore/Functions around the suite; 17/17 passed | Resolved |
| AC-042 | Functions declares Node 22 but the current host provides Node 24, so the emulator warns and uses Node 24 | ENVIRONMENT | Keep local evidence separate; use Node 22 before claiming deployment-runtime parity | Open |
| AC-042 | On 2026-08-16, Node 24 exposed ports but Functions source discovery timed out after 60 seconds | ENVIRONMENT | The interactive start script now rejects non-Node-22 runtimes; unify Rules, Functions, migration, export, and restore behind one repository-pinned Node 22 entry and exact export-discovery receipt | Open until every local entry uses and verifies the pinned runtime |
| AC-042 | The ignored production iOS plist was copied into the first local iOS build and native Firebase attempted a real-project Installations request before Dart configured emulators | IMPLEMENTATION | Rebuilt from an isolated `/tmp` mirror with the plist excluded; add a dedicated iOS-local build scheme before calling this repeatable | Open |
| AC-042 | The iOS local placeholder API key was too short and Firebase Installations terminated the app | IMPLEMENTATION | Replaced it with a syntactically valid non-secret demo key and added a focused test; the app now launches | Resolved |
| AC-042 | Both clients reused persisted anonymous credentials after the Auth emulator restarted, so Firestore sync passed while the Auth UI contained no accounts | TEST_ORACLE | Run a clean-install two-client Auth/create/join flow against one continuously running suite and verify both UIDs in the Auth UI | Open |
