# CoPaw Flutter migration handoff

Last updated: 2026-08-17 (Asia/Tokyo)

## Workspace

- Worktree: current `0808 Revenuecat Hackathon-flutter-migration` checkout.
- Branch: `codex/flutter-migration`
- Original Swift workspace remains separate at `0808 Revenuecat Hackathon`.
- Do not push, deploy, or publish before the privacy/secret preflight in `AGENTS.md`.

## Product boundary

- Flutter/Dart migration with household collaboration parity.
- Multi-pet, safe medication, health timeline, handoff, and reports are the requested end state.
- RevenueCat, entitlements, prices, trials, paywalls, and Raven Cache are explicitly deferred.

## Implemented

- Flutter shell, locale persistence, household create/join/restore/leave, realtime household/profile sync.
- Care tasks/routines, assignment lifecycle, Today/Calendar/Activity, EN/JP UI, error/retry states.
- Server-authoritative routine occurrence materialization through Cloud Functions.
- Multi-pet domain/data/UI, pet filtering, legacy primary-pet compatibility, task/routine pet snapshots.
- Safe-medication server contract:
  - immutable schedule versions;
  - deterministic local-date/slot occurrence IDs;
  - independent responsibility and terminal outcome state;
  - trusted server actor/time/snapshots;
  - administered/skipped once-only transitions;
  - idempotency receipts for ambiguous retries;
  - DST rejection policy;
  - callable-only pet archive, blocked by active medication plans;
  - Rules allow member reads and deny all client authority writes.
- Safe-medication Dart models, Firestore/Functions gateway, repository, occurrence expansion, EN/JP strings, Today dose cards, plan management, and Activity history UI.
- Reliable-notification local implementation: private installation tokens, permission/status recovery, serialized token lifecycle, household-timezone due/+15m/+30m dispatch, cross-midnight/version boundaries, terminal suppression, concurrent leases, unique-device deduplication, invalid-token disable, redacted payloads, short expiry, and iOS foreground presentation configuration.
- Medication archive UI with today status, separate current/past medicines, pet identity, recorded purpose/watch-outs, full schedule history, and an explicitly unavailable secure-photo slot; terminal outcomes remain server-confirmed only.
- Structured medical/health timeline: ten immutable record types including water intake and mood, visit/diagnosis/prescription/veterinarian-instruction prompts, pet/type filtering, limited weight trend, non-diagnostic UI, explicit unavailable-photo affordance, strict codecs, pending/cache handling, listener cleanup, idempotent retry IDs, and member-only Rules.
- Household handoff: one member-only current document with care instructions, emergency/veterinary contacts, monotonic revision, trusted updater/time snapshots, strict codec, cache/pending state, and realtime convergence.
- Reconciled selected-pet 7/30-day reports: household-local range boundaries, routine and one-off care, every immutable medication schedule version, confirmed terminal outcomes, health counts, source actor/times, and non-diagnostic copy.
- Explicit local PDF sharing: bundled Noto Sans JP font and license, selected pet/range only, generic filename, no automatic upload, native system-share adapter, and visible failure/retry state.

## Latest verified evidence

- Dart formatting on 86 files and `flutter analyze` passed at the 2026-08-17 local checkpoint.
- Current full Flutter suite: 175/175 tests passed, including the isolated local Firebase bootstrap, daily health check-in, medication archive/detail/photo-boundary UI, notification-policy copy, structured water input, exact doctor-report detail, Unicode PDF structure, handoff repository/UI, health repository boundaries, and legacy dual-read fixtures.
- Focused medication widget coverage now includes no optimistic confirmation, cached-terminal suppression, terminal-conflict refresh, and skipped reason/history display.
- Firestore Rules: 53/53 passed at the 2026-08-17 checkpoint, including daily health fields, handoff member/outsider, revision and trusted-field boundaries plus the existing health/medication/care coverage.
- Current Auth/Firestore/Functions emulator suite: 17/17 passed. The six notification cases cover redaction, due/+15/+30, terminal suppression, retry, household timezone/effective end, cross-midnight, concurrent schedulers, unique-device recipients, disabled tokens, and invalid-token disable.
- Android Firebase SDK integration: 1/1 passed against Auth/Firestore/Functions emulators. Two independent Firebase app instances raced administer versus skip; exactly one server result won, both listeners converged, and a later plan replacement preserved the historical occurrence snapshot.
- The same Android SDK flow now has two caregivers create health records for two pets through two independent Firebase app instances; both listeners converge on the correct pet/type/actor snapshots without cross-pet mixing.
- The same SDK flow has client A create household handoff, client B update it, and both listeners converge on revision 2 with the trusted client-B snapshot.
- The complete Android two-Firebase-app SDK flow passed again on 2026-08-17 against the preserved local suite; the original interactive Emulator data was exported before the test and restored afterward.
- Ambiguous medication mutations persist only a SHA-256 request fingerprint and mutation ID, survive repository/App restart, and clear after an authoritative or unambiguous response; medication and dose content are not persisted in this marker.
- The latest `main_demo.dart` Android debug APK and iOS Simulator `Runner.app` passed from one clean `/tmp` source mirror. The saved-project path cannot be used as build evidence because FileProvider reattaches Finder metadata and also blocks the cached shader compiler; the Flutter SDK was restored after the isolated builds.
- The 2026-08-17 checkpoint rebuilt the Android debug APK and an isolated iOS Simulator `main_emulator.dart` app. The iOS mirror required removal of the production-plist resource reference, confirming that a committed dedicated iOS-local scheme remains open.
- Android runtime logs contained none of the synthetic pet names or health fixture text used by the SDK test; the health retry marker stores only a SHA-256 request hash and generated record ID.
- A Japanese one-page PDF was rendered and visually inspected; exact medicine/dose, 420 ml water, visit/veterinarian instruction, range, reconciled counts, and missing-data/non-diagnostic statements were readable without clipping or broken glyphs. `pdfplumber` extraction reconciled the same source text.
- The final isolated iOS demo build was installed and launched on CoPaw B. Visible Today and Medication review confirmed Japanese task/dose/instruction copy, dog/rabbit identity and per-pet colors, today dose state, and separate current/past medication records. This was a local fake-data UI review, not Firebase/provider evidence.
- The latest Android APK was installed visibly. With the intentionally absent ignored Android Firebase configuration, it showed the safe configuration-recovery UI, stayed running, and logged only a sanitized bootstrap category/code/platform.
- Final local AC-027 review found Firebase configuration files ignored and untracked, only deliberate demo API-key placeholders in emulator tests, no feature-data analytics, no pet/medication/health content in the inspected runtime log, and no machine-specific path in Git-visible handoff documentation.

## Immediate next verification

1. On a configured iPhone, compare an explicitly shared received PDF with the same selected pet/range report in the app (AC-025).
2. When provider access is authorized, validate App Check, real APNs/FCM token lifecycle, scheduler execution, permission recovery, foreground/background/killed delivery, and the visible health UI.
3. Run the complete create/join/assign/medication/conflict/restart/reconnect/handoff/health/report matrix on two physical iPhones (AC-028).
4. Only after explicit user approval, review the exact outgoing scope again and decide whether to stage/commit; the worktree remains intentionally dirty.

## Known remaining work

- Complete real-provider/device safe-medication acceptance and reconcile any discovered schema/client mismatch.
- Validate App Check in a configured non-emulator Firebase project; emulator intentionally does not provide App Check.
- Complete real-provider/device notification acceptance; local deterministic implementation is complete, but provider acceptance is not atomic with Firestore and exactly-once must not be claimed.
- Complete visible configured-device health acceptance and add recoverable sign-in before production health-data readiness.
- Inspect the real system share sheet and received PDF on configured devices; local PDF visual/text reconciliation is complete.
- Run production migration dry-run/reconciliation and deployed Rules confirmation only in a separately authorized provider phase; no production data was touched here.
- Complete two-device/provider checks, recoverable sign-in/account linking, and independent physical-device acceptance.
- Do not mark the long goal complete until the above phases and evidence gates are satisfied.

## Important files

- `BUILD_SPEC.md`: acceptance contract and AC-001..AC-042.
- `PLANS.md`: phased migration plan.
- `firestore.rules` and `tests/firestore.rules.test.mjs`: current security contract.
- `functions/medication.js`: medication and pet-archive authority.
- `functions/test/medication.test.mjs`: Functions emulator medication contract tests.
- `copaw_flutter/lib/main_emulator.dart`: local-only Flutter entry point.
- `copaw_flutter/lib/src/bootstrap/firebase_emulator_configuration.dart`: explicit demo-project emulator routing.
- `docs/FIREBASE_LOCAL.md`: local Firebase runbook and acceptance commands.
- `copaw_flutter/lib/src/domain/medication_models.dart`
- `copaw_flutter/lib/src/domain/medication_occurrence_service.dart`
- `copaw_flutter/lib/src/data/firebase_medication_gateway.dart`
- `copaw_flutter/lib/src/data/firebase_medication_repository.dart`
- `copaw_flutter/lib/src/data/firebase_handoff_repository.dart`
- `copaw_flutter/lib/src/domain/report_service.dart`
- `copaw_flutter/lib/src/data/report_pdf_renderer.dart`
- `copaw_flutter/lib/src/data/system_report_share_repository.dart`
- `copaw_flutter/lib/src/views/household_home_view.dart`
