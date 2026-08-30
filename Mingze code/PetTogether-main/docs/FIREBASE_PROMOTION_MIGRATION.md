# Firebase promotion and migration runbook

Status: LT-1 local contract; no staging or production action is authorized

This runbook separates contract verification from environment promotion. It
does not authorize creating a Firebase project, reading production, deploying,
migrating documents, enabling notifications, or transferring data. `BUILD_SPEC.md`
owns observable acceptance; `docs/firestore-schema.md` owns the target schema;
`docs/legacy-firestore-contract.md` owns legacy decoding and classification.

## Promotion principle

Data is not promoted from Emulator to staging or from staging to production.

- Emulator uses synthetic fixtures to prove migration behavior.
- Independent staging recreates those fixtures with staging Firebase Auth UIDs.
- Production is inventoried in place and defaults to a compatibility rollout
  with zero document rewrites.

Firebase Auth UID is the household-member identity, so copying membership data
between projects would not preserve authorization. Production pet, medication,
health, handoff, notes, reports, image URLs, tokens, receipts, or delivery data
must not be copied into staging. Any later request to use real data in staging is
a separate data-transfer task requiring field-level approval, de-identification,
access/region/retention controls, and deletion evidence.

## Required artifacts

Before staging is considered:

- versioned canonical and legacy schema contracts;
- a reviewed index inventory and the local `firestore.indexes.json` artifact;
- deterministic synthetic fixtures covering every applicable migration class,
  with an explicit zero count for any class that has no pre-approved shape;
- a migration tool with dry-run as the default and explicit project/environment
  guards;
- a reconciliation receipt format and content-free semantic fingerprints;
- a per-write migration manifest and protected before-images for safe patches;
- rollback instructions for app, Rules, Functions, indexes, and data;
- an independently reviewed notification dispatch kill switch that defaults to
  disabled outside Emulator until separately activated.

The repository now contains a guarded Emulator-only dry-run classifier and a
tested default-off notification kill switch. It does not yet contain a migration
apply engine, protected before-image manifest, or executable rollback engine;
those remain required before staging migration acceptance.

## Environment identity guard

Every command plan and evidence receipt records the expected and observed:

- environment name and Firebase/GCP project ID;
- app IDs and iOS/Android bundle/application IDs;
- authenticated operator and least-privilege service-account identity;
- Git commit and migration-tool version;
- Rules, Functions, and index-manifest hashes;
- Functions region/runtime and App Check mode;
- notification dispatch mode.

The tool must refuse to continue if any observed identity differs from the
approved manifest. It must also refuse production apply unless a production
write authorization reference is supplied. A permissive CLI login, project
alias, or local Firebase configuration is not authorization.

## Step 1 — Local Emulator with synthetic fixtures

Use only the `demo-copaw` Emulator configuration documented in
`docs/FIREBASE_LOCAL.md`. Do not import production exports.

Fixtures cover at least:

- canonical household/member/routine/task/pet/medication/health/handoff data;
- readable legacy household, routine, and every task state;
- missing or invalid household timezone;
- missing nullable task overlays and a partial request overlay;
- legacy-primary pet synthesis and an archived pet with retained history;
- invite code with missing `active` and one explicitly inactive code;
- valid Health v1 ordinary records and random-ID v1 daily check-ins;
- Health v2 daily records around local midnight and DST boundaries;
- same-day v1/v2 daily conflicts and mixed water-basis records;
- malformed documents and dangling/cross-household references.

Run sequence:

1. Export the synthetic baseline and compute semantic fingerprints.
2. Run the current dry-run classifier. Every source document is classified exactly once as
   `canonical/no-op`, `safe-additive`, `safe-patch`, `manual/blocking`, or
   `malformed/quarantine`.
3. Independently review the exact classifications. The current tool emits no
   write plan and refuses apply mode.
4. After a separate apply/manifest implementation exists, apply only to
   Emulator. The writes must exactly match the approved plan.
5. Run apply again; it must produce zero writes.
6. Reconcile counts, references, history, report outputs, and privacy-safe logs.
7. Exercise rollback, including a document modified by a simulated user after
   migration. That user change must not be overwritten or deleted.
8. Restore/recreate the baseline and repeat with two clean Auth clients.

Local success proves tooling behavior only. It does not prove deployed IAM,
Rules, indexes, App Check, APNs/FCM, scheduler identity, billing, account
recovery, or physical-device behavior.

## Step 2 — Independent staging

Creating or modifying staging requires explicit staging authorization. Staging
uses a dedicated Firebase/GCP project, ignored platform configuration, unique
app IDs/bundle IDs, staging Auth users, least-privilege IAM, and separate App
Check and APNs/FCM credentials. A staging build must reject production project
identity and must not package production configuration.

Deploy from one pinned commit in this order:

1. Inventory existing staging indexes and live query requirements.
2. Review the exact index plan and wait for every required index to become
   ready. The empty local index manifest must not delete Console-managed indexes.
3. Deploy backward-compatible Functions with notification dispatch disabled.
4. Keep the previously deployed Rules while installing clients that dual-read
   Health v1/v2 and send every new Health write through the callables. Do not
   close v1 direct writes before retained-client compatibility is measured.
5. Establish and record the approved minimum-version or force-upgrade gate.
   Only after no retained direct-v1 writer remains may the current writer-
   closing Rules be deployed. If that evidence is unavailable, stop here and
   prepare a separately reviewed transitional Rules artifact.
6. Create staging Auth users and seed only synthetic fixtures.
7. Run dry-run; apply, second-run idempotence, reconciliation, and rollback
   remain blocked until their executable tooling exists.
8. Run both Flutter and the retained Swift client against each Rules stage and
   Functions. Verify reads and protected writes; absence of a crash is not
   sufficient compatibility evidence.
9. Verify member/outsider authorization, App Check enforcement, clean Auth
   lifecycle, two-client conflicts, restart/reconnect, and real device/provider
   behavior required by the acceptance cases.
10. Only after a separate staging-notification authorization, enable dispatch
    and run due/+15m/+30m, cancellation, token rotation, foreground/background/
    killed, privacy-redaction, and failure/retry checks. Disable it again after
    the test unless continuing operation was explicitly approved.

The notification kill switch must be server-controlled, auditable, and default
off. Deploying Functions must not cause the scheduled worker to scan or send
production-like reminders before activation. An Emulator scheduler being absent
or ignored is not evidence that this gate exists.

## Step 3 — Production read-only inventory

Production read access is the first independent authorization gate. Before any
deploy or write:

1. Confirm project/app identity, region, IAM, App Check, deployed Rules,
   Functions, scheduler state, indexes, and client versions.
2. Count documents by path, schema version, type, and migration class without
   logging document bodies or sensitive field values.
3. Detect malformed/unsafe documents, missing timezones, duplicate daily health
   records, unknown water basis, dangling references, and retained Swift payloads.
4. Produce a read-only dry-run and reconciliation baseline.
5. Stop if the live shape is outside the documented decoder/Rules contract.

Read authorization does not authorize deployment, data writes, exports to a
developer machine, or notification activation.

## Step 4 — Production compatibility deploy

Production deployment is the second independent authorization gate. Before it:

- create a Firestore managed export in a restricted approved bucket and record
  its generation/manifest; restoration must already have been exercised outside
  production without copying production data into staging;
- pin exact app, Rules, Functions, and index versions plus their rollback
  versions;
- compare target and remote indexes and obtain explicit authorization for any
  deletion;
- confirm the notification kill switch is disabled;
- review exact outgoing files/history for secrets, personal information, local
  usernames, absolute paths, generated artifacts, and Firebase configuration.

Prefer a reader-first, zero-document-rewrite deployment:

1. indexes, only after remote comparison and readiness;
2. backward-compatible Functions with notification dispatch disabled;
3. dual-read/all-writes-callable clients as a limited canary while existing
   Rules still permit retained v1 writers;
4. wider client rollout while legacy reads and fields remain intact;
5. explicit minimum-version evidence or an approved force-upgrade;
6. only then, the writer-closing Rules that make Health v1 immutable.

Do not disable legacy readers, remove legacy fields, retire the Swift client, or
force a health migration as part of this compatibility deployment.

The repository `.firebaserc` defaults to `demo-copaw` as a local safety guard.
Every authorized remote command must still use an explicit reviewed project ID;
changing an alias is not an authorization gate.

## Optional production backfill

Production document writes are the third independent authorization gate. The
default is no backfill. A write is considered only when the approved dry-run
proves that a legacy document blocks a required user flow and the transformation
is deterministic.

Allowed candidates are limited to the reviewed legacy classification matrix,
for example deterministic creation of `pets/legacy-primary` from a valid
household pet snapshot. Never infer a missing timezone, actor UID, action time,
status, revision, health local date, water basis, medication outcome, or
historical schedule.

If authorized:

- approve exact counts, paths, fields, batches, and stop thresholds;
- use small batches/transactions and `updateTime` preconditions;
- write no deletes and retain legacy fields;
- record every created/patched path, before fingerprint, after fingerprint, and
  resulting update time in a restricted migration manifest;
- canary one approved cohort, reconcile, then pause for independent review
  before expanding;
- run the same migration version a second time and require zero writes.

## Reconciliation receipt

Each dry-run/apply/rollback produces a receipt containing no pet, medication,
health, handoff, note, phone, image URL, invite code, or token content. Stable
identifiers in portable reports are keyed/HMAC pseudonyms; the key and protected
before-images remain in restricted storage.

The receipt contains:

- environment/project and artifact identities listed above;
- start/end time and separate approval references;
- before/after counts per collection, schema version, type, household pseudonym,
  and migration class;
- planned/applied/skipped/conflicted/error write counts;
- referential checks for household/member/invite, pet, routine/task,
  medication/version/occurrence, and health records;
- proof that completed task actor/time/revision and historical medication
  schedules/outcomes/denominators are unchanged;
- Health v1/v2 counts, daily-conflict counts, unknown-basis counts, and exact
  v2 per-day water aggregation fixtures;
- Flutter/Swift decode diagnostics and dropped/hidden-document counts;
- 7/30-day report semantic fingerprints before and after;
- member-success and outsider-denial results;
- second-run zero-write result and rollback result.

All source counts must equal the sum of the mutually exclusive migration
classes. Any mismatch is a stop condition, not an ignorable warning.

## Rollback

Rollback includes app, Rules, Functions, indexes, and data. A managed export is
a recovery layer, not the complete rollback mechanism: importing an export does
not necessarily remove documents created later.

- Roll back clients, Rules, and Functions to pinned compatible versions while
  keeping legacy fields/readers available.
- Never use the empty local index manifest to remove a remote index during
  rollback. Apply only the independently reviewed index delta.
- Delete a migration-created document only if it is listed in the per-write
  manifest and its current `updateTime` still equals the migration result.
- Restore a patched document from its protected before-image only with the same
  unchanged-update-time precondition.
- If a user or service wrote after migration, stop automated rollback for that
  document and route it to manual reconciliation; never overwrite newer data.
- Notification dispatch is disabled first and its delivery state is reconciled
  separately. Rollback must not resend an already accepted reminder.

## Stop conditions

Stop before the next read, deploy, write, or notification action if any of the
following occurs:

- project/app/operator identity or artifact hash mismatch;
- missing approval, backup manifest, protected before-images, or rollback drill;
- required index still building, unknown remote index, or proposed unapproved
  index deletion;
- live document shape, class count, or path differs from the approved dry-run;
- missing timezone, ambiguous actor/state/time, unknown water basis, daily
  health conflict, malformed reference, or other inference would be required;
- retained Swift or Flutter clients lose a protected read/write flow;
- member access fails or outsider/cross-household access succeeds;
- App Check or expected server-only write enforcement fails;
- notification dispatch is active before its separate gate;
- raw sensitive content, secrets, device tokens, local usernames, or absolute
  machine paths appear in logs, receipts, build artifacts, or outgoing scope;
- reconciliation fingerprints/report denominators differ unexpectedly;
- idempotence produces writes on the second run;
- rollback would overwrite a post-migration user write.

## Four production authorization gates

| Gate | Authorizes | Does not authorize |
| --- | --- | --- |
| P1 — read-only inventory | Inspect approved production metadata and aggregated schema counts | Deploy, export to local/staging, document writes, notifications |
| P2 — compatibility deploy | Deploy the exact approved indexes/Functions/Rules/client artifacts with dispatch disabled | Backfill, legacy deletion, notifications |
| P3 — bounded data write | Apply the exact approved deterministic backfill and rollback plan | Wider transformations, guessed values, notifications |
| P4 — notification activation | Enable the approved production dispatch policy and device/provider acceptance window | Schema migration or unrelated provider changes |

Passing a local test, creating a commit, or approving one gate never implies a
later gate. Production release still requires the relevant physical-device,
provider, account-recovery, privacy, and acceptance evidence in `BUILD_SPEC.md`.
