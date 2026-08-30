# LT-5 task responsibility and handoff session contract

Status: local implementation checkpoint verified; clean Flutter two-client,
provider, staging, deployment, and physical-device evidence remain open and are
not authorized by this document.

## Product decision

CoPaw uses consented responsibility transfer. A member may release their own
responsibility. Reassignment moves from A to B only after B accepts. A takeover
request from B moves responsibility only after the current assignee A accepts.
No household member has unilateral takeover or forced-assignment authority.

The task source remains one of `unclaimed`, `claimed`, or `completed`. LT-5 does
not add a task status that retained clients cannot decode. A responsibility
proposal never means the requester is responsible and never means care occurred.

## Task responsibility authority

Pending proposals live in server-owned sidecar documents rather than the legacy
assignment overlay:

- `households/{householdID}/taskResponsibilityTransfers/{transferID}` stores the
  exact proposal, participants, source task/revision snapshot, status, trusted
  transition actors/times, and monotonically increasing revision.
- `households/{householdID}/taskResponsibilityState/{taskID}` is a
  member-readable, server-written pointer to the one pending proposal for that
  task. It is removed when the proposal becomes terminal.
- `households/{householdID}/taskResponsibilityReceipts/{receiptID}` is a
  server-only idempotency receipt. Its deterministic identity derives from UID
  and client mutation ID; it contains only fingerprints and non-sensitive source
  identifiers/results.

Every transfer document has every exact version 1 key below. Nullable terminal
fields are stored explicitly:

| Field | Contract |
| --- | --- |
| `schemaVersion`, `id`, `taskID` | `1`, document ID, and canonical task ID. |
| `kind` | `reassign` or `takeover`. |
| `status` | `pending`, `accepted`, `declined`, `cancelled`, or `superseded`. Terminal values never reopen. |
| `requestedByID/Name` | Reassign: current assignee A. Takeover: requesting member B. |
| `consentByID/Name` | Reassign: target B. Takeover: current assignee A. |
| `responsibilityFromID/Name` | Current assignee A at proposal time. |
| `responsibilityToID/Name` | Proposed new assignee B. |
| `taskRevisionAtProposal` | Exact claimed task revision used to create the proposal. |
| `createdAt` | Trusted proposal time. |
| `resolvedByID/Name`, `resolvedAt` | Null while pending; exact authenticated terminal actor/time otherwise. |
| `resultingTaskRevision` | New task revision for `accepted` or completion-driven `superseded`; null for decline/cancel. |
| `revision` | `1` while pending and exactly `2` after its single terminal transition. |

The exact version 1 active pointer keys are `schemaVersion`, `taskID`,
`transferID`, `taskRevisionAtProposal`, and trusted `createdAt`. Pointer task ID
and transfer proposal fields must agree. Creating a proposal creates both;
accept/decline/cancel/supersede changes the transfer, deletes the pointer,
mutates the task when applicable, writes the receipt, and appends the
deterministic event in one server transaction. A pending transfer without its
pointer, or a pointer to a non-pending/mismatched transfer, is malformed and
blocks mutation rather than being guessed or repaired.

All LT-5 mutations are authenticated callable transactions with production App
Check, required expected source/proposal revision, exact current membership,
server timestamps, deterministic receipts, and no optimistic success. While a
pending pointer exists, retained direct task writers are denied so they cannot
leave a dangling proposal. The current client completes through the same server
authority and atomically closes a pending proposal if completion wins the race.

### Transitions

| Action | Required actor and state | Result |
| --- | --- | --- |
| Release | Current assignee; claimed task; no pending proposal | Existing unclaimed task shape, assignee fields cleared, revision + 1 |
| Request reassign | Current assignee A; target member B; no pending proposal | Task remains claimed by A; pending A-to-B proposal |
| Accept reassign | B; matching pending proposal and revisions | Task becomes claimed by B; proposal accepted and pointer cleared |
| Request takeover | Non-assignee B; current assignee A; no pending proposal | Task remains claimed by A; pending B-asks-A proposal |
| Accept takeover | A; matching pending proposal and revisions | Task becomes claimed by B; proposal accepted and pointer cleared |
| Decline | Proposal's consent-giver | Task unchanged; proposal declined and pointer cleared |
| Cancel | Proposal requester | Task unchanged; proposal cancelled and pointer cleared |
| Complete | Current assignee; matching task revision | Task completed; a pending proposal, if any, is terminally superseded |

Rejected/stale mutations change no source, receipt result, or collaboration
event. Identical retries return the authoritative result. Reusing a mutation ID
with a different payload fails.

## Handoff template, versions, and sessions

`handoff/current` remains the editable household template. A session never
silently follows later template edits.

- `handoffVersions/{versionID}` is a server-created immutable copy of one exact
  template revision. It may contain the care instructions and phone fields and
  is readable only by current household members.
- `handoffSessions/{sessionID}` references one version, creator and recipient,
  a household-wide planned UTC start/end with household timezone snapshot,
  `offered | accepted | declined | cancelled | closed`, trusted actor/time
  fields, and revision.
- `handoff/sessionState` is a member-readable, server-written pointer that
  permits at most one offered or accepted session per household.
- `handoffSessionReceipts/{receiptID}` contains no template text or phone data.

The immutable version document ID is `v` followed by the six-digit,
zero-padded positive template revision, for example `v000012`. Its exact version
1 keys are `schemaVersion`, `id`, `sourceHandoffRevision`, all five
`handoff/current` care/emergency fields, `updatedByID`, `updatedByName`,
`updatedAt`, and trusted `materializedAt`. An offer transaction reads
`handoff/current`, requires the supplied revision to match, and creates this
version or reuses an existing byte-for-byte equivalent version. A mismatch or
conflicting existing version aborts; it never substitutes the latest template.
Equivalence compares the source revision and source-derived template/updater
fields; an existing version keeps its original `materializedAt`.

Every session has every exact version 1 key below. Nullable transition fields
are explicit:

| Field | Contract |
| --- | --- |
| `schemaVersion`, `id`, `versionID`, `handoffRevisionSnapshot` | `1`, document ID, immutable version reference, and its source revision. |
| `creatorID/Name`, `recipientID/Name` | Distinct current member snapshots bound when offered. |
| `timeZoneIdentifierSnapshot` | Validated household IANA timezone at offer. |
| `plannedStartAt`, `plannedEndAt` | UTC Firestore instants; start is before end, end is future at offer, and duration is at most 30 days. |
| `status` | `offered`, `accepted`, `declined`, `cancelled`, or `closed`. Terminal values never reopen. |
| `offeredAt` | Trusted creation time. |
| `acceptedByID/Name`, `acceptedAt` | Recipient snapshot/time only for accepted or later closed. |
| `declinedByID/Name`, `declinedAt` | Recipient snapshot/time only for declined. |
| `cancelledByID/Name`, `cancelledAt` | Creator, or owner recovery actor, only for cancelled. |
| `closedByID/Name`, `closedAt` | Participant or owner recovery actor only for closed. |
| `resolutionReason` | Null normally; `ownerRecovery` only when the owner cancels an offered or closes an accepted stuck session. |
| `revision` | `1` offered; `2` after accept or an offered terminal action; `3` when an accepted session closes. |

The exact active pointer keys are `schemaVersion`, `sessionID`, `sessionStatus`,
`plannedEndAt`, and trusted `updatedAt`. Its status is only `offered` or
`accepted` and must match the source session. Offer creates session/version,
pointer, receipt, and event atomically. Accept updates session and pointer in one
transaction and is rejected at or after `plannedEndAt`. Decline/cancel removes
an offered pointer; close removes an accepted pointer. To prevent a lost creator
from blocking the household forever, the owner may cancel an offered session or
close an accepted session with `resolutionReason = ownerRecovery`; content is
never rewritten. A new offer never treats an expired pointer as absent without
an explicit participant/owner terminal transition.

Only another current member can receive an offer. Only the recipient accepts or
declines. Only the creator cancels before acceptance, except the owner may
cancel an offered session with `ownerRecovery`. Either participant closes an
accepted session, and the owner may close a stuck accepted session with
`ownerRecovery`. Recovery cannot rewrite version/session content. Terminal
sessions never reopen. Closing does not complete tasks, administer medication,
or infer medical correctness; close-out counts are read from authoritative
sources.

Accepting a household-wide session acknowledges only the pinned instructions
and planned coverage window. It never overrides or assigns any task assignee,
medication responsible member, outcome actor, owner role, or LT-6 recipient.
Task and medication responsibility can change only through their own
authoritative state machines. Close-out uses the half-open household coverage
window `[plannedStartAt, plannedEndAt)` and derives planned, unresolved, and
completed source counts at read time; those counts are not stored as session
facts.

## Collaboration projection and privacy

Task responsibility and handoff session facts use a versioned exact event shape.
Task events identify responsibility-from and responsibility-to separately from
the authenticated transition actor. Handoff events contain only session ID,
participants, status, revision, and trusted time. Event IDs are deterministic
hashes of source path, source revision, and action.

Handoff instructions, phone numbers, health content, medication/dose content,
tokens, image URLs, and report bodies never enter collaboration events,
receipts, push payloads, inbox documents, analytics, or logs. Source tasks,
transfers, handoff versions, and sessions remain authoritative; the ledger is an
eventually consistent convenience view and never a report denominator.

## Membership exit boundary

The UI must distinguish:

- disconnect this device: clears only local session state and does not claim to
  revoke access; before clearing, it disables the current installation's token
  for that household and preserves the local session if disabling fails;
- leave household: server-revokes the member document and disables that member's
  household notification installations after confirming no active assigned
  task, pending transfer, or offered/accepted handoff obligation.

True leave uses a server-only `membershipRevocations/{uid}` progress pointer and
an immutable per-mutation receipt. The pointer first enters `draining`, blocks
rejoin and new notification delivery claims, and waits for trusted short leases
from already-started sends. It then deletes membership and disables matching
installations in bounded, cursor-backed batches. Completion atomically writes
the receipt result and removes the temporary pointer, so the same mutation can
return its result, a crashed call can resume with a new mutation, and a later
legitimate rejoin starts with no stale leave authority. No token value or
handoff content is stored in the pointer, lease, or receipt.

The owner cannot leave until a separately implemented ownership transfer or
household deletion flow exists. A rejected leave explains the blocking source
without exposing sensitive content. Historical name snapshots are retained.

## Verification and release boundary

LT5-AC01 through LT5-AC12 in `BUILD_SPEC.md` are the closure contract. Local
completion requires Functions, Rules, repository, codec/legacy, widget,
privacy, race/retry, and two-client Emulator evidence plus independent review.
It does not prove production App Check, retained-client rollout, recoverable
accounts, remote Firebase, or two physical iPhones.
