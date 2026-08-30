# LT-6 reminder routing, inbox, and interaction contract

Status: exact local contract independently unlocked for bounded local
implementation; implementation in progress. Provider dispatch remains disabled.
This document does not authorize
APNs/FCM configuration, deployment, token collection, scheduler activation, or
physical-device delivery.

## Truth and terminology

Notification state has four independent layers: OS permission on this
installation, the member's server-confirmed CoPaw preferences, this
installation's registration readiness, and provider evidence for a particular
attempt. No layer implies another. `providerAccepted` means only that the
provider accepted an attempt; it does not prove device display, reading,
acknowledgement, care completion, medication outcome, or handoff acceptance.

An inbox item is a private attention intent, not an audit event or source of
truth. Authoritative task, medication, handoff, membership, preference, and
installation documents are re-read before generation, provider claim, and route
resolution. The collaboration ledger, inbox, Activity, online state, and AI
output are never routing authority.

## Exact preference contract

Path: `users/{uid}/householdNotificationPreferences/{householdID}`. A canonical
v1 document has exactly these keys:

| Key | Exact value |
| --- | --- |
| `schemaVersion` | integer `1` |
| `uid` / `householdID` | owning path IDs; non-empty, at most 128 characters, no `/` |
| `memberJoinedAtSnapshot` | exact trusted `members/{uid}.joinedAt` for this membership epoch |
| `medicationRemindersEnabled` | boolean |
| `assignmentAlertsEnabled` | boolean |
| `urgentAlertsEnabled` | boolean |
| `pushEnabled` | boolean; controls provider push, not mandatory inbox |
| `backupForMemberIDs` | sorted unique list of 0–20 canonical UIDs; no self ID; every entry must be current at write |
| `quietHoursEnabled` | boolean |
| `quietStartMinute` / `quietEndMinute` | integers `0..1439`; unequal when enabled |
| `summaryEnabled` | boolean |
| `summaryMinute` | integer `0..1439` in household local time |
| `timeZoneIdentifierSnapshot` | current validated household IANA timezone at write |
| `revision` | create `1`; each accepted update is previous `+1` |
| `createdAt` / `updatedAt` | trusted Timestamps; `createdAt` immutable |

The client calls `setHouseholdNotificationPreferences`; it never writes the
document directly. The exact request contains `householdID`,
`expectedRevision`, `clientMutationID`, and the ten preference values above.
Unknown or extra keys are rejected. `expectedRevision = 0` creates a missing
document; otherwise it must equal the current canonical revision. A separate
exact `resetMalformedNotificationPreferences` request contains only
`householdID` and `clientMutationID`, is accepted only for a current member with
a malformed document, and replaces it with canonical conservative defaults.
If the malformed document has a positive integer revision, reset writes that
revision `+1`; otherwise it writes revision `1`. The transaction rechecks that
the document is still malformed, so reset cannot overwrite a concurrent valid
save. Reset preserves `createdAt` only when it is a valid Timestamp not after
trusted now; otherwise both `createdAt` and `updatedAt` use trusted now. It
always writes the current membership/timezone snapshots. Both callables return
exactly `{householdID, revision, existing}`, where
`existing = true` means this exact mutation receipt was replayed and `false`
means this call performed the write. They use
`unauthenticated`, `invalid-argument`, `permission-denied`, `aborted` for a
revision race, and `failed-precondition` with safe details
`preferences-already-canonical` or `preferences-malformed`. Identical retry is
resolved from its receipt after auth/current-membership-epoch validation but
before preference current-state validation; mutation ID reuse with another
payload is rejected. Unexpected dependency failure remains
`unavailable` or `internal`; the UI retains input and offers Retry rather than
claiming a validation or permission cause.
Receipts bind UID, action, mutation ID, and keyed payload fingerprint, but never
store choices, member lists, tokens, source IDs, or protected content.

Missing preferences use in-memory conservative defaults without creating a
document: all four enable booleans are false, backup is empty, quiet hours are
disabled with `1320`/`420`, and summary is disabled with minute `1080`.
Malformed or stale-timezone preferences block routing only for that member and
surface repair; other canonical recipients are unaffected. A successful save
always snapshots the server-read household timezone. No client guesses or
repairs authority locally.

If member B includes A in `backupForMemberIDs`, B opts in only when A is the
authoritative responsible member. This grants no task, medication, owner,
takeover, or handoff authority. Preference reads require current membership and
the owning UID, and the membership epoch must match. A syntactically valid
backup ID that later leaves is ignored for routing and does not make B's whole
policy malformed. Client create/update/delete, another user's read, and list
access are denied.

Receipt path is
`users/{uid}/notificationPreferenceMutationReceipts/{receiptID}`, where
`receiptID = SHA256(uid + ":" + memberJoinedAtSnapshot + ":" +
clientMutationID)`, where the Timestamp component is canonical decimal
`seconds:nanoseconds` rather than object stringification. Its exact server-only
keys are `schemaVersion = 1`, `uid`,
`householdID`, `memberJoinedAtSnapshot`, `action`, keyed `fingerprint`, exact
non-sensitive `result = {householdID, revision, existing}`, and trusted
`createdAt`. Here `fingerprint = SHA256(canonicalJSON(action, exact request
excluding clientMutationID))`; "keyed" means field-name-keyed canonical JSON,
not a secret HMAC. Stored result always has `existing = false`; replay returns a
copy with `existing = true`.

Safe error details are exact: aborted revision race is
`{reason: revisionMismatch, currentRevision}`; malformed save is
`{reason: preferencesMalformed, currentRevision}`; reset against a canonical
document is `{reason: preferencesAlreadyCanonical, currentRevision}`.
`currentRevision` is a non-negative integer or null when the malformed value is
not an integer. No details include preference values.

## Exact recipient and channel matrix

`Inbox` means a private item is generated. `Push` additionally requires
canonical preferences with `pushEnabled = true`, an enabled canonical
installation, both gates, and all dispatch-time authority checks.

| Source/level | Inbox recipients | Push requirement | Quiet/summary |
| --- | --- | --- | --- |
| Claimed medication `due` | responsible member, mandatory | responsible has both medication and push enabled | never delayed or summarized |
| Claimed medication `+15` / `+30` | responsible mandatory; each canonical backup whose list contains responsible UID and medication is enabled | responsible and each backup have both medication and push enabled | never delayed or summarized |
| Unclaimed medication `due` / `+15` / `+30` | current members with medication enabled | recipient also enables push | never delayed or summarized |
| Responsibility proposal | exact transfer `consentByID`, mandatory | assignment and push enabled | quiet delay; summary/coalescing allowed |
| Handoff offer | exact recipient, mandatory | assignment and push enabled | quiet delay; summary/coalescing allowed |
| Urgent unclaimed one-off care | current members with urgent enabled | recipient also enables push | never delayed or summarized |
| Routine care | no Reminders item; Today remains the in-app surface | never | not applicable |
| Terminal/cancelled/closed/expired source | no later item | no later attempt | not applicable |

Missing/off preferences never suppress the responsible member's or direct
target's mandatory inbox, but always suppress their push. Backup,
unclaimed-medication, and urgent inbox require explicit category opt-in.
Provider failure never widens recipients.

Exact source eligibility is: medication occurrence is canonical and
`outcomeStatus = unresolved` (claimed routing uses its canonical
`responsibilityStatus/responsibleByID`); LT-5 transfer is canonical
`status = pending` and recipient is `consentByID`; handoff session is canonical
`status = offered` and recipient is `recipientID`; urgent task is canonical
one-off `priority = urgent` and `status = unclaimed`; retained direct assignment
is a canonical task with a complete open assignment-request overlay. Any other
state is terminal/ineligible for that intent type.

Exact stored relative source paths are
`medicationOccurrences/{sourceID}`, `tasks/{sourceID}`,
`taskResponsibilityTransfers/{sourceID}`,
`handoffSessions/{sourceID}`, or recipient-private
`notificationDigests/{sourceID}` according to `sourceType`. Household/user path
segments are never embedded in `sourcePath`; household and recipient are the
separate exact fields.

Responsibility, target, membership, or source revision change cancels old active
items before new recipient items are created for that recipient. Cross-recipient
convergence is eventual, not one unbounded transaction; every provider claim
re-reads the source, so a stale item cannot send while cancellation catches up.
Terminal source state cancels active items and unattempted deliveries. A
provider call already started cannot be recalled; it records an honest terminal
result while its inbox item remains cancelled.

Preference changes apply only to future source intents. Once a new preference
revision commits, the prior routing authority is immediately invalid: every
finalizer/claim re-read guarantees zero new provider call under the old revision.
Persisting cancelled state across old unattempted deliveries/digests is eventual
through bounded reconciliation, and callable success never claims that all
derived documents were rewritten. It does not cancel a mandatory
responsible/direct inbox item and later re-enabling never backfills that item. A
non-mandatory backup/unclaimed/urgent inbox item may eventually be cancelled
with `policyChanged`. Saving preferences never duplicates a mandatory item.

## Exact private inbox

Path: `users/{uid}/notificationInbox/{intentID}`. The server creates/updates it;
the current recipient may read it only while the membership epoch matches. A
canonical v1 item has exactly:

| Key | Exact value |
| --- | --- |
| `schemaVersion` / `id` | integer `1`; `id` is the 64-lowercase-hex document ID |
| `householdID` / `recipientID` | canonical IDs; recipient equals parent UID |
| `recipientJoinedAtSnapshot` | exact trusted `members/{uid}.joinedAt` at creation |
| `category` | `medication`, `assignment`, `urgent`, or `summary` |
| `level` | `due`, `overdue15`, `overdue30`, `directAssignment`, `responsibilityProposal`, `handoffOffer`, `urgentUnclaimed`, `burstSummary`, or `dailySummary` |
| `routeReason` | `responsible`, `backup`, `medicationOptIn`, `directTarget`, `handoffRecipient`, `urgentOptIn`, or `summary` |
| `sourceType` | `medicationOccurrence`, `task`, `taskResponsibilityTransfer`, `handoffSession`, or `notificationDigest` |
| `sourceID` / `sourcePath` | bounded opaque ID and exact type-derived relative path |
| `sourceRevision` | non-negative integer |
| `preferenceRevision` | canonical positive revision, or `null` for mandatory inbox without canonical preferences |
| `status` | `active` or `cancelled` |
| `availableAt` / `expiresAt` | trusted Timestamps with `availableAt < expiresAt` |
| `nextDispatchAt` | trusted Timestamp or `null` for inbox-only/terminal delivery |
| `coalescingKey` | 64-hex string or `null` |
| `cancelReason` | `null`, `sourceTerminal`, `sourceChanged`, `membershipEnded`, `policyChanged`, or `expired` |
| `cancelledAt` | trusted Timestamp only when cancelled; otherwise `null` |
| `createdAt` / `updatedAt` | trusted Timestamps, non-decreasing |

An item never contains a name, task title, medicine, dose, health value/note,
handoff text/phone, token, image URL, report body, payload/body, or raw error.
Expiry is evaluated at trusted read/claim time and need not rewrite the item.

For source items:

`intentID = SHA256(canonicalJSON(householdID, sourceType, sourcePath,
sourceRevision, level, recipientID, recipientJoinedAtSnapshot.seconds,
recipientJoinedAtSnapshot.nanoseconds))`.

New LT-5 proposals use the authoritative
`taskResponsibilityTransfers/{transferID}` path, transfer ID, transfer revision,
`level = responsibilityProposal`, and exact `consentByID`; repeated proposals
therefore cannot collide. Retained direct assignment requests use the task path,
task revision, and `level = directAssignment` and never masquerade as a transfer.

Before a medication intent transaction, the generator validates the medication,
immutable schedule version, local date, slot, effective interval, DST policy,
and deterministic occurrence ID using the same canonicalizer as medication
mutation. If the occurrence is absent, the transaction first creates the exact
canonical unresolved/unclaimed revision-0 occurrence with its trusted `dueAt`
and snapshots, then uses that document as the source. If it exists, the exact
canonical occurrence and current revision/state are used. Generation never
routes from a merely virtual or malformed occurrence.

Summary items reference the exact server-only digest document below. Transactions
create once; reuse with a different canonical body fails closed.
Medication expiry is the end of its 15-minute semantic window. Assignment and
urgent task expiry is at most 24 hours from creation and ends earlier on terminal
source state. Handoff expiry is `min(plannedEndAt, createdAt + 24h)`.

Recent queries filter household and current `recipientJoinedAtSnapshot`, order
by `createdAt desc` then document ID `desc`, request 21 raw documents, expose the
first 20, set `mayHaveMore = rawCount == 21`, and use the twentieth raw
`DocumentSnapshot` as an opaque continuation token. The preview document is
returned by the next page, not decoded twice. Malformed
first/middle/final documents increment a visible dropped count but never
truncate continuation. Cache, pending, permission, decode, and network states
remain distinct. Dropped-only is repair state, never authoritative empty.

An active item is visible in Inbox immediately; `availableAt` controls provider
availability, not row visibility. Cancelled items may remain as generic
no-longer-available history but are not unread and never advance the cursor.
Expired-but-not-yet-cancelled items remain conservatively unread until a server
resolver or sweeper cancels them; device time alone cannot hide or mark them.
Only a server-confirmed non-cache page with zero active items, zero dropped
items, no pending writes, and no error may show authoritative no-active-reminders
copy. Realtime recent-window eviction preserves already loaded older rows and
page dropped counts accumulate for the screen lifetime.

### Server-only digest source

Path: `users/{uid}/notificationDigests/{digestID}`. It is a derived provider
coordination record, not care truth, and clients cannot read/write it. Exact v1
keys are `schemaVersion`, `id`, `householdID`, `recipientID`,
`recipientJoinedAtSnapshot`, `mode` (`burst` or `daily`), `coalescingKey`,
`windowStartAt`, `windowEndAt`, `catchUpUntilAt`, `preferenceRevision`, `status`
(`collecting`, `ready`, `cancelled`, or `blocked`), nullable `cancelReason`
(`noValidSource`, `availabilityExpired`, `policyChanged`, or
`membershipEnded`), nullable `safeErrorCode` (`tooManyCandidates` only),
`createdAt`, `updatedAt`, `nextFinalizeAt` (non-null only while collecting),
nullable `readyAt`, `cancelledAt`, and `blockedAt`.
Times are trusted; window is half-open and
non-empty. `digestID = SHA256(canonicalJSON(householdID, recipientID,
membership epoch, mode, windowStartAt, windowEndAt, preferenceRevision))` and
`coalescingKey = digestID`.

Every push-eligible assignment/handoff inbox item stores that coalescing key and
has `nextDispatchAt = null`; it never creates an individual delivery. A
mandatory but push-ineligible item stores null for both fields. At window
close plus five seconds, the digest finalizer queries all of that recipient's
source items by exact household, membership epoch, and coalescing key in raw
pages of 100 with exact `category == assignment` and
`sourceType in [task, taskResponsibilityTransfer, handoffSession]`; summary
items can never satisfy their own digest. It re-reads sources until it finds one authoritative valid source
or exhausts the query. It examines at most 1,000 candidates per run. If a valid
source is found, it
sets the digest ready and creates one summary inbox item with
`sourceID = digestID`, `sourcePath = notificationDigests/{digestID}`,
`sourceRevision = 1`, `level = burstSummary` for burst or `dailySummary` for
daily, `routeReason = summary`,
`preferenceRevision` from the digest,
`dispatchAvailableAt = max(readyAt, quiet-end instant when applicable)`,
`availableAt = dispatchAvailableAt`,
`expiresAt = windowEndAt + 24h`,
`nextDispatchAt = dispatchAvailableAt`, and `coalescingKey = digestID`. If none remain, it
cancels the digest and creates no summary. Dispatch repeats the query and source
validation; an exhausted query with zero valid originals cancels with
`noValidSource`; reaching 1,000 while `mayHaveMore` blocks with
`tooManyCandidates`. The inbox is used
only to locate candidates, never to assert their source truth. Summary provider
claim requires the same current membership epoch and exact preference revision,
`pushEnabled`, and `assignmentAlertsEnabled`; any mismatch cancels the
unattempted digest and enabling later does not backfill it.

Exact preference-revision, push master, or assignment-category mismatch cancels
the digest with `policyChanged`; missing/current-epoch membership mismatch uses
`membershipEnded`.

`dispatchAvailableAt` is a finalizer-local variable, not an inbox/digest field;
only its exact value is persisted into the already-declared `availableAt` and
`nextDispatchAt` keys.

If `dispatchAvailableAt >= windowEndAt + 24h`, finalization cancels the digest
with `availabilityExpired` and creates no summary item, preserving the inbox
invariant `availableAt < expiresAt` even across DST folds or long quiet windows.

A five-minute recovery scheduler queries collecting digests ordered by
`nextFinalizeAt asc, document ID asc`, limit 100, and processes only due rows. A crash simply
rescans the bounded candidate pages; no partial ready state is exposed. A late
source trigger may reopen only `cancelled/noValidSource`, only before
`catchUpUntilAt`, and only if no summary item/delivery exists. Blocked or any
other cancelled digest never reopens automatically.

Digest field invariants are exact: collecting has non-null `nextFinalizeAt` and
all ready/cancelled/blocked fields null; ready has non-null `readyAt`, null
`nextFinalizeAt`, and all cancellation/block fields null; cancelled has
`cancelReason` and `cancelledAt` non-null with ready/block/finalize fields null;
blocked has `safeErrorCode` and `blockedAt` non-null with
ready/cancel/finalize fields null. Reopening `cancelled/noValidSource` clears its
cancel fields, sets collecting, and writes a new trusted `nextFinalizeAt` within
the unchanged catch-up bound.

## Exact read cursor

Path: `users/{uid}/notificationInboxState/{householdID}`. It contains exactly
`schemaVersion = 1`, `householdID`, `recipientJoinedAtSnapshot`, `createdAt`,
`intentID`, and trusted `updatedAt`.

The cursor is the newest safely displayed, unexpired item ordered by
`(createdAt, intentID)`. Rules allow the owning current member to get/create or
monotonically update it only when the referenced item exists, matches household,
membership epoch, and exact `createdAt`. Equal is idempotent; backwards,
fabricated, delete, list, and another user's access are denied. `updatedAt` must
equal `request.time`. Cache, pending, unknown, malformed, or read error keeps
unread conservative. Opening a push does not mark read; the exact Reminders row
must first be visible.

Unread precedence is exact: a safely decoded active item newer than a
server-confirmed cursor is unread; active evidence plus cursor
unknown/error/pending is conservatively unread; any dropped-item evidence is
conservatively unread. A server-confirmed empty or cancelled-only page is not
unread even if no cursor exists. Cache-empty/cancelled-only without prior active
or dropped evidence does not invent a dot, but the page labels cache uncertainty.
Loading/error preserves the previously rendered dot; an initial loading/error
state without item/dropped evidence starts without a dot and shows the separate
recoverable status. A successful server refresh recomputes from these rules.

## Exact provider delivery

Legacy Phase-5 records remain server-only at
`households/{householdID}/medicationReminderDeliveries/{deliveryID}`. LT-6 never
writes them.

LT-6 path: `users/{uid}/notificationDeliveries/{deliveryID}`. A current recipient
may read their own safe record; clients cannot write/delete. A canonical v2
record has exactly:

| Key | Exact value |
| --- | --- |
| `schemaVersion` / `id` | integer `2`; 64-hex document ID |
| `intentID` | canonical inbox intent ID |
| `householdID` / `recipientID` / `recipientJoinedAtSnapshot` | must match the intent and owning UID |
| `installationHash` | stable canonical installation document ID |
| `status` | `queued`, `attempting`, `providerAccepted`, `providerUnknown`, `retryableFailure`, `permanentFailure`, `cancelled`, or `expired` |
| `attemptCount` | integer `0..3` |
| `nextAttemptAt` | non-null for queued/definite retryable failure; otherwise null |
| `leaseID` / `leaseExpiresAt` | both non-null only while attempting |
| `providerRequestStartedAt` | trusted Timestamp only after the final pre-send transaction while attempting; otherwise null |
| `providerAcceptedAt` / `providerUnknownAt` / `terminalAt` | nullable trusted times consistent with status |
| `safeErrorCode` | `null`, `sourceTerminal`, `policyChanged`, `membershipEnded`, `installationDisabled`, `installationDuplicate`, `tokenInvalid`, `providerRejected`, `providerAmbiguous`, or `leaseExpired` |
| `createdAt` / `updatedAt` | trusted Timestamps |

`deliveryID = SHA256(canonicalJSON(intentID, installationHash))`. Token values
are read only from the current installation immediately before provider call and
are never copied into any other document, payload, analytics, or log. Rotation
on one installation cannot create another delivery. Two installations may each
receive once.

Canonical installation document IDs are exactly 64 lowercase hexadecimal
characters, as produced from the stable local installation secret. Updated
Rules require that shape for new documents. Existing noncanonical IDs remain
read/update compatible for retained clients but are never LT-6 delivery
candidates. Duplicate canonical documents are grouped only within one
UID/household by current token value.

The one-time server-only path
`users/{uid}/notificationDeliveryManifests/{intentID}` freezes delivery
materialization. Its exact keys are `schemaVersion = 1`, `intentID`,
`householdID`, `recipientID`, `recipientJoinedAtSnapshot`, sorted unique
`selectedInstallationHashes`, integer `selectedCount` equal to list length,
positive integer `bindingKeyVersion`,
`status` (`materializing`, `complete`, or `blocked`), nullable `safeErrorCode`
(`tooManyInstallations` or `conflictingDelivery`), nullable `cursorInstallationHash`, `createdAt`,
`updatedAt`, `nextRecoveryAt` (non-null only while materializing), nullable
`completedAt`, and nullable `blockedAt`. The first
materializer scans eligible installations, chooses the lexicographically
smallest canonical ID per duplicate-token group, fails safely with
`tooManyInstallations` above 1,000 eligible documents, and persists the entire chosen
ID list before creating deliveries in batches of at most 400. Provider scans
ignore a manifest until complete. Too many documents atomically writes blocked,
error, and blockedAt and creates no delivery. Resume uses the persisted cursor.
A five-minute recovery scheduler queries collection-group manifests with
`status == materializing`, ordered by `nextRecoveryAt asc, document ID asc`,
limit 100, and processes only due rows. Every delivery claim must read the matching manifest, require complete,
matching epoch, and inclusion of its installationHash. Once
complete, selection never changes: later installation creation, deletion,
disablement, or a duplicate becoming smallest cannot create another delivery
for that intent. A missing/disabled selected installation suppresses its attempt
rather than substituting a duplicate.

Each materialization batch is one transaction: it reads the manifest in
materializing state and exact cursor, creates or verifies at most 400 canonical
delivery documents, then advances cursor/updatedAt/nextRecoveryAt. An existing
delivery with the exact expected body is an idempotent no-op; a conflicting body
atomically blocks the manifest with `safeErrorCode = conflictingDelivery` and
creates/updates nothing else. The final batch atomically sets complete,
completedAt, clears cursor/nextRecovery/error, and only then makes deliveries
claimable.

On a definite invalid-token response, the dispatcher re-queries that
UID/household's installations and disables every document whose current token
equals the rejected token. The value is held only in process memory for that
operation and is never logged or persisted outside the token documents.

Dispatch-time convergence of two selected installations onto one current token
is serialized by a server-only endpoint binding at
`households/{householdID}/notificationEndpointBindings/{bindingID}`. The ID is
`HMAC-SHA256(versionedServerSecret, canonicalJSON(intentID, recipientID,
currentToken))`;
the secret comes from provider secret configuration, is injectable in local
tests, and is never committed. The exact record contains `schemaVersion = 1`,
`intentID`, `recipientID`, `recipientJoinedAtSnapshot`, immutable
`winningDeliveryID`, exact positive `bindingKeyVersion` equal to the manifest,
`status` (`reserved`, `providerAccepted`,
`providerUnknown`, `retryableFailure`, `permanentFailure`, or `cancelled`),
nullable trusted `leaseExpiresAt`,
`expiresAt = intent.expiresAt + 24h`, and trusted `createdAt/updatedAt`. It stores
no token or unkeyed token hash and is denied to clients.

The final provider-start transaction creates or reuses this binding. If absent,
the candidate becomes the immutable winner. If bound to another delivery, the
candidate cancels with `installationDuplicate` and never calls the provider,
even if the original installation later rotates/disables. The winning delivery
alone may retry a definite retryable failure, moving the binding back to
reserved with the same winner; all terminal states remain terminal. The binding
follows its honest state and is retained through expiry. Concurrent or post-manifest token
convergence therefore has one endpoint attempt stream without changing stable
installation delivery identity.

The manifest freezes one binding key version for every delivery of an intent.
All candidates and retries use that version, even after the active key rotates.
The server key ring must retain an old key for at least 72 hours after the last
manifest created with it; removing a still-referenced version fails dispatch
closed and never falls forward to a new key. Keys are provider secrets and are
never committed. Local tests inject deterministic versioned keys.

An attempt requires a trusted short lease and the LT-5 membership-revocation
claim. The claim transaction re-reads current membership/epoch, revocation
absence, enabled canonical installation, active/unexpired item, current source
revision/state, preference, and both gates. Dispatch re-reads its gate again in
a final transaction that writes `providerRequestStartedAt`, then calls the
provider. A crash after that write is conservatively ambiguous even if no bytes
were actually sent. Definite pre-provider/rejection failures may retry with
bounded backoff before TTL/attempt limit. Timeout or connection loss after bytes
may have been sent becomes terminal `providerUnknown` with
`providerAmbiguous` and is never automatically retried. Expired attempting lease
with null `providerRequestStartedAt` becomes retryable; with a non-null value it
becomes providerUnknown. No state is called `delivered`.

The final pre-send transaction re-reads both v2 gates, effective cutoff,
complete matching manifest, selected installation, membership/revocation,
preference revision, inbox item, authoritative source/digest, and endpoint
binding. If a gate is
disabled or unreadable while the cutoff still permits the item, it deletes the
revocation claim, releases the delivery lease, restores queued with the prior
attemptCount, and sets `nextAttemptAt = trusted now + 5 minutes`; the gate-first
scanner prevents a hot loop while disabled. If a changed cutoff or any other
authority makes the item permanently ineligible, it deletes the claim and
cancels instead. Only after all checks pass does it set
`providerRequestStartedAt`; from then on ambiguity rules apply.

The provider adapter has only four typed outcomes: accepted,
definiteRetryableRejection, definitePermanentRejection, or ambiguous. The local
mapping allowlist treats explicit provider server-unavailable/internal/quota
responses as definite retryable, invalid/unregistered token, invalid argument,
sender mismatch, and authentication/configuration rejection as definite
permanent, and timeout/connection loss/unknown SDK result as ambiguous. Raw
provider text is never stored. AC09 must verify the real SDK mapping before any
dispatch activation.

Exact delivery state invariants are:

| Status | Exact field relationship |
| --- | --- |
| `queued` | attempts `0..2`; next attempt non-null; all lease/request/result/terminal fields null; error null |
| `attempting` | attempts `1..3`; lease fields non-null; next/result/terminal null; request-start null before final gate or trusted non-null after it; error null |
| `retryableFailure` | attempts `1..2`; next attempt non-null; lease/request/result/terminal null; error `providerRejected` or `leaseExpired` |
| `providerAccepted` | attempts `1..3`; `providerAcceptedAt == terminalAt` and non-null; next/lease/request/unknown null; error null |
| `providerUnknown` | attempts `1..3`; `providerUnknownAt == terminalAt` and non-null; next/lease/request/accepted null; error `providerAmbiguous` |
| `permanentFailure` | attempts `1..3`; terminalAt non-null; scheduling/lease/request/result null; error `tokenInvalid` or `providerRejected` |
| `cancelled` | attempts `0..3`; terminalAt non-null; scheduling/lease/request/result null; error is `sourceTerminal`, `policyChanged`, `membershipEnded`, `installationDisabled`, or `installationDuplicate` |
| `expired` | attempts `0..3`; terminalAt non-null; scheduling/lease/request/result null; error null |

Dispatcher recovery uses two bounded collection-group queries: status in
`queued/retryableFailure`, ordered by `nextAttemptAt asc, document ID asc`; and
`attempting`, ordered by `leaseExpiresAt asc, document ID asc`. Each page is at
most 100 raw documents. Recipient delivery history filters household and
membership epoch and orders `updatedAt desc, document ID desc`. Required
composite indexes are committed with the first implementation.

Rules permit inbox list only when every possible result is the owning UID's
current household/membership epoch and limit is at most 21; the client query
uses `createdAt desc, __name__ desc`. Delivery list similarly constrains
household, membership epoch, current `installationHash`, limit 21, and uses
`updatedAt desc, __name__ desc`. Server digest validation queries exact
household, epoch, and coalescing key. The index manifest must include these
queries, both dispatcher recovery queries, manifest `status/nextRecoveryAt`,
digest `status/nextFinalizeAt`, expiry `status/expiresAt`, and medication leave
blocker `responsibleByID/outcomeStatus/dueAt`, each with the documented
document-ID tie-break. Emulator tests exercise actual query shapes rather than
only single-document Rules.

Exact composite index directions are:

| Collection | Query scope | Fields in order |
| --- | --- | --- |
| `notificationInbox` recent | `COLLECTION` | `householdID ASC`, `recipientJoinedAtSnapshot ASC`, `createdAt DESC`, `__name__ DESC` |
| `notificationInbox` digest candidates | `COLLECTION` | `householdID ASC`, `recipientJoinedAtSnapshot ASC`, `category ASC`, `sourceType ASC`, `coalescingKey ASC`, `createdAt ASC`, `__name__ ASC` |
| `notificationDeliveries` history | `COLLECTION` | `householdID ASC`, `recipientJoinedAtSnapshot ASC`, `installationHash ASC`, `updatedAt DESC`, `__name__ DESC` |
| `notificationDeliveries` ready | `COLLECTION_GROUP` | `status ASC`, `nextAttemptAt ASC`, `__name__ ASC` |
| `notificationDeliveries` lease recovery | `COLLECTION_GROUP` | `status ASC`, `leaseExpiresAt ASC`, `__name__ ASC` |
| `notificationDeliveryManifests` recovery | `COLLECTION_GROUP` | `status ASC`, `nextRecoveryAt ASC`, `__name__ ASC` |
| `notificationDigests` finalization | `COLLECTION_GROUP` | `status ASC`, `nextFinalizeAt ASC`, `__name__ ASC` |
| `notificationInbox` expiry | `COLLECTION_GROUP` | `status ASC`, `expiresAt ASC`, `__name__ ASC` |
| `medicationOccurrences` leave blocker | `COLLECTION` | `responsibleByID ASC`, `outcomeStatus ASC`, `__name__ ASC` |

## Quiet hours, summaries, and coalescing

Household IANA timezone is authoritative. Quiet interval is half-open and may
cross midnight; equal enabled start/end is invalid. Nonexistent DST local time
resolves to the first valid instant after the gap; repeated time uses the first
occurrence. Medication and urgent items ignore quiet/summary delay but still
require master/category push opt-in and never coalesce.

Assignment/handoff push always routes through exactly one digest, so a first
event can never race an individual send. With `summaryEnabled = false`, choose
the fixed two-minute UTC bucket containing the event's base availability. If
that availability falls in quiet hours, base availability is first moved to
quiet end and then bucketed. The bucket remains collecting until its end plus a
five-second grace; one or many valid originals produce exactly one
`burstSummary` push. Burst `catchUpUntilAt = windowEndAt + 10 minutes`.

With `summaryEnabled = true`, burst is disabled. Daily windows are consecutive
half-open intervals between nominal household-local `summaryMinute` instants,
using the stated DST policy. An item after a nominal instant belongs to the next
window. Quiet hours do not change window membership; if window end is inside
quiet hours, the ready summary's `availableAt` moves to quiet end. A missed
finalizer may create only the immediately preceding window before the next
window closes, never an older digest. One or many valid originals produce one
`dailySummary` push. Preference revision is part of digest identity, so a save
starts a new digest; disabling push/category cancels unattempted old digests and
enabling never backfills them. Daily `catchUpUntilAt` is the following nominal
summary window end.

## Exact dual gates and Phase-5 cutover

Paths:

- `systemConfig/notificationIntentGenerationV2`;
- `systemConfig/notificationDispatchV2`.

Each contains exactly `schemaVersion = 1`, boolean `enabled`, exact Firebase
`projectID`, trusted `cutoverAt`, non-empty bounded `updatedBy`, and trusted
`updatedAt`. Missing, extra, malformed, disabled, project-mismatched, or failed
reads are off. Clients cannot read/write either gate.

| Generation | Dispatch | Observable result |
| --- | --- | --- |
| off | off | no new intent; no provider call |
| on | off | new private inbox intents only |
| off | on | no generation and no dispatch |
| on | on | only active intents whose semantic source instant is at/after both cutovers may dispatch |

The effective cutoff is `max(generation.cutoverAt, dispatch.cutoverAt)`. Exact
semantic instants are: medication `dueAt + 0/15/30 minutes` for each level;
retained direct assignment `assignmentRequestedAt`; LT-5 transfer `createdAt`;
handoff `offeredAt`; urgent one-off care trusted task `createdAt`; burst digest
`windowEndAt`; daily digest `windowEndAt`. Digest candidate queries also exclude
every original whose own semantic instant is before the effective cutoff. The
same pure mapping is used by generation, materialization, claim, and route
resolution.

Generation checks at scheduler/trigger entry and create transaction. Dispatch
checks at scan, claim transaction, and immediately before provider call. No
activation backfills an older source/window. Dispatch-off leaves unexpired
inbox items visible but begins no attempt. Disabling during a provider call
cannot recall it; the result remains honest and is not retried just because the
gate reopens.

The Phase-5 `systemConfig/notificationDispatch` remains disabled. The broad
`dispatchMedicationReminders` scheduled export must be removed before either v2
gate can be enabled; a pure helper may remain only for compatibility tests.
Safe order: ship strict readers/UI first; deploy Rules/indexes/callables/new
generator/dispatcher with both gates off; prove retained readers, stable
installation dedupe, minimum version, staging routing, and old export absence;
enable generation at a fresh cutover; inspect synthetic intents; only then seek
separate LT6-AC09 authorization for dispatch. This local task does not perform
those remote steps.

## Typed interaction recovery

Visible title/body is fixed generic copy. Payload has exactly four string keys:
`schemaVersion = "1"`, `destination = "notificationInbox"`, `householdID`, and
`inboxItemID = intentID`. Unknown keys or invalid/mismatched IDs are rejected.
The notification title is exactly `CoPaw`; body is exactly
`ケアの更新があります / Care update available`; collapse key is exactly
`copaw-` plus the first 32 lowercase hex characters of
`HMAC-SHA256(manifest versioned secret, "collapse|" + intentID)`; this is a
non-sensitive stable per-intent identity, so distinct medication levels and
urgent intents never replace one another, retries reuse one key, and each digest remains one intent.
TTL is `expiresAt - providerRequestStartedAt`, clamped to
`1..86400` seconds. Sounds, badges, Critical Alerts, and source-specific copy are
out of scope.

Trusted expiry/source resolution uses callable `resolveNotificationInboxRoute`,
not device time. Its exact request is `{householdID, inboxItemID}`. After Auth,
App Check outside emulator, membership epoch, strict item decode, trusted now,
and authoritative source/digest validation, it returns exactly either
`{disposition: open, householdID, inboxItemID, category, level,
serverCheckedAt}` or `{disposition: reject, householdID, inboxItemID, reason,
serverCheckedAt}`. `serverCheckedAt` is an RFC-3339 UTC string with exactly
millisecond precision. Reject reason is one of `missing`, `malformed`, `expired`,
`cancelled`, `membershipEnded`, `sourceChanged`, or `sourceUnavailable` and
contains no source detail. Auth/shape/membership use
`unauthenticated`/`invalid-argument`/`permission-denied`; network, deadline, and
internal uncertainty remain callable errors so the client keeps Retry. Resolver
open success performs no write and never advances read state. An expired reject
transactionally changes an exact still-active item to cancelled with
`cancelReason = expired` and trusted `cancelledAt/updatedAt`, then returns reject.
A 15-minute server expiry sweeper performs the same idempotent transition using
a collection-group query `status == active && expiresAt <= trustedNow`, ordered
by `expiresAt asc, document ID asc`, pages of 100. It stops when a page is short.
It runs independently of the
provider-dispatch gate and never creates or sends an intent.

The client persists exactly one content-free JSON record under local key
`copaw.notification.pendingRoute.v1`: the four payload values, state
`waitingForSession`, `resolving`, or `retryable`, and a local monotonically
increasing generation. `resolved` and `rejected` are transient states and clear
the record only after navigation or generic rejection copy is committed. A
newer different click replaces the record and increments generation; an older
in-flight resolver result with another generation is ignored. Repeated clicks
for the current item are idempotent. A later fresh click may reopen the same
safe item. On process launch, persisted `resolving` normalizes to `retryable`;
waiting/retryable remain unchanged.

After resolver disposition open, `NotificationInboxRepository.loadByIDFromServer`
direct-gets the exact item, strict-decodes the same membership epoch, and pins it
above the paged recent window so an item older than 20 can be visibly rendered.
Network/cache/decode failure preserves the pending route as retryable. Only
after the pinned row is committed to the selected Reminders view does the client
clear the route and permit cursor advancement. Foreground shows a generic
banner and navigates only after tap. Background/killed click persists before
waiting for Auth/session. Resolution requires current matching membership epoch,
server-confirmed active unexpired item, and authoritative source. Network/cache
uncertainty keeps Retry. A different current household is never auto-switched;
wrong household, missing/expired/cancelled item, or revoked membership returns
to Today with generic actionable copy. Success opens Updates > Reminders and
waits for the exact row to be visible before cursor advancement.

A click never completes a task, administers/skips medication, accepts a
transfer/session, changes preferences, or grants authority.

## Flutter status, privacy, and acceptance boundary

UI exposes independent enums:

- OS permission: `notDetermined`, `denied`, `authorized`, `provisional`,
  `unsupported`, `error`;
- preference authority: `missingDefaults`, `serverConfirmed`, `cached`,
  `pendingWrite`, `malformed`, `error`;
- installation readiness: `disabled`, `registering`, `ready`, `unavailable`,
  `unsupported`, `error`;
- provider evidence: `notVerifiedForCurrentInstallation`, `providerAccepted`,
  `providerUnknown`, `definiteFailure`.

Provider evidence is scoped to current household, current membership epoch, and
this installationHash. The repository queries delivery records in that scope by
`updatedAt desc, document ID desc`, limit one. No record, queued, attempting,
cancelled, or expired maps to `notVerifiedForCurrentInstallation`; providerAccepted maps
only to `providerAccepted`; providerUnknown maps only to `providerUnknown`;
retryable/permanent failure maps to `definiteFailure`. UI always labels the
attempt time only when a record with an attempt exists, labels the scope, and
never presents it as household-wide delivery health.

Provider observation authority is separately `loading`, `serverConfirmed`,
`cached`, or `error`. Only serverConfirmed may present the mapped value as
current evidence. Cached shows its timestamp as stale and uses cautious copy;
loading/error preserve the last rendered evidence with loading/error status but
do not promote it. Installation `ready` requires the current OS token to match a
canonical enabled installation document from a server-confirmed snapshot with
no pending write. Cache/pending mismatch is `registering`; missing/disabled,
permission/network, unsupported platform, and malformed data map to the distinct
installation states already listed.

OS authorization is never labelled reminders enabled. `providerAccepted` copy
says display is unverified. Profile separates readiness and preferences.
Updates keeps five primary destinations and adds Changes/Reminders secondary
views. The primary dot is the OR of both conservative unread states, never a
number. Reminders never enter Changes, Activity, reports, or PDF.

True leave's final success transaction atomically deletes that household's
preference and inbox cursor, marks the membership receipt complete, and removes
the revocation pointer. If any write cannot commit, leave does not report
success and retry resumes. Old inbox/delivery/digest/manifest records remain
server-owned but their joined-at epoch prevents read, route, or dispatch after
leave/rejoin. Rejoin therefore starts with missing conservative preferences;
the old epoch-bound preference mutation receipt cannot return stale success.
Before revocation starts, leave also queries canonical medication occurrences
where `responsibleByID == uid && outcomeStatus == unresolved`, ordered by
document ID and limited to 101. It strict-decodes every result before applying
`dueAt > trustedNow - 45 minutes`. Any malformed/missing dueAt blocks with
`medicationResponsibilityNeedsRepair`; 101 results block with
`tooManyMedicationResponsibilities`; any canonical result inside the future or
active due/+15/+30 window blocks with `unresolvedMedicationResponsibility`.
Historical canonical unresolved claims whose last reminder window ended do not
block. The check and member deletion share the leave authority transaction, so
a concurrent claim/revision change aborts or is observed; a missing former
member is never silently reinterpreted as unclaimed by the resolver.
Preference mutation is callable-only, inbox and
delivery client writes are denied, and cursor has only the monotonic Rules write
above. Payload, banner, row, semantics, IDs, errors, receipts, claims, analytics,
and logs may contain only the exact non-sensitive fields here. They must not
contain names, task titles, pet/medicine/dose/health data, handoff/phone content,
tokens, image URLs, report bodies, raw provider errors, or arbitrary source maps.
Lock-screen title/body, collapse key, and TTL remain generic and do not embed
source IDs.

The compact widget/semantics matrix is the full 12-case cross-product of
320×568 and 390×844, English and Japanese, and text scale 1, 2, and 3. Fixtures include long member/error text,
missing/malformed repair, pending save, cache, dropped-only, load-more, route
retry, and all four status layers. Tests assert five-tab and Changes/Reminders
selected semantics, switch values, backup controls, unread dot label,
loading/error/empty/retry reading order, 44×44 targets, no overflow, and status
not expressed by color alone. Profile's backup picker may speak current member
display names because the user must identify an opt-in target; the prohibition
on names applies to notification inbox/delivery/payload/log surfaces, not this
authenticated preference control.

LT6-AC01 through LT6-AC08 require resolver/timezone, Functions, Rules, strict
codec/pagination, race, privacy, repository, interaction, and compact
English/Japanese large-text/semantics tests. Gates-off tests must prove no
provider fake call, legacy delivery creation, or exported broad scheduler.
Rules logs must have no expression/call-stack budget warning. LT6-AC09 remains
the separately authorized APNs/FCM staging/physical-device gate. No green local
test or provider acceptance may be reported as exactly-once device display.
