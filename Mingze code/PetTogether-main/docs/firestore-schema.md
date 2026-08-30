# CoPaw Firestore schema contract

Status: LT-1/LT-2 executable local contract and LT-3 through LT-5 local
implementation checkpoints are verified. LT-6 additions below remain a planned
exact contract; migration, provider, staging, production, and physical-device
evidence remain open.

This document defines the persisted boundary that the Flutter app, Cloud
Functions, Firestore Rules, migration fixtures, and future staging project must
share. `BUILD_SPEC.md` owns observable product behavior. `firestore.rules`,
Functions validation, Dart codecs, and contract tests remain executable sources
of truth. Health v2 is the local canonical writer contract. Health v1 remains a
readable, immutable compatibility input until production reconciliation and
explicit retirement approval satisfy the evidence gates below.

The legacy household, member, routine, and task shapes are recorded separately
in `docs/legacy-firestore-contract.md`. New readers must continue to decode those
documents until a production reconciliation proves that the compatibility path
can be retired.

## Global invariants

- Firebase Auth UID is the member identity. Membership is the existence of
  `households/{householdID}/members/{uid}`.
- A stored `id` is a snapshot; the Firestore document ID is authoritative.
- Household-local dates and occurrence IDs use the household's validated IANA
  timezone. A client must not silently substitute its device timezone.
- Security-sensitive actor names are historical snapshots bound to the current
  member document when the write is accepted.
- `createdAt`, transition times, and terminal outcome times are server-authored.
- Mutable state machines advance `revision` monotonically and reject stale
  expected revisions.
- Medication responsibility is independent from medication outcome. Only a
  confirmed `administered` or `skipped` outcome is terminal.
- Historical pet, caregiver, medicine, dose, and instruction snapshots do not
  change after profile or schedule edits.
- Lock-screen payloads, logs, analytics, mutation receipts, and delivery IDs do
  not contain pet, medication, dose, health, phone, or free-text content.
- Schema additions are dual-read first. Destructive rewrites and production
  migrations require a backup, dry-run counts, reconciliation, and rollback.

## Path inventory

`?` denotes nullable or legacy-optional data. Arrays use `[]`.

| Path | Canonical fields | Write authority and lifecycle |
| --- | --- | --- |
| `households/{householdID}` | `id`, `name`, `petName`, `inviteCode`, `timeZoneIdentifier`, `ownerID`, `createdAt`, `updatedAt?` | Authenticated create is atomically bound to the owner member and invite. Members may edit display fields only. `petName` remains for legacy-primary compatibility. |
| `households/{householdID}/members/{uid}` | `id`, `displayName`, `inviteCode`, `joinedAt`, `updatedAt?` | A user creates or updates only their own membership; members may list the household roster. Creation is denied while a server revocation pointer exists. |
| `inviteCodes/{inviteCode}` | `householdID`, `createdBy`, `createdAt`, `active?` | Created with a household. Signed-in users may get one supplied code but may not list codes. Missing `active` is legacy-compatible as active. |
| `households/{householdID}/pets/{petID}` | `id`, `name`, `species?`, `isArchived`, `createdAt`, `updatedAt` | Members create/rename. Archive is callable-only and blocked by active medication plans. `legacy-primary` may be synthesized from `household.petName`. |
| `households/{householdID}/routines/{routineID}` | `id`, `title`, `category`, `priority`, `hour`, `minute`, `frequency`, `weekdays[]`, `startDate`, `timeZoneIdentifier`, `createdByID`, `createdByName`, `petID`, `petName`, `isActive`, `createdAt` | Members create canonical schedules. The callable validates and materializes a household-local occurrence. |
| `households/{householdID}/tasks/{taskID}` | Base, assignment, assignee, completion overlays, pet snapshot, `revision` | Members create one-off tasks. Rules/callable transactions enforce actor, current state, trusted time, immutable fields, and `revision + 1`. Legacy missing overlays remain readable. |
| `households/{householdID}/taskResponsibilityTransfers/{transferID}` | LT-5 exact proposal, kind, task/revision, requester/consent-giver/new-assignee snapshots, status, trusted transition times, `revision` | Implemented LT-5 member-readable/server-only consent record. It never changes responsibility before acceptance. |
| `households/{householdID}/taskResponsibilityState/{taskID}` | Active `transferID` and trusted creation metadata | Implemented LT-5 member-readable/server-written singleton pointer. Its existence blocks retained direct task mutation until a trusted transition resolves the proposal. |
| `households/{householdID}/taskResponsibilityReceipts/{receiptID}` | UID/action/fingerprint and non-sensitive authoritative result | Implemented LT-5 server-only idempotency receipt; no task title, pet name, handoff, health, medication, or free text. |
| `households/{householdID}/medications/{medicationID}` | `schemaVersion`, `id`, `petID`, `displayName`, `purpose?`, `possibleSideEffects?`, `isActive`, `currentScheduleVersion`, `currentScheduleVersionID`, `revision`, creator/updater snapshots and times | Callable-only authority. Replacement and stop require expected medication revision/current version. |
| `.../medications/{medicationID}/scheduleVersions/{versionID}` | `schemaVersion`, `id`, `medicationID`, `version`, pet/medicine snapshots, `weekdays[]`, `slots[]`, `timeZoneIdentifier`, `dstPolicy`, effective date interval, creator/closer snapshots, `revision` | Immutable version body; a replacement closes the prior version and creates the next one transactionally. End date is exclusive. |
| `households/{householdID}/medicationOccurrences/{occurrenceID}` | Schedule, pet, medicine, dose, instruction snapshots; responsibility overlay; outcome overlay; `materializedAt`, `revision` | Callable-only. ID is `{medicationID}_{scheduleVersionID}_{YYYY-MM-DD}_{slotID}`. At most one terminal outcome wins. |
| `households/{householdID}/medicationMutationReceipts/{receiptID}` | `uid`, request `fingerprint`, `action`, non-sensitive `result`, `createdAt` | Callable-only idempotency receipt. ID is a hash of UID and client mutation ID. It must not contain medical payload text. |
| `households/{householdID}/healthRecords/{recordID}` | Health v2: `schemaVersion = 2`, pet snapshot, `type`, `recordedAt`, `recordedLocalDate`, `recordedTimeZoneIdentifier`, `detail?`, typed measurement fields, `waterMeasurementBasis?`, creator snapshot, `createdAt` | Member-only read. All new writes are callable/server-only and immutable; Health v1 remains read-only during the compatibility window. Daily check-ins are unique per pet/local date. |
| `households/{householdID}/healthMutationReceipts/{receiptID}` | `schemaVersion`, `uid`, request `fingerprint`, `action`, non-sensitive `result`, `createdAt` | Callable-only idempotency receipt for ordinary and daily health writes. ID is a hash of UID and client mutation ID. Clients cannot read or write it, and it must not contain health answers, notes, pet names, or water values. |
| `households/{householdID}/handoff/current` | `schemaVersion`, care and emergency fields, `revision`, updater snapshot and time | Member-only singleton. LT-2 adds required `expectedRevision` compare-and-set behavior before the larger session model. |
| `households/{householdID}/handoffVersions/{versionID}` | Immutable exact template revision and member-visible care/emergency fields | Implemented LT-5 server-created snapshot referenced by sessions. Sensitive content stays here and never enters ledger/inbox/receipts. |
| `households/{householdID}/handoffSessions/{sessionID}` | Version reference, creator/recipient, planned window/timezone snapshot, status, trusted transition actors/times, `revision` | Implemented LT-5 member-readable/server-write state machine. At most one offered/accepted session is active. |
| `households/{householdID}/handoff/sessionState` | Active session pointer and trusted update time | Implemented LT-5 member-readable/server-written singleton control record. |
| `households/{householdID}/handoffSessionReceipts/{receiptID}` | UID/action/fingerprint and non-sensitive authoritative result | Implemented LT-5 server-only idempotency receipt; never stores template content or phone fields. |
| `households/{householdID}/membershipMutationReceipts/{receiptID}` | UID/action/fingerprint, `revoking | complete`, non-sensitive authoritative result, trusted times | LT-5 server-only true-leave receipt. It preserves idempotent completion after the temporary revocation pointer is removed. |
| `households/{householdID}/membershipRevocations/{uid}` | `draining | revokingTokens`, initiating mutation/fingerprint, receipt ID, token cursor/count, trusted times | Temporary LT-5 server-only revocation pointer. It blocks rejoin and new notification claims, persists batch progress, and is deleted atomically when the receipt completes. |
| `.../membershipRevocations/{uid}/notificationClaims/{deliveryID}` | Delivery/recipient/installation references, trusted lease and creation time | Temporary server-only delivery lease. Leave drains or expires these claims before deleting membership; no token value or notification body is stored. |
| `households/{householdID}/collaborationEvents/{eventID}` | Append-only task transition fact with deterministic source revision/action identity plus actor, counterparty, pet, and task snapshots | Member-only read and server-only create. The source task remains authoritative; the ledger is eventually consistent, may be incomplete during retained-writer compatibility, and is never a report denominator. See `docs/collaboration-event-ledger.md`. |
| `households/{householdID}/members/{memberID}/updateState/collaboration` | `schemaVersion = 1`, trusted event-order cursor `occurredAt` + `eventID`, server `updatedAt` | Private to that member. The client may create or monotonically advance its own cursor only to an existing collaboration event whose trusted `occurredAt` matches. Listing, deletion, another member's cursor, fabricated events, and backwards movement are denied. |
| `users/{uid}/notificationTokens/{installationHash}` | `token`, `householdID`, `platform`, `enabled`, `createdAt`, `updatedAt` | Private to that UID. Document identity is a stable installation hash; token rotation updates the same installation. |
| `users/{uid}/householdNotificationPreferences/{householdID}` | Exact LT-6 v1 membership epoch, category/push/backup/quiet/summary policy, household timezone snapshot, monotonic revision, and trusted times | Planned callable-written/current-member-private policy. Missing uses conservative defaults; malformed/stale timezone blocks only that member's provider routing; leave/rejoin never restores old consent. |
| `users/{uid}/notificationPreferenceMutationReceipts/{receiptID}` | Exact LT-6 v1 UID/household/membership epoch, action, keyed fingerprint, non-sensitive revision result, and trusted time | Planned server-only callable idempotency receipt; it contains no choices, member list, token, or source. |
| `users/{uid}/notificationInbox/{intentID}` | Exact LT-6 v1 non-sensitive recipient membership epoch, category/level/reason, opaque source identity/revision, active/cancelled state, availability/expiry/dispatch/coalescing, and trusted times | Planned private server-written intent. It is not audit/source truth and contains no names, medical/care/handoff content, token, image, or report body. |
| `users/{uid}/notificationInboxState/{householdID}` | Exact LT-6 v1 membership epoch and monotonic `createdAt` + `intentID` read cursor with trusted update time | Planned private self-write cursor. Unknown/error/pending remains conservatively unread; leave/rejoin cannot reuse the prior epoch. |
| `users/{uid}/notificationDigests/{digestID}` | Exact LT-6 v1 membership epoch, burst/daily window, preference revision, coalescing identity, collecting/ready/cancelled/blocked state, and trusted times | Planned server-only coordination source. It queries and re-validates original authoritative sources and never stores names, content, tokens, or source lists. |
| `users/{uid}/notificationDeliveryManifests/{intentID}` | Exact LT-6 v1 membership epoch, frozen sorted selected installation IDs, materialization cursor/status/count, and trusted times | Planned server-only one-time selection. Later duplicate/installation drift cannot create a second delivery for an old intent. |
| `users/{uid}/notificationDeliveries/{deliveryID}` | Exact LT-6 v2 intent/recipient epoch/stable installation references, status, bounded attempts, lease, safe error, and trusted result times | Planned private-read/server-write provider evidence. Token-derived identity is forbidden; `providerAccepted` is not delivered/read/completed and ambiguity is terminal without automatic retry. |
| `households/{householdID}/notificationEndpointBindings/{bindingID}` | Exact LT-6 v1 intent/recipient epoch, immutable winning delivery, attempt-stream state/lease/expiry, and trusted times; ID is a server-secret HMAC of intent/recipient/current token | Planned server-only dispatch-time endpoint serialization. It stores no token or unkeyed token hash and prevents post-manifest token convergence from sending twice. |
| `households/{householdID}/medicationReminderDeliveries/{deliveryID}` | Legacy Phase-5 occurrence/level/token-fingerprint delivery record | Retained server-only compatibility data. LT-6 never writes it. |
| `systemConfig/notificationDispatch` | Legacy Phase-5 `enabled`, project/audit identity, and trusted update time | Retained disabled gate. The broad legacy scheduled export must be removed before any LT-6 activation. |
| `systemConfig/notificationIntentGenerationV2` | Exact v1 `enabled`, `projectID`, `cutoverAt`, `updatedBy`, `updatedAt` | Planned server/admin-only generation gate. Missing/malformed/disabled/project mismatch/read failure is off and old windows are never backfilled. |
| `systemConfig/notificationDispatchV2` | Exact v1 `enabled`, `projectID`, `cutoverAt`, `updatedBy`, `updatedAt` | Planned independent server/admin-only provider gate, re-read immediately before send. This local task never enables it. |

## Task overlays

Task base fields are `id`, `title`, `category`, `dueTime`, `kind`, `priority`,
`routineID?`, `petID?`, `petName?`, `status`, `createdByID`, `createdBy`,
`createdAt`, and `revision`.

Assignment fields are `assignmentRequestID?`, `assignmentMode?`,
`requestedByID?`, `requestedByName?`, `requestedToID?`, `requestedToName?`, and
`assignmentRequestedAt?`. Assignee fields are `assigneeID?`, `assigneeName?`,
and `claimedAt?`. Completion fields are `completedByID?`, `completedBy?`, and
`completedAt?`. Canonical writers include every nullable overlay explicitly;
legacy readers tolerate missing overlays but do not mutate unsafe shapes.

LT-5 responsibility proposals do not reuse the assignment overlay because that
overlay is valid only while a task is unclaimed. Claimed-task reassign/takeover
consent lives in server-owned sidecars described in
`docs/task-responsibility-handoff-sessions.md`, preserving the three canonical
task status values and retained-reader compatibility.

## Medication schedule and occurrence fields

Each schedule slot contains `slotID` (`HHmm`), `hour`, `minute`, `doseText`, and
nullable `instructions`. Apple weekday integers remain `1 = Sunday` through
`7 = Saturday`. `dstPolicy = reject`: nonexistent or ambiguous local dose times
are rejected instead of silently shifted.

Occurrence responsibility values are `unclaimed` or `claimed` with nullable
`responsibleByID`, `responsibleByName`, and `claimedAt`. Outcome values are
`unresolved`, `administered`, or `skipped` with nullable actor/time and skip
reason fields. Responsibility never proves administration.

## Health v2 canonical contract

Supported types remain `dailyCheckIn`, `weight`, `waterIntake`, `appetite`,
`energy`, `mood`, `stoolObservation`, `symptom`, `visit`, `vaccine`, and `note`.
Every new Health writer uses `schemaVersion = 2`; Health v1 is a compatibility
input, not an allowed new-write shape.

### Time and daily identity

- `recordedAt` is the observation instant.
- `recordedTimeZoneIdentifier` is the validated household IANA timezone used at
  creation. It is an immutable historical snapshot and never comes from the
  device timezone.
- `recordedLocalDate` is the `YYYY-MM-DD` calendar date obtained by converting
  `recordedAt` into `recordedTimeZoneIdentifier`. A trusted server path verifies
  this relationship; clients may not supply an inconsistent date/timezone pair.
- The canonical daily-check-in ID is the lowercase SHA-256 digest of
  `{petID}|{recordedLocalDate}`. A transaction/callable creates it once, returns
  the existing authoritative record for an idempotent retry, and rejects a
  different payload for the same pet/date. A random client document ID is not
  sufficient evidence of daily uniqueness.
- Later household-timezone changes do not rewrite the recorded date or timezone
  snapshot. Reports group v2 records by `recordedLocalDate` rather than the
  current device or household timezone.

### Typed observations

- `weightKilograms` is a positive observation attached only to a weight record.
- A daily check-in stores qualitative change-from-usual values for water,
  appetite, urination, stool, energy, and mood plus optional measured water and
  notes. These values describe a caregiver observation; they are not universal
  normal ranges.
- Missing fields stay missing. Reports and AI must not infer normality, missing
  quantities, diagnoses, risk, treatment, or dosage.

### Water measurement basis

When `waterMilliliters` is present in v2, `waterMeasurementBasis` is required:

| Value | Allowed source | Meaning | Report treatment |
| --- | --- | --- | --- |
| `singleIntake` | `waterIntake` | One discrete observed intake. It is not a day-to-date or whole-day total. | Sum v2 `singleIntake` records for a pet/date only when no overlapping day-to-date or full-day measurement is selected. |
| `localDayToDate` | `dailyCheckIn` | The caregiver's observed total from the start of `recordedLocalDate` through `recordedAt`; it does not claim to cover the rest of that day. | Display as “through check-in time”; do not add same-day `singleIntake` values because they may already be included. |
| `fullLocalDay` | A future explicit finalized-day source, not the initial daily-check-in writer | A reviewed total covering the complete household-local calendar day. | Use as the day's total and do not add other same-day water measurements. |
| `legacyUnknown` | Reader-derived classification for Health v1 only; never persisted by a v2 writer | The legacy value has no provable interval/basis. | Keep the exact source visible but exclude it from aggregate totals. |

If `waterMilliliters` is null, `waterMeasurementBasis` must be null. Other health
types cannot carry either field. The initial v2 ordinary writer persists only
`singleIntake`; the canonical daily callable must persist `localDayToDate` when
it stores water. `fullLocalDay` is reserved until an explicit finalized-day writer
and acceptance contract exist. A v1 record has no trustworthy basis and is
decoded as `legacyUnknown`: it remains visible as the exact observation but is
excluded from v2 aggregation. The UI/report must label excluded, partial-day,
or mixed-basis values rather than silently presenting a misleading total.

## Health v1 compatibility window

The last accepted baseline wrote v1 records with random IDs and no
`recordedLocalDate`, `recordedTimeZoneIdentifier`, or water basis. During the
reader-first compatibility window:

1. Readers decode v1 and v2 and preserve every valid v1 source record in the
   timeline.
2. After the v2 writer is activated, Rules reject new client v1 creates; v1
   records remain immutable and member-readable.
3. v1 daily check-ins do not participate in the v2 deterministic identity. The
   v2 callable blocks a same-pet v1 daily whose recorded instant falls in the
   requested current household-local day. Promotion inventory must separately
   block households whose historical timezone changes make a v1 day ambiguous;
   neither path hides, rewrites, or guesses the legacy record.
4. No migration derives a timezone from the device, assumes that the current
   household timezone was historically correct, or guesses a water basis.
5. Retirement is evidence-based, not date-based: retain the v1 reader until
   production counts and reports reconcile, all retained clients have stopped
   writing v1, rollback has been exercised, and the product owner explicitly
   approves closing the compatibility window. Closing it does not authorize
   deleting historical v1 documents.

## Index contract

`firestore.indexes.json` is a required versioned artifact, but the LT-1 baseline
is intentionally an empty composite-index manifest because no repository-owned
composite has yet been verified against an independent staging project. Existing
queries currently rely on Firestore automatic single-field indexes.

An empty local manifest is not evidence that a deployed project has no Console-
managed indexes and must never be used to delete them. Before any index deploy,
export/inventory the target project's existing indexes, map every live query,
review the CLI plan, and obtain explicit authorization for any deletion. A new
compound query must add the minimal index plus Emulator/staging query evidence
in the same phase.

## Compatibility and migration policy

1. Decode legacy household/member/routine/task fixtures and current v1 fixtures
   before any writer or Rules change.
2. New writers emit canonical fields; readers accept documented legacy omissions.
3. Rules must explicitly test the exact last-shipped payload, not only helper
   payloads that already contain new nullable keys.
4. Additive fields roll out reader first, then Rules, then writer. A breaking
   change requires a new schema version or a parallel path and dual-read.
5. Before a production migration: export/backup, dry-run decode, record counts
   by path/type/version, duplicate/dangling-reference report, and rollback test.
6. After migration: compare before/after counts and canonical IDs, sample source
   snapshots, keep old readers through the observation window, and never delete
   the Swift reference or legacy fields without product-owner approval.

## Environment promotion

The authoritative operational procedure is
`docs/FIREBASE_PROMOTION_MIGRATION.md`. In short, Emulator fixtures validate the
tooling, independent staging replays synthetic legacy/canonical cases, and
production defaults to compatibility deployment with zero document rewrites.
Production read, deploy, data-write, and notification-activation actions each
require a separate authorization gate.

No local commit authorizes Firebase project creation, deployment, migration,
push notification credentials, production reads/writes, Git push, or release.
