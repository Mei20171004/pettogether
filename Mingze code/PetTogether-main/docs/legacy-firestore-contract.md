# Legacy Firestore contract for Flutter migration

Verified against `origin/main` baseline `61c685bf682867ed153e9d5df98e6db48074bf74` on 2026-08-12. This file describes existing persisted behavior; `BUILD_SPEC.md` remains authoritative where the old implementation is unsafe or incomplete.

## Existing paths

```text
households/{householdID}
households/{householdID}/members/{uid}
households/{householdID}/routines/{routineID}
households/{householdID}/tasks/{taskOccurrenceID}
inviteCodes/{inviteCode}
```

Activity is a view of completed task documents, not a separate collection. Pet photos are currently local-only files.

## Household and member

`households/{householdID}` stores `id`, `name`, `petName`, `inviteCode`, `timeZoneIdentifier`, `ownerID`, `createdAt`, and optional `updatedAt`. The document ID is authoritative over the stored `id`.

`members/{uid}` stores `id`, `displayName`, `inviteCode`, `joinedAt`, and optional `updatedAt`. Membership is represented only by document existence. The current Leave action clears the local active-household session and listeners; it does not delete membership.

Creating a household atomically creates the household, owner member, and invite. Joining creates a member or updates the returning member's own display name. Profile editing batches household name, legacy pet name, and current member name.

Compatibility decision: a missing or invalid household timezone is a visible `legacyNeedsTimezone` recovery condition. The Flutter app may keep already-persisted tasks readable, but it must not derive or save schedules using the device timezone until a household timezone is explicitly repaired.

## Routine

Canonical routine fields:

- `id`, `title`, `category`, `priority`
- `frequency`: `daily` or `selectedDays`
- `weekdays`: integers 1 through 7 where 1 is Sunday
- `hour`, `minute`, `startDate`, `timeZoneIdentifier`
- `createdByID`, `createdByName`, `isActive`, `createdAt`

Legacy defaults are `frequency = daily` and `weekdays = [1,2,3,4,5,6,7]`. Missing `priority`, timezone, or active state is malformed legacy data and must produce an observable diagnostic/recovery result rather than disappearing from the listener.

Routine templates are expanded locally. An occurrence ID is `<routineID>_YYYY-MM-DD` using the household timezone. An untouched occurrence is virtual. The first claim or assignment request materializes it transactionally with initial revision 1. A persisted occurrence wins over its virtual counterpart.

## Task

Canonical base fields:

- `id`, `title`, `category`, `dueTime`, `kind`, `priority`, `routineID`
- `status`, `createdByID`, `createdBy`, `createdAt`, `revision`

Assignment overlay:

- `assignmentRequestID`, `assignmentMode`
- `requestedByID`, `requestedByName`, `requestedToID`, `requestedToName`
- `assignmentRequestedAt`

Assignee and completion overlay:

- `assigneeID`, `assigneeName`, `claimedAt`
- `completedByID`, `completedBy`, `completedAt`

Canonical writers explicitly write nullable overlay keys as null. Compatibility defaults are:

- `pending` status decodes as `unclaimed`.
- Missing or unknown `kind` decodes as `oneOff`.
- Missing or unknown `priority` decodes as `normal`.
- Missing `createdAt` uses `dueTime`.
- Missing `revision` decodes as 0.
- Missing assignment mode is inferred as `open` when `requestedToID` is null and `direct` otherwise.

A partial request overlay is a malformed-data diagnostic, not silently “no request.” A legacy task that lacks fields required for a safe Rules-approved transition remains readable, but its action UI must require repair/backfill rather than claim success.

## Existing task state machine

```text
unclaimed, no request
  -> direct or open request
  -> self-claimed

unclaimed, direct request
  -> recipient accepts
  -> recipient declines
  -> requester cancels
  -> requester claims

unclaimed, open request
  -> any member claims
  -> requester cancels

claimed
  -> current assignee completes

completed
  -> terminal
```

Every mutation transaction-reads the current server document, validates actor/request/state, and writes `revision = current revision + 1`. Request, claim, and completion actions must use server-authored times. Flutter and Rules must both reject stale and unauthorized actions and then refresh the authoritative state.

## Invite code

`inviteCodes/{code}` stores `householdID`, `createdBy`, `createdAt`, and `active`. A signed-in user may get a single code but cannot list codes. Input is trimmed and upper-cased and must be a six-character code in the supported alphabet. Missing `active` is legacy-compatible as active; explicit false is inactive.

## Migration classification matrix

Every production document inspected by LT-1 must be assigned to exactly one
class. Classification is a dry-run result, not permission to write. The complete
source count must equal the sum of these mutually exclusive classes.

| Class | Criteria and examples | Allowed automated action | Required user behavior |
| --- | --- | --- | --- |
| `canonical/no-op` | Already satisfies the applicable schema and reference invariants; legacy omission is intentionally supported, such as an invite with missing `active`. | None. Never rewrite only to normalize optional fields. | Read and preserve exact historical snapshots. |
| `safe-additive` | A missing canonical document can be created from an unambiguous, immutable legacy source without changing the source. The only currently nominated example is `pets/legacy-primary` from a valid household `petName`, when that pet document does not exist. | Create the deterministic new document only after an approved backfill; use a precondition and record the new path/update time. | Continue dual-read; source fields remain intact. |
| `safe-patch` | A missing field has one provable value from authoritative fields in the same document or transaction, with no timezone, identity, state, or historical inference. No production patch is pre-approved by this contract. | Patch only fields and paths listed in an independently approved dry-run; preserve a protected before-image and use `updateTime` preconditions. | Continue reading the legacy shape throughout the compatibility window. |
| `manual/blocking` | The document is readable but a safe mutation would require a decision: missing/invalid household timezone, partial assignment overlay, actor represented only by a display name, ambiguous state/time/revision, random-ID Health v1 daily check-in that conflicts with a canonical day, or Health v1 water without a provable basis. | No automated write. Surface a repair/conflict state and stop the affected migration or mutation. | Keep history visible; ask an authorized household member or migration owner to resolve the exact ambiguity. |
| `malformed/quarantine` | Cannot be decoded safely, violates reference/type/authorization invariants, or points across households. | No normalization, deletion, or silent drop. Report a content-free diagnostic and isolate the path from automated writes. | Do not present it as successful care/health history; require independent data/security review. |

The migration must never infer:

- a timezone from the current device or assume the current household timezone
  was historically correct;
- a Firebase UID from a display name;
- assignment, claim, completion, medication outcome, or action times;
- a missing revision or terminal state for the purpose of a write;
- a Health v1 `recordedLocalDate`, `recordedTimeZoneIdentifier`, or
  `waterMeasurementBasis` unless the approved source contains evidence that
  proves the value without assumption.

Health v1 was introduced after the original Swift baseline recorded at the top
of this document. Its compatibility boundary is defined in
`docs/firestore-schema.md`: it stays member-readable and immutable, and is not
silently converted into Health v2 or included in v2 water totals.

## Minimum Dart compatibility tests

- Canonical and legacy codecs for household, member, routine, and all task states.
- Document ID wins over a conflicting stored `id`.
- Legacy status/defaults, missing nullable keys, partial request, unknown enum, wrong timestamp, and wrong number types.
- Canonical writer-to-codec round trip with explicit nullable keys.
- Daily/selected-day expansion, start-date boundary, non-device timezone, DST, occurrence ID, and persisted-over-virtual deduplication.
- Create/join/rejoin/restore/leave and listener cancellation across session changes.
- One-off creation and every task transition with success, invalid actor, stale request/revision, terminal state, concurrency, and offline failure.
- Legacy tasks remain visible; unsafe legacy transitions visibly require repair.

## Required Rules hardening before parity acceptance

- Require `assignmentRequestedAt`, `claimedAt`, and `completedAt` to equal `request.time` for their transitions.
- Cover immutable-field tampering, cross-household references, malformed weekdays, and symmetric list/get authorization.
- Define legacy-readable versus legacy-migratable boundaries explicitly.
- Prevent clients from fabricating routine occurrence identity or scheduled time before those occurrences are used as report denominators.
