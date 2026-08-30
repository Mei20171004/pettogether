# CoPaw collaboration event ledger contract

Status: LT-4 and LT-5 local implementation checkpoints complete;
retained-writer, clean two-client, provider, staging, and deployment evidence
remain open. This contract does not authorize deployment.

## Purpose and authority

`households/{householdID}/collaborationEvents/{eventID}` is an append-only,
member-readable history of accepted household task and handoff collaboration
transitions. Only trusted server code creates events. Clients cannot create,
update, or delete them.

The authoritative source document and its state machine remain truth. The
ledger is eventually consistent and may be incomplete while retained clients
can still write the legacy task shape. It must never be used as a care,
medication, or report denominator and must not turn a request, claim,
responsibility, or handoff fact into evidence that care occurred.

## Event identity and replay

`eventID` is the lowercase SHA-256 digest of the literal string
`tasks/{taskID}|{sourceRevision}|{action}`. A trigger retry therefore addresses
the same document. The server creates the document once; an identical replay is
a no-op and a conflicting replay fails without overwriting history. A rejected
task mutation advances no revision and creates no event.

## Version 1 task event shape

Every document contains every key below. Nullable values are explicit.

| Field | Contract |
| --- | --- |
| `schemaVersion` | Integer `1`. |
| `sourceType` | `task`. |
| `sourceID` | Task document ID snapshot. |
| `sourceRevision` | Accepted task revision that produced the event. |
| `action` | `taskCreated`, `taskRequested`, `taskClaimed`, `taskAccepted`, `taskDeclined`, `taskCancelled`, or `taskCompleted`. LT-5 facts never use the v1 shape. |
| `actorID`, `actorName` | Member identity and display-name snapshot validated when the task transition is accepted. |
| `targetMemberID`, `targetMemberName` | Nullable counterparty snapshot. Both are null or both are present. |
| `requestID`, `assignmentMode` | Nullable assignment-request snapshots. |
| `petID`, `petName` | Immutable pet snapshots copied from the accepted task. |
| `taskTitle`, `taskCategory`, `taskPriority`, `taskDueTime` | Task snapshots copied from the accepted task, except medication-category titles are replaced with the non-sensitive `Medication care` label. |
| `stateAfter` | `unclaimed`, `claimed`, or `completed`. |
| `occurredAt` | Trusted task transition timestamp. |
| `recordedAt` | Server timestamp when the trigger appended the event. |

No health note, medication name/dose, handoff free text, phone number, device
token, notification payload, or analytics identifier belongs in this ledger.

## Version 2 responsibility and handoff event shape

LT-5 uses an exact version 2 union. Every v2 document contains every key below;
fields not allowed for that source/action are explicit nulls:

| Field | Contract |
| --- | --- |
| `schemaVersion` | Integer `2`. |
| `sourceType` | `taskResponsibilityTransfer`, `task`, or `handoffSession`. |
| `sourceID`, `sourceRevision` | Authoritative source document ID and accepted revision. |
| `action` | `taskReleased`, `taskReassignRequested`, `taskTakeoverRequested`, `taskReassigned`, `taskTakenOver`, `taskTransferDeclined`, `taskTransferCancelled`, `taskTransferSuperseded`, `handoffOffered`, `handoffAccepted`, `handoffDeclined`, `handoffCancelled`, or `handoffClosed`. |
| `actorID`, `actorName` | Authenticated transition actor snapshot. Always non-null. |
| `responsibilityFromID/Name`, `responsibilityToID/Name` | Task responsibility roles; both pairs are non-null for every transfer-sourced fact, only `from` is non-null for release, and both are null for handoff. |
| `handoffCreatorID/Name`, `handoffRecipientID/Name` | Session participant snapshots; both pairs are null for task responsibility. |
| `requestID` | Transfer ID for every responsibility-transfer lifecycle fact; null for release and all handoff facts. |
| `petID`, `petName`, `taskTitle`, `taskCategory`, `taskPriority`, `taskDueTime`, `stateAfter` | Task snapshots for task responsibility facts; all null for handoff. Medication-category task title is redacted to `Medication care`. |
| `handoffStatus` | Resulting session status for handoff facts; null for task facts. |
| `occurredAt`, `recordedAt` | Trusted source transition time and server event-write time. |

Action semantics are exact:

- `taskReleased`: source is `tasks/{taskID}` at the new task revision; actor and
  responsibility-from are the releasing assignee; responsibility-to and request
  are null; `stateAfter = unclaimed`.
- `taskReassignRequested` and `taskTakeoverRequested`: source is the new transfer
  at revision 1; actor is the requester, from/to are the unchanged current and
  proposed assignees, request ID is the transfer ID, and `stateAfter = claimed`.
- `taskReassigned`: source is
  `taskResponsibilityTransfers/{transferID}` at terminal revision; actor is the
  new assignee B who accepted; from is A, to is B, request ID is transfer ID,
  and `stateAfter = claimed`.
- `taskTakenOver`: source is the terminal transfer; actor is current assignee A
  who approved B's request; from is A, to is B, request ID is transfer ID, and
  `stateAfter = claimed`.
- `taskTransferDeclined` and `taskTransferCancelled`: source is the terminal
  transfer at revision 2; actor is the authorized resolver, responsibility stays
  with from, and `stateAfter = claimed`.
- `taskTransferSuperseded`: source is the terminal transfer at revision 2; actor
  is the assignee whose confirmed completion won the race and
  `stateAfter = completed`.
- Handoff actor is the member who offered/accepted/declined/cancelled/closed.
  Creator and recipient remain separately named, so owner recovery cannot be
  mistaken for either participant.

Event identity is the lowercase SHA-256 digest of the literal
`{sourcePath}|{sourceRevision}|{action}`. Source paths are `tasks/{taskID}` for
release, `taskResponsibilityTransfers/{transferID}` for proposal/terminal
responsibility facts, and `handoffSessions/{sessionID}` for handoff lifecycle. Source
transition, receipt, and v2 event are written in the same server transaction;
rejected/stale actions write zero events and identical retry addresses the same
event.

When completion supersedes a pending transfer, the accepted task update still
produces the existing v1 `taskCompleted` fact and the same server transaction
also writes the v2 `taskTransferSuperseded` fact. They describe different
authoritative source revisions and neither is deduplicated into the other.

v1 and v2 share the trusted `occurredAt desc`, then event ID `desc` ordering and
the same private read cursor. The LT-5 reader dual-decodes both exact shapes. A
retained LT-4 reader may count/drop v2 as incomplete but must not crash or infer
that no transition occurred. Reader-first and minimum-version evidence are
required before any v2 writer is promoted.

## Ordering, pagination, and incomplete history

Readers order by `occurredAt desc`, then document ID `desc` as the stable tie
break. Pages are bounded to 50 events and continue after the pair
`(occurredAt, eventID)`. Repository snapshots expose cache state, malformed
document counts, and `isPotentiallyIncomplete = true` during the retained-client
compatibility window. Legacy task/activity reads remain unchanged; no actor or
timestamp is invented for a legacy transition that did not produce an event.

Recent snapshots and older pages carry an opaque continuation token derived
from the final raw stored document, not the final safely decoded event. Firebase
keeps the raw document snapshot and continues with `startAfterDocument`; the UI
only passes the token back and never sees a Firebase type or reconstructs a
cursor from event fields. A malformed event, including one whose `occurredAt`
has the wrong stored type, is dropped and counted without truncating access to
older pages. Page results also preserve Firestore cache metadata.

Each member's private read position is stored at
`households/{householdID}/members/{memberID}/updateState/collaboration` as the
exact version 1 shape `schemaVersion`, `occurredAt`, `eventID`, and `updatedAt`.
This read cursor is distinct from the opaque pagination token and uses the same
event ordering pair. Rules require the referenced event
and matching trusted timestamp, bind reads and writes to that member, use a
server write time, and permit only an idempotent retry or forward movement.
Other members cannot inspect the cursor, and clients cannot list or delete read
state documents.

## Writer rollout boundary

The current Flutter writer adds a Rules-validated collaboration marker to each
task transition. A Firestore server trigger derives the immutable event from
that accepted task revision. Older retained writers remain readable and may
continue to use the legacy marker-free task shape, so their transitions do not
produce ledger events. Closing that gap requires the normal reader-first,
minimum-version, staging, and provider evidence gates; this local phase must not
claim a complete historical ledger.
