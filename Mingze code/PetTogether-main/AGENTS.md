# CoPaw repository working agreement

## Product source of truth

- Read `BUILD_SPEC.md` before planning or changing product behavior.
- Read `PLANS.md` before beginning or closing a migration phase.
- Preserve the non-goals, legacy-data compatibility, and protected collaboration behavior in `BUILD_SPEC.md`.
- Refer to acceptance cases by ID in plans, tests, reviews, and handoff evidence.
- When repository behavior and recall conflict, the checked-out code, deployed-provider state, and current acceptance evidence win.

## Repository map

- Current reference app: `copaw/` and `copaw.xcodeproj` (SwiftUI; keep until Flutter parity is accepted).
- Flutter app: `copaw_flutter/` (created during Phase 1).
- Firestore contract and authorization: `firestore.rules`.
- Firestore Rules tests: `tests/firestore.rules.test.mjs`.
- Long-running product contract: `BUILD_SPEC.md`.
- Long-running execution checkpoints: `PLANS.md`.
- Demo documentation and local tooling: `docs/` and `scripts/`.

## Commands

Run commands from the repository root unless noted otherwise.

- Install Rules dependencies: `npm ci`.
- Test Firestore Rules: `npm run test:rules` (requires Java).
- Resolve Flutter dependencies: `cd copaw_flutter && flutter pub get`.
- Format Dart: `cd copaw_flutter && dart format --output=none --set-exit-if-changed lib test integration_test`.
- Analyze Dart: `cd copaw_flutter && flutter analyze`.
- Test Flutter: `cd copaw_flutter && flutter test`.
- Build iOS Simulator: `cd copaw_flutter && flutter build ios --simulator`.
- Build Android debug APK: `cd copaw_flutter && flutter build apk --debug`.

Only mark a command verified in `PLANS.md` after it has succeeded in the current worktree. A successful build is not evidence of real Firebase, sync, notification, or device acceptance.

## Architecture and change rules

- Keep UI code independent of Firebase. Use `models -> repository/service -> application state -> views`.
- Provide a Firebase implementation and a deterministic fake/in-memory implementation for domain and widget tests.
- Preserve Firestore transactions, monotonic `revision`, trusted server timestamps, member-scoped access, and snapshot listener cleanup.
- Use household timezone for occurrence identity and calendar behavior; do not silently fall back to device timezone for persisted schedules.
- Preserve historical name, medication, and task snapshots. Later profile edits must not rewrite past records.
- Safety-sensitive medication actions are server-confirmed. Never show administered or skipped as successful from optimistic/offline state.
- Keep medication responsibility separate from medication outcome. `claimed` is not `administered`, and `skipped` is not an ordinary completion.
- New schema must dual-read legacy documents until migration evidence proves old data is preserved.
- Do not delete or rewrite the SwiftUI reference app until Flutter acceptance cases AC-001 through AC-014 pass and the user approves retirement.
- Keep changes phase-scoped. Do not add RevenueCat, a paywall, AI diagnosis, marketplace, GPS, community, training content, or speculative infrastructure.

## Privacy and remote-action rules

- Never commit Firebase configuration files, API keys, credentials, populated environment files, device tokens, health notes, pet names, medication names/doses, local usernames, or absolute machine paths.
- Do not send pet health content, medication content, notes, report bodies, or image URLs to analytics or logs.
- Lock-screen notifications must avoid sensitive medication and health details by default.
- Remove unnecessary photo EXIF/location metadata before any future upload.
- Do not push, deploy Rules, migrate production data, upload builds, or publish anything without an exact outgoing-scope privacy/secret review and explicit user approval where personal material is involved.

## Verification responsibilities

- Implementer: makes the minimum phase-scoped change and deterministic tests.
- Data/security reviewer: independently checks schema, Rules, state transitions, migration, concurrency, and privacy.
- Acceptance runner: exercises the clean UI and real dependency/device flow without relying on implementer-created local state.
- A phase remains incomplete if real-provider or real-device evidence required by its acceptance cases is unavailable.

## Definition of done

- Every in-scope acceptance case has current evidence in `BUILD_SPEC.md` or an evidence artifact referenced from `PLANS.md`.
- Relevant Dart unit/widget/integration tests, Rules tests, analysis, formatting, and platform builds pass.
- Legacy fixtures load without dropped tasks, routines, activity, or household membership.
- The claimed collaboration flow is verified on two separate clients and then two physical iPhones.
- Medication concurrency, offline failure, stale actions, restart, reconnect, timezone, and permission cases are verified at the appropriate layer.
- The final diff and any outgoing Git history are reviewed for scope, secrets, personal information, machine paths, generated artifacts, and release blockers.
