# CoPaw Flutter migration and care-platform build specification

Status: Accepted for implementation
Owner: Product owner and Codex implementation team
Last updated: 2026-08-17

## User and problem

- Primary users: couples, families, roommates, and trusted caregivers sharing responsibility for one or more pets.
- Situation: care happens across people, devices, schedules, and occasional handoffs.
- Problem: people cannot reliably tell what a pet needs next, who is responsible, whether care or medication actually happened, and what history to share with another caregiver or veterinarian.
- Evidence: the existing CoPaw product contract and working SwiftUI/Firebase collaboration flow; market research informed future monetization potential but does not authorize a paywall in this build.

## Product outcome

Migrate CoPaw to Flutter/Dart without losing the current two-device household collaboration loop, then add multi-pet care, safe medication coordination, structured health history, household handoff, and accurate 7/30-day summaries. All capabilities remain available during this build; modules are separated so pricing can be considered later without rewriting the core domain.

The first release checkpoint worth shipping is:

> Flutter parity for the existing collaboration loop, plus multi-pet foundations and the complete safe-medication outcome flow.

## Confirmed assumptions

- Preserve existing Firebase household, member, routine, task, and activity data through backward-compatible reads and an explicit migration path.
- Prioritize full iOS and two-physical-iPhone acceptance. Android must build and run in an emulator; physical Android release acceptance is later.
- Target a reviewable Beta, not App Store publication in this task.
- Keep Firebase Anonymous Auth during migration. Account linking/recovery is required before treating sensitive health data as production-ready, but is not in the current Beta scope.
- Preserve English and Japanese. The product owner authorized a focused household-dashboard UI/UX refresh plus local medication-profile, medical-record, and photo-affordance design; remote photo storage, voice capture, and diagnosis remain deferred.
- Required local development tools may be installed. Secrets and Firebase configuration remain ignored and local.

## Scope

### In

- Flutter/Dart application scaffold beside the SwiftUI reference app.
- Firebase Anonymous Auth, session restoration, Firestore listeners, transactions, error mapping, and member-scoped Rules.
- Household create/join/profile/leave/rejoin and caregiver synchronization.
- One-time, urgent, daily, and selected-weekday tasks.
- Self-claim, direct assignment, open assignment, accept, decline, cancel, and assignee-only completion.
- Today, Calendar, Activity, profile, loading, empty, error, and recovery states in English and Japanese.
- Household-wide Today, Medications, Calendar, Health, and Activity by default; one optional shared pet filter; chronological care, visible pet identity, responsibility-first assignment UI, calendar event markers, an exact activity timeline, clearer 7/30-day metrics, and consolidated profile preferences.
- Species-aware dog, cat, and rabbit identity with deterministic per-pet colors; pet color identifies ownership while task-category icons identify the care action.
- Multi-pet profiles, pet selection/filtering, archive behavior, task/routine association, and legacy `household.petName` compatibility.
- A medication archive containing active and stopped medicines, purpose, possible-side-effect notes, historical schedule versions, multiple times per day, responsibility, administered/skipped outcomes, skipped reasons, overdue display, trusted timestamps, and concurrency protection.
- Notification phase: due, 15-minute, and 30-minute escalation with cancellation and permission/token handling.
- Structured medical/health timeline: veterinary visits, recorded diagnoses, prescriptions and veterinarian instructions, weight, water intake, appetite, energy/mood, stool/observation, symptom/injury, vaccine, and notes; local photo attachment affordances are visible but Firebase Storage upload remains deferred.
- Household handoff information and accurate in-app 7/30-day task, medication, and health summaries; system sharing and PDF follow after data reconciliation passes.
- Rules tests, model/repository/state/widget/integration tests, platform builds, two-client and two-iPhone acceptance, privacy review, and evidence handoff.

### Not now

- RevenueCat, StoreKit billing, prices, trials, entitlement enforcement, free/pro limits, or paywalls.
- AI diagnosis, health-risk prediction, medication advice, treatment recommendations, or claims that replace a veterinarian.
- Online veterinarian service, GPS tracking, social community, training courses, commerce, insurance, advertising, or data sale.
- External sitter accounts, permanent public links, or time-limited Sitter Pass in the initial handoff phase.
- Firebase Storage and health-photo upload in the first health-timeline release.
- Physical Android release acceptance, App Store submission, remote deployment, production data migration, or SwiftUI deletion without later authorization.

### Protected behavior

- Household creation/invite/join and session restoration.
- Realtime member, household, routine, and task synchronization.
- Daily and selected-weekday routine derivation in household timezone.
- Self-claim, open assignment, direct assignment, accept/decline/cancel, and assignee-only completion.
- Transaction-protected state transitions, `revision + 1`, historical snapshots, and server-authored action times.
- Today, Calendar, Activity, profile editing, English/Japanese, and actionable error states.
- Existing data remains readable; missing newer fields use deliberate compatibility defaults rather than dropping documents.

## Domain invariants

1. A user may read or write household data only while represented by a member document for that household.
2. A task transition is accepted only from the current server state and advances `revision` exactly once.
3. Historical display names and task/medication snapshots do not change after later profile edits.
4. A routine or medication occurrence has a deterministic identity derived from its schedule and household-local date/time.
5. Pet archive hides the pet from new scheduling but preserves historical tasks, medication events, and health records.
6. Medication responsibility and medication outcome are independent dimensions.
7. An occurrence has at most one terminal medication outcome: `administered` or `skipped`.
8. No client may fabricate completion actor or trusted action time.
9. Offline or pending medication writes never display as confirmed outcomes.
10. Reports reconcile planned, administered, late, skipped, and unresolved counts without changing historical denominators when a schedule is edited.
11. Doctor-facing reports show only captured source values; missing water, medication, health, or photo data is labeled missing and is never inferred.
12. Health v2 records preserve the household-local date and timezone used at capture; water reporting distinguishes `singleIntake`, `localDayToDate`, reserved `fullLocalDay`, and Health v1 `legacyUnknown` values and never double-counts mixed bases.

## Primary user flows

### Existing collaboration

1. Caregiver A creates a household and pet and receives an invite code.
2. Caregiver B joins and both devices show the same roster.
3. A creates a one-time or recurring task and assigns B or opens it to the household.
4. B accepts/claims and completes the occurrence.
5. A sees the final caregiver and server-authored time without manual refresh.

### Multi-pet

1. A adds a second pet.
2. A creates care for one selected pet.
3. Today, Medications, Calendar, Health, and Activity default to all active pets on both devices; an explicit pet filter narrows every content tab consistently without changing stored care.
4. Archiving a pet prevents new plans but keeps history accessible.

### Safe medication

1. A creates a medication and one or more schedule times for a selected pet.
2. The due occurrence appears for all household members with dose and instructions.
3. One caregiver records administered or skipped with a reason.
4. A concurrent or stale second action is rejected and refreshed to the server result.
5. The event contributes once to history and later summaries.

### Health, handoff, and summary

1. A records structured health observations for a selected pet.
2. B sees the same pet-scoped timeline.
3. A maintains household handoff information.
4. A chooses 7 or 30 days and receives a reconciled, non-diagnostic summary suitable for household review and explicit sharing.

## Acceptance contract

### Migration and parity

| ID | Scenario / precondition | Action | Observable expected result | Verification | Status / evidence |
| --- | --- | --- | --- | --- | --- |
| AC-001 | Clean install, no session | Create a household | Household, first member, legacy-compatible first pet, and invite are created; relaunch restores the session | Widget/integration + real Firebase | Not run |
| AC-002 | Household exists on A | B joins with invite | Both clients show the same household and members without manual refresh | Two emulator clients + two iPhones | Not run |
| AC-003 | One-time, daily, selected-weekday, and urgent tasks exist | Navigate Today/Calendar | Correct occurrences appear on correct household-local dates with category/priority preserved | Unit + widget + timezone integration | Not run |
| AC-004 | Unclaimed task | Self-claim, direct request, or open request | Both clients show the valid request/assignee state and trusted server time | Repository integration + two clients | Not run |
| AC-005 | Direct/open request exists | Accept, decline, or cancel with authorized/unauthorized member | Authorized transition succeeds; unauthorized/stale action fails with actionable UI and refreshed state | Rules + repository + widget | Not run |
| AC-006 | Claimed task | Assignee and non-assignee attempt completion | Only current assignee completes; both clients show actor/time once | Rules + concurrent integration | Not run |
| AC-007 | Existing activity and profile data | Rename profile/household and relaunch | Current profile updates sync; historical name snapshots remain unchanged; leaving clears only local session | Model + integration + two clients | Not run |
| AC-008 | English/Japanese selected | Relaunch and traverse core flows | Language persists and core text/date formatting is complete, legible, and unmixed | Widget + visual/device review | Not run |
| AC-009 | Network unavailable or listener fails | Load/mutate/retry | UI distinguishes offline/network/permission/validation/stale-state failures; retry recovers without duplication | Fake repository + emulator fault cases | Not run |

### LT-1 schema, migration, and environment promotion

| ID | Scenario / precondition | Action | Observable expected result | Verification | Status / evidence |
| --- | --- | --- | --- | --- | --- |
| LT1-AC01 | The repository has legacy and canonical data paths but no deployed schema is assumed | Review the canonical schema, legacy matrix, Rules, Functions, codecs, and index artifact | Every path, schema version, write authority, immutable field, legacy mapping, and required index has one consistent documented owner; any target not yet implemented is labeled as such | Contract diff + independent schema review | Local contract and executable paths reviewed; retained-client rollout evidence and remote index inventory remain open |
| LT1-AC02 | Synthetic fixtures cover every applicable migration class and explicitly prove that no `safe-patch` shape is pre-approved when its count is zero | Dry-run, apply, apply again, then rollback in Emulator | Classification counts close exactly; first apply matches the approved plan; second apply writes zero documents; rollback restores semantic fingerprints without exposing sensitive content | Emulator migration tool + fixture receipt | Guarded classifier and exact-path fixture tests pass locally with zero pre-approved `safe-patch` shapes; apply, manifest, second-run, reconciliation, and rollback are not implemented |
| LT1-AC03 | An independently authorized staging project exists | Verify identity and deploy the pinned compatibility artifacts with synthetic data only | Staging uses distinct project/app/Auth/configuration/IAM/App Check/provider identities; production configuration/data is rejected; required indexes are ready and notification dispatch remains off | Staging inventory + deployment receipt | Not authorized or run |
| LT1-AC04 | Staging contains canonical, legacy, malformed, conflict, and history fixtures | Run Flutter and retained Swift clients plus member/outsider checks | Both clients preserve protected reads/writes, no document is silently dropped, historical actor/time/revision and report denominators remain stable, and outsider/cross-household access is denied | Two-client/provider integration + reconciliation receipt | Not run |
| LT1-AC05 | A staged migration has created/patched documents and a simulated user writes afterward | Roll back app, Rules, Functions, indexes, and data | Migration-owned unchanged writes roll back; post-migration user changes are detected and never overwritten/deleted; notification dispatch is disabled first | Staging rollback drill | Not run |
| LT1-AC06 | Production state has not been inferred from local files | Request the production read-only inventory gate | Exact project/deployed Rules/Functions/indexes/schema counts are recorded without raw sensitive payloads; unexpected shape stops promotion | Approved read-only provider inspection | Not authorized or run |
| LT1-AC07 | A production dry-run, restricted backup, rollback versions, privacy review, and separate approvals exist | Deploy reader-first compatibility artifacts, then optionally apply the exact bounded backfill | Default rollout rewrites zero documents; any approved backfill is deterministic, preconditioned, manifest-recorded, canaried, reconciled, and idempotent; legacy fields/readers remain | Deployment/data receipts + independent review | Not authorized or run |
| LT1-AC08 | Compatibility deployment and provider/device acceptance pass with dispatch disabled | Request the independent notification-activation gate | Only the approved reminder policy is activated; lock-screen payloads remain non-sensitive; delivery/failure evidence reconciles; activation never implies schema-write authority | Approval record + APNs/FCM device matrix | Not authorized or run |

### Legacy data and multi-pet

| ID | Scenario / precondition | Action | Observable expected result | Verification | Status / evidence |
| --- | --- | --- | --- | --- | --- |
| AC-010 | Legacy household/tasks have `petName` and no `petID`; task may use `pending` | Load Flutter app | A deterministic legacy pet appears and all old tasks/routines/activity remain visible | Legacy fixtures + emulator | Not run |
| AC-011 | Household contains two active pets | Open each household tab, then switch pet filters | Today, Medications, Calendar, Health, and Activity initially show both pets; an explicit filter shows only that pet and both clients agree | Widget + two-client integration | Not run |
| AC-012 | Pet has historical records | Archive pet | No new plan may target it; historical records remain readable and pet can still be selected in history | Rules + integration | Not run |
| AC-013 | Cross-household IDs are supplied | Attempt to reference another household's pet/member | Server rejects the write and no data leaks through get/list | Rules negative tests | Not run |

### Safe medication

| ID | Scenario / precondition | Action | Observable expected result | Verification | Status / evidence |
| --- | --- | --- | --- | --- | --- |
| AC-014 | Valid medication schedule with multiple times/days | Save plan and view dates | Deterministic dose occurrences appear once for the correct pet and household-local times | Unit + repository integration | Not run |
| AC-015 | Scheduled or overdue occurrence | Record administered | Exactly one terminal event stores trusted actor/time and dose snapshot; all clients update | Transaction test + two clients | Not run |
| AC-016 | Scheduled or overdue occurrence | Record skipped and reason | Exactly one skipped event is shown distinctly from administered/completed and included in history | Transaction + widget | Not run |
| AC-017 | A and B act on same occurrence simultaneously | Administer/administer or administer/skip | Only one transaction wins; losing client sees who recorded the actual result and does not claim success | Concurrent emulator + two devices | Not run |
| AC-018 | Device is offline or has stale cached occurrence | Attempt medication outcome | App does not show a confirmed result; reconnect refreshes authoritative state and user can act only if still valid | Network fault + device | Not run |
| AC-019 | Schedule is edited after prior occurrences | View historical events/report | Past snapshots and planned denominator remain stable; future occurrences use the new schedule version | Unit + migration/report integration | Not run |

### Notifications, health, handoff, and reports

| ID | Scenario / precondition | Action | Observable expected result | Verification | Status / evidence |
| --- | --- | --- | --- | --- | --- |
| AC-020 | Medication remains unresolved | Wait through due, +15m, +30m | Intended recipients receive each level once; administered/skipped cancels later notifications | Function tests + real APNs/FCM device | Not run |
| AC-021 | Notification permission denied/token refreshed/app killed | Trigger reminder and recover settings | UI exposes status and recovery; valid tokens receive non-sensitive notification without duplicates | Real iPhone; Android emulator where possible | Not run |
| AC-022 | Health records for two pets | Create and filter records | Other client sees the record in the correct pet timeline; cross-pet/household data never mixes | Rules + two-client integration | Not run |
| AC-023 | Handoff details contain care and emergency information | View/update household handoff | Members see current household-scoped information; non-members cannot access it | Rules + widget/integration | Not run |
| AC-024 | 7/30-day range contains planned and terminal events | Generate summary | Counts reconcile and actor/times match source events; summary states it is not medical advice | Golden fixtures + report integration | Not run |
| AC-025 | User explicitly shares report | Use system share/PDF | Shared output matches in-app data, contains only selected pet/range, and is not uploaded automatically | Golden PDF + visual/device review | Not run |

### Household dashboard UI/UX refresh

| ID | Scenario / precondition | Action | Observable expected result | Verification | Status / evidence |
| --- | --- | --- | --- | --- | --- |
| AC-029 | Two active pets have care, medication, health, and activity | Open each household tab and use pet filters | All pets appear by default across Today, Medications, Calendar, Health, and Activity; records retain household-local ordering and identify the pet with a distinct accessible avatar/name | Widget + visual review | Pass at local fake/demo layer; Phase 9 evidence in `PLANS.md` |
| AC-030 | Tasks are unclaimed, requested, claimed, and completed | View and act on task cards | Self-claim, household request, and direct assignment use one visual system; responsibility is prominent and remains distinct from confirmed completion | Widget + existing mutation tests | Pass at local widget layer; Phase 9 evidence in `PLANS.md` |
| AC-031 | The visible month contains care on some dates | Browse Calendar and select a marked date | Scheduled dates have category markers; the selected date shows a chronological compact agenda with pet identity | Unit/widget + timezone visual review | Pass at local widget/demo layer; Phase 9 evidence in `PLANS.md` |
| AC-032 | Care, medication, and health events plus 7/30-day source data exist | Open Activity and switch report range | Timeline states exactly what happened, for which pet, by whom, and when; report foregrounds care completion and medication adherence without changing reconciled source counts | Widget + report fixtures + visual review | Pass at local widget/demo layer; Phase 9 evidence in `PLANS.md` |
| AC-033 | Clean install and an existing saved-language install | Open Profile, inspect household settings, and relaunch | Invite code, language, notifications, and handoff are in Profile; new installs default to Japanese while an existing saved English/Japanese choice persists | Widget + locale repository + visual review | Pass at local widget/demo layer; Phase 9 evidence in `PLANS.md` |

### Medication, medical-record, and report refinement

| ID | Scenario / precondition | Action | Observable expected result | Verification | Status / evidence |
| --- | --- | --- | --- | --- | --- |
| AC-034 | Dog, cat, and rabbit pets have multiple care items | Open Today and pet filters | Each species has an accessible animal symbol; each pet keeps one deterministic color across its care cards; the task icon describes the care action and does not repeat the pet symbol | Codec/Rules + widget + visual review | Pass at local codec/Rules/widget/demo layer; Phase 10 evidence in `PLANS.md` |
| AC-035 | Japanese is selected and demo/system content is present | Traverse Today, Medications, Health, Activity, and Profile | System and seeded demo copy is Japanese without stray English care, dose, instruction, or health-detail labels; user-entered content is preserved verbatim | Widget + visual language audit | Pass at local seeded-content/widget/demo layer; Phase 10 evidence in `PLANS.md` |
| AC-036 | Active and stopped medication records plus schedule versions exist | Open the Medication archive and a medication detail | Today status remains visible, while active and historical medicines are separated; detail identifies pet, medication name, recorded purpose, possible-side-effect notes, dose, frequency, timing, instructions, and a clearly unavailable photo slot without changing confirmed outcome semantics | Repository/function + widget + visual review | Pass at local repository/function/widget/demo layer; Phase 10 evidence in `PLANS.md` |
| AC-037 | Notification permission has any status | Open Profile notification settings | UI states the exact policy: medication due/+15/+30 is implemented, urgent/assignment realtime alerts are planned, routine care is not realtime, and lock-screen content stays non-sensitive | Widget + visual review; provider remains AC-020/021 | Pass for local policy UI; provider/device delivery remains under AC-020/021 |
| AC-038 | Medical records include visits, prescriptions, mood, observations, water, and missing photos | Open Health and add/view records | Health reads as the complete pet medical record, captures structured water ml, visit/diagnosis/prescription/veterinarian instructions and mood, and exposes photo affordances without claiming upload or sync | Rules + repository + widget + visual review | Pass at local Rules/repository/widget layer; secure photo sync remains deferred |
| AC-039 | A 7/30-day report contains exact care, medication, water, and health sources | Open Activity and render/share report | In-app and PDF output list exact captured items, medication names/doses/outcomes, water source values, only basis-safe daily summaries allowed by LT2-AC02, dated health observations, and explicit missing-data text; no diagnosis or inferred value appears | Report fixtures + PDF text/render + visual review | Basis-safe local report/PDF implementation is under consolidated verification; system share/device receipt remains open |
| AC-040 | Routine care tasks and medication doses are due for one or more pets today | Open Today and change the pet filter | Care and medication appear in one household-time chronological list with pet identity; medication keeps its server-confirmed administered/skipped controls and is not duplicated in a separate Today section | Widget + Android visual review | Pass at local widget/Android-emulator layer; Phase 12 evidence in `PLANS.md` |
| AC-041 | A pet has no daily health check-in for the current household-local day | Open Health, complete the daily template, and return on the same day | Health prompts for water, appetite, urination, stool, energy, and mood/behavior using qualitative change-from-usual values plus optional measured water and notes; the completed day is visible once, tomorrow remains unrecorded, photo sync is not claimed, and no population-wide numeric normal is inferred | Repository/Rules + widget + timezone visual review | Callable idempotency and local two-client race implementation exist; final consolidated Emulator rerun and remote photos remain open |

### LT-2 daily health and water-source correctness

| ID | Scenario / precondition | Action | Observable expected result | Verification | Status / evidence |
| --- | --- | --- | --- | --- | --- |
| LT2-AC01 | Two caregivers submit the same pet's daily check-in near household midnight, including retry, stale client, and DST cases | Create through the canonical Health v2 server path | Exactly one record whose ID is SHA-256 of the pet ID, a literal pipe separator, and `recordedLocalDate` exists; `recordedLocalDate` is derived from the server observation time using the persisted `recordedTimeZoneIdentifier`; identical retry returns the authoritative record and a different payload returns a visible conflict | Function/Rules tests + two-client Emulator/staging race + timezone fixtures | Trusted-time writer, legacy-daily conflict guard, retry, timezone-change authoritative response, local two-client race, and consolidated local gates pass; staging/device evidence remains open |
| LT2-AC02 | A date contains v2 `singleIntake`, `localDayToDate`, reserved `fullLocalDay`, missing water, and Health v1 `legacyUnknown` observations | Render Health, Activity, and 7/30-day PDF/report | Source records remain individually visible; `singleIntake` values are summed only when no overlapping day-to-date/full-day value is selected; `localDayToDate` is labeled as partial-day and never added to same-day intakes; `fullLocalDay` supersedes other same-day values; missing and `legacyUnknown` values are labeled/excluded rather than inferred; all outputs reconcile exactly | Report fixtures + repository/widget + PDF text/render + two-client provider data | Local reducer, labels, source-only exclusions, malformed-source warning, rendered PDF, and consolidated local gates pass; third-party receiver and provider-data verification remain open |

### LT-3 five-destination information architecture and accessibility

| ID | Scenario / precondition | Action | Observable expected result | Verification | Status / evidence |
| --- | --- | --- | --- | --- | --- |
| LT3-AC01 | The app runs at 320–430 logical pixels in English or Japanese | Traverse primary navigation | Exactly five destinations—Today, Calendar, Updates, Records, and Profile—remain visible without wrapping, clipping, overflow, or horizontal scrolling; every retained feature is reachable within two taps | Widget size matrix + visual review | Local five-tab and two-tap reachability matrix passes; physical-device visual review remains open |
| LT3-AC02 | Care, medication, health, collaboration, and report data exist | Traverse the five destinations and their secondary surfaces | Today contains current action; Calendar contains plans; Updates contains collaboration changes; Records contains medication, health, factual history, and reports; Profile contains household/device settings; selected pet and unsaved form state are not silently reset | Widget state/navigation tests | Local navigation, Records secondary state, pet-filter, and form-state tests pass |
| LT3-AC03 | Long Japanese household, pet, caregiver, task, and medication text exists | Open Today at 320×568 and 390×844 with text scale 1.0, 2.0, and 3.0 | No RenderFlex error, clipping, bottom-bar obstruction, or inaccessible action; pet, time, responsibility, status, and primary action remain readable; touch targets are at least 44×44 and status is not color-only | Widget surface matrix + semantics/visual review | Complete 320×568/390×844 × English/Japanese × 1.0/2.0/3.0 long-content matrix passes locally; physical visual review remains open |
| LT3-AC04 | Profile and edit forms show errors with the software keyboard open | Scroll, edit, fail, retry, cancel, and save | Every section, field, error, Save, and Cancel remains reachable; duplicate submit is prevented; failure preserves input and identifies an actionable next step; permission status and reminder policy are distinct | Widget form/failure tests + visual review | Local keyboard, scroll, Cancel, failure-preservation, retry, and duplicate-submit tests pass |
| LT3-AC05 | VoiceOver/TalkBack semantics and both locales are enabled | Traverse navigation, care rows, medication rows, empty/error states, and controls | Reading order follows visual order; navigation announces label and selection; rows announce pet, time, action, and status; decorative icons are excluded; copy distinguishes Updates, OS notifications, and long-term records; contrast meets 4.5:1 for ordinary text and 3:1 for large text/non-text controls | Semantics tests + contrast/locale audit | Local nav/care/medication/empty/error/control semantics and exact-surface contrast tests pass; physical VoiceOver/TalkBack remains open |
| LT3-AC06 | Existing protected care, calendar, health, report, and locale fixtures are loaded | Run regression after information-architecture changes | Server-confirmed medication outcomes, shared pet filter, Monday-first calendar, malformed-source warnings, exact report/water counts, and language persistence do not regress | Consolidated Flutter/Rules/Functions + builds | Flutter 219/219, Rules 62/62, Functions 35/35, Android debug, and clean-mirror iOS Simulator build pass locally |

### LT-4 collaboration ledger, Updates, and factual Records separation

| ID | Scenario / precondition | Action | Observable expected result | Verification | Status / evidence |
| --- | --- | --- | --- | --- | --- |
| LT4-AC01 | A member requests, accepts, declines, cancels, completes, or records another supported collaboration transition | Perform, retry, race, reject, and replay the mutation | Each accepted transition creates at most one immutable event using a deterministic source/revision/transition identity with server-authored actor/time and historical pet/task snapshots; rejected or stale mutations create none; members may read but clients cannot create, update, or delete events | Functions/Rules/repository concurrency tests | Deterministic trigger replay/conflict, marker transitions, immutable ledger, and member-only Rules pass locally; retained marker-free clients remain explicitly incomplete |
| LT4-AC02 | Events span multiple pages, equal timestamps, offline/cache state, and two members' read positions | Open and page Updates, reconnect, and mark read | Events use trusted time plus deterministic tie-break ordering, never duplicate across pages, expose loading/offline/permission/incomplete recovery, and use a per-member cursor; legacy absence is labeled as pre-Updates history rather than fabricated | Repository/widget/two-client tests | Opaque raw pagination, malformed continuation, cache/error states, per-member monotonic cursor, conservative pending/error UI, and two-client Android emulator convergence pass; real offline/provider devices remain open |
| LT4-AC03 | One care completion or medication outcome can appear in Updates and factual Records | Compare Updates, timeline, 7/30 report, and PDF | Updates answers who changed what; factual Records answers what happened to the pet; both reference the authoritative source, while report denominators, water reduction, and health facts remain source-derived rather than ledger-derived; assignment/profile events never enter health/care denominators | Projection/reconciliation fixtures + PDF/widget review | Local task projection and Records/report/PDF reconciliation fixtures pass; ledger remains non-authoritative and excluded from report denominators |
| LT4-AC04 | Notification permission is denied and an event contains potentially sensitive source data | Open Updates and inspect notification/log boundaries | In-app Updates remains usable; lock-screen summaries stay non-sensitive; ledger/log/analytics do not copy health notes, dose details, tokens, image URLs, or report bodies; notification delivery never becomes the audit source | Privacy tests + device/provider boundary review | Local permission-independence and medication-title/dose redaction tests pass; APNs/FCM and lock-screen device review remain open |

### LT-5 consented responsibility transfer and handoff sessions

| ID | Scenario / precondition | Action | Observable expected result | Verification | Status / evidence |
| --- | --- | --- | --- | --- | --- |
| LT5-AC01 | A canonical claimed task has no pending transfer | Current assignee releases responsibility | Task atomically returns to the existing unclaimed shape with trusted actor/time and revision + 1; non-assignee, stale, terminal, or pending-transfer attempts change nothing and create no event | Callable/Rules/repository tests | Local pass: callable, repository, ledger, and negative authority fixtures cover release, stale state, retry, and pending-transfer rejection |
| LT5-AC02 | A is responsible and asks B to take responsibility | B accepts or declines; A cancels | A remains responsible until B accepts; acceptance atomically moves responsibility to B; decline/cancel leaves A responsible; self, outsider, third-party, stale, and duplicate actions fail safely | Functions race + two-client tests | Local pass at Functions/repository/widget layers; a real Flutter two-client run remains open |
| LT5-AC03 | B asks to take over a task currently owned by A | A accepts or declines; B cancels | No member can unilaterally take over; A remains responsible until explicit acceptance; consent, actor, counterparty, request ID, and trusted time are unambiguous | Functions/Rules/widget tests | Local pass: consent actor, counterparty, cancellation, privacy, and no-optimistic-success fixtures pass |
| LT5-AC04 | Completion, release, transfer acceptance, and a second proposal race on one task revision | Submit concurrently | Exactly one authoritative transition wins; losers receive the current task/transfer result and cannot overwrite it; completion never occurs optimistically | Concurrent Emulator + repository tests | Local pass: isolated Firestore concurrent completion/acceptance and proposal races produce one authoritative winner |
| LT5-AC05 | A mutation times out, reconnects, restarts, or retries | Retry the same client mutation ID and then reuse it with a different payload | Identical retry returns the authoritative result without duplicate revision/event; payload reuse is rejected; offline UI never claims success | Receipt/restart/fault tests | Local pass: exact receipt retry, payload-bound IDs, editable-offer signatures, offline recovery, and server-confirmed UI fixtures pass |
| LT5-AC06 | Retained clients and malformed/legacy tasks coexist | Read and attempt LT-5 actions | Existing unclaimed/claimed/completed readers remain compatible; unsafe legacy tasks stay visible but immutable; a retained writer cannot bypass a pending transfer or leave it dangling | Legacy fixtures + Rules matrix | Local pass: retained task shapes still decode; Rules block direct writes during pending authority; orphan/malformed source-pointer pairs fail closed |
| LT5-AC07 | Handoff template revision N exists and A offers a household-wide coverage window to B | B accepts and the template later becomes N+1 | A server-owned session references an immutable version of template N; only B accepts; later template edits do not alter the accepted session | Functions/repository/two-client tests | Local pass at Functions/repository/widget layers: pointer, session, and immutable pinned version are strictly joined; current N+1 is visibly separate from pinned N; real two-client run remains open |
| LT5-AC08 | A session is offered or accepted | Recipient declines, creator cancels, participant closes, or owner recovers a stuck offered/accepted session | Only the authorized transition succeeds; terminal sessions never reopen; owner recovery cancels offered or closes accepted but cannot rewrite content or source outcomes | Functions/Rules/widget tests | Local pass: participant transitions, owner recovery, terminal immutability, cache/error authority gates, and close-out source counts pass |
| LT5-AC09 | Two offers or terminal actions race; supplied template revision is stale | Submit concurrently | At most one offered/accepted session is active per household; one transition wins; stale content is never silently substituted | Transaction/race tests | Local pass: isolated transaction races, expired/stale offers, canonical pointer cardinality, and orphan active-session rejection pass |
| LT5-AC10 | Session data includes care instructions and phone numbers | Read as member/outsider and inspect ledger, receipts, notifications, and logs | Members may read the authoritative version/session; outsiders and cross-household users cannot; free text and phone data never enter ledger, receipts, push, inbox, analytics, or logs | Rules/privacy tests | Local pass: member/server-write Rules and strict redacted v2 ledger/receipt fixtures pass; no provider or remote log inspection has run |
| LT5-AC11 | Two clients observe task transfer and handoff session lifecycle | Propose, accept/decline/cancel/close, disconnect, and reconnect | Both clients converge on source task/session and deterministic ledger projections; cache/offline/stale states remain explicit | Two-client Emulator + device follow-up | Partial: deterministic repositories/widgets and multi-actor Functions pass; clean Flutter two-client Emulator and physical-device convergence remain open |
| LT5-AC12 | A member chooses to leave a household containing sensitive handoff data or an active medication responsibility | Revoke membership or disconnect only this device | Product copy distinguishes the two actions; disconnect first disables the current installation token and preserves the session on failure; true leave removes Rules membership and disables household notification registrations only after task/session and still-active medication reminder responsibilities pass; owner and unresolved obligations receive a safe blocking explanation | Callable/Rules/widget/two-client tests | Partial after LT6 contract review: existing disconnect, owner/task/session blockers, lease drain, 501-token pagination, crash recovery, rejoin race, and repeat leave fixtures pass; active medication-responsibility blocker and real provider/device verification remain open |

### LT-6 responsibility-routed reminders, private inbox, and recovery

| ID | Scenario / precondition | Action | Observable expected result | Verification | Status / evidence |
| --- | --- | --- | --- | --- | --- |
| LT6-AC01 | OS permission, CoPaw preference, installation readiness, and provider evidence vary independently | Open notification settings | UI reports each layer separately and never equates OS authorization or token registration with verified delivery | Repository/widget matrix | Local pass: strict repositories and widget transitions preserve the four independent layers, stale evidence, retry, and not-configured states; real provider evidence remains open |
| LT6-AC02 | Medication is claimed/unclaimed/terminal and members have explicit backup preferences | Generate due/+15/+30 reminder intents | Claimed reminders route to the responsible member and opted-in backups at the documented levels; unclaimed reminders use explicit eligible members; terminal sources create no later intent | Pure resolver + Functions fixtures | Local pass: claimed/unclaimed/backup/terminal routing, immutable effective versions, replacement/stop boundaries, and source reconciliation pass isolated Functions fixtures |
| LT6-AC03 | One installation rotates tokens; a token is duplicated or converges after materialization; a user has two installations; schedulers race; or a recipient leaves/rejoins | Create and dispatch one semantic intent | User intent identity includes source/level/recipient membership epoch; one-time materialization freezes stable installations; a versioned-HMAC endpoint binding serializes later token convergence, so rejoin/rotation cannot reuse or resend while two distinct endpoints may each receive once | Functions concurrency/rotation/epoch/endpoint-binding tests | Local pass: epoch identity, manifest recovery, rotation/convergence, HMAC binding, leases, leave/rejoin, and ambiguous provider outcomes pass fake-provider Functions tests |
| LT6-AC04 | Inbox spans pages, cache, malformed data, permission failures, and two members' read positions | Open Reminders, page, retry, and mark read | Each member has a private recoverable inbox and monotonic cursor; unread remains conservative; inbox state never changes task, medication, ledger, Activity, or reports | Rules/repository/widget/two-client tests | Local pass: Rules privacy, raw 21-item paging, opaque continuation, exact failed-cursor retry, malformed/cache/error handling, and conservative cursor convergence pass deterministic tests; real two-client run remains open |
| LT6-AC05 | A generic notification is opened foreground, background, killed, duplicated, offline, expired, or under the wrong household | Resolve the typed route after session restoration | Only a validated member/item opens Reminders; failure preserves a retry or returns to Today with actionable generic copy; no click performs care, medication, or acceptance actions | Interaction fake + widget/integration | Local pass with provider-neutral lifecycle fakes: foreground banner, delayed initial/open races, persisted route CAS, wrong-household/expired recovery, and direct server load are covered; real OS/provider lifecycle remains open |
| LT6-AC06 | Quiet hours and summaries cross midnight or DST in the household timezone | Resolve availability and digest windows | Household timezone is authoritative; assignment/summary alerts respect preferences; medication and urgent reminders are not silently delayed; burst events are coalesced rather than spammed | Timezone/burst fixtures | Local pass: timezone/DST, quiet-hour, burst/daily digest, bounded recovery, cancellation, and policy/membership races pass deterministic Functions tests |
| LT6-AC07 | Fixtures contain pet, medication, dose, health, phone, handoff text, token, image URL, and report content | Inspect payload, inbox, delivery, IDs, errors, and logs | None of the sensitive values are copied; dispatch remains project-bound and default off; providerAccepted never means delivered/read/completed | Privacy tests + provider boundary review | Local pass: fixed generic payloads and server-only notification state pass privacy/Rules review; both v2 gates remain absent/off and no real provider was invoked |
| LT6-AC08 | Preferences and Reminders render on compact English/Japanese surfaces at large text | Traverse and edit | No overflow or inaccessible action; switches, route reason, unread, loading/error/retry, and status semantics remain explicit | Widget/semantics/contrast matrix | Local pass: 12 width/locale/text-scale cases, full-shell compact traversals, 44-point actions, exact semantics, provider transitions, repair/retry, and actual Material surface contrast pass |
| LT6-AC09 | Explicitly authorized staging and physical devices have APNs/FCM configured | Run permission, rotation, foreground/background/killed click, collapse, TTL, invalid-token, and ambiguous-acceptance matrix | Provider/device observations reconcile with intents and deliveries without claiming exactly-once display | APNs/FCM physical-device matrix | Not authorized or run |

### LT-7 repeatable local Firebase and two-client acceptance

LT-7 is local-only acceptance infrastructure. It does not authorize migration
apply/rollback, staging or production access, deployment, App Check, APNs/FCM,
or physical-device claims. A "second migration run" in this phase means a
second read-only dry-run over the same approved synthetic Emulator scope; it
must not be described as apply idempotence.

| ID | Scenario / precondition | Action | Observable expected result | Verification | Status / evidence |
| --- | --- | --- | --- | --- | --- |
| LT7-AC01 | Local Firebase commands run under Node/JDK/project variations | Start Emulator, Rules, Functions, migration, export, or restore entry points | Non-Node-22 or missing/old-JDK paths fail before opening ports; every success pins `demo-copaw` and loopback Emulator hosts without CLI-alias, ADC, or remote fallback | Environment receipt + expected-failure tests | Accepted: `npm run test:lt7` 16/16 |
| LT7-AC02 | The local Functions source has evolved across phases | Import and discover exports under Node 22 | Exactly the 24 named LT7 exports load with no missing/extra export, discovery timeout, or runtime-major warning | Exact manifest test + Functions discovery log | Accepted: 24/24 exports discovered under node@22 with no runtime-major warning |
| LT7-AC03 | Auth, app storage, and backend data start clean | Launch two independent Flutter OS processes with separate app sandboxes; A creates and B joins; kill and relaunch each | A and B receive different anonymous UIDs, retain only their own UID/session across restart, and converge on one household/member/source truth; a second `FirebaseApp` inside one process is not sufficient evidence | Two process/device IDs + content-free UID/member receipt + visible state | Partially accepted: bootstrap and reconnect converged across two iOS Simulator processes; source and offline blocked by the empty-list Rules defect |
| LT7-AC04 | A versioned synthetic canonical-plus-legacy local dataset is loaded | Fingerprint, export Auth/Firestore, mutate a sentinel, stop, import, and reconnect | Restored Auth UID/path/schema/type counts and semantic fingerprints equal baseline; the mutation is replaced by the exported baseline; historical actor/time/revision, report, and water semantics remain unchanged | Export manifest + before/mutated/restored reconciliation | Accepted: `scripts/lt7_snapshot_acceptance.sh` reconciled twice, 23 sentinels, out-of-schema and in-schema drift both detected |
| LT7-AC05 | A versioned migration-scope synthetic fixture is present in `demo-copaw` | Run the read-only migration classifier twice and reconcile before/after | Both receipts are identical and content-free; each in-scope source is in exactly one of five classes; out-of-scope canonical paths are counted separately; planned/applied writes remain zero; Emulator fingerprint is unchanged; apply, non-Emulator, non-`demo-copaw`, or missing-host attempts fail closed | Receipt diff + zero-write/fingerprint tests | Accepted: two identical content-free receipts, zero planned/applied writes |
| LT7-AC06 | A committed shared iOS-local scheme/config targets `main_emulator.dart` | Build and launch on iOS Simulator | The local bundle contains no production plist or APNs entitlement, disables Messaging auto-init/AppDelegate proxy, never registers for remote notifications or writes a token, and routes Auth/Firestore plus the `asia-northeast1` Functions instance only to loopback | Static scheme/build-product/codesign checks + runtime receipt | Accepted after fixing three defects that prevented the local entry point from ever running an integration test |
| LT7-AC07 | Two local clients encounter offline, restart, Emulator import/restart, stale cache, and retry races | Mutate authoritative state from the other client, reconnect, and resolve | Cache/error state never claims a medication/care success; persistence remains disabled; both clients refetch and converge; medication outcome mutation identity/fingerprint and Health mutation/record identity survive restart and clear only after authoritative resolution; collaboration source/event counts and listeners do not duplicate | Two-client state timeline + source/event counts | Unverified: depends on the blocked source and offline phases |
| LT7-AC08 | Device and household timezones differ and legacy/canonical fixtures coexist | Cross Tokyo midnight and New York DST gap/fold; load the frozen legacy matrix | Household timezone remains authoritative; routine gap materialization and medication `dstPolicy=reject` reject invalid wall times; notification quiet-time gap resolves to the first valid instant and fold to the first occurrence; Health maps trusted instants to persisted local dates; invalid timezone blocks derived writes with repair state; legacy states remain visible and malformed/partial/dangling sources are diagnostic rather than silently repaired or dropped | Repository/UI counts + timezone/legacy/report fingerprints | Accepted for the notification quiet gap/fold, Tokyo midnight, malformed-zone, and medication reject cases via `npm run lt7:timezone`; routine ambiguous-hour behavior is locked as an accepted difference |

LT7-AC02 freezes these exact exports: `archivePet`,
`createMedicationPlan`, `replaceMedicationPlan`, `stopMedicationPlan`,
`mutateMedicationOccurrence`, `createDailyHealthCheckIn`,
`createHealthRecord`, `setHouseholdNotificationPreferences`,
`resetMalformedNotificationPreferences`, `resolveNotificationInboxRoute`,
`expireNotificationInbox`, `recoverNotificationDigests`,
`recoverNotificationManifests`, `dispatchNotificationV2`,
`generateMedicationNotificationIntentsV2`,
`onTaskNotificationSourceWritten`, `onTransferNotificationSourceWritten`,
`onHandoffNotificationSourceWritten`,
`onMedicationOccurrenceNotificationSourceWritten`,
`recordTaskCollaborationEvent`, `mutateTaskResponsibility`,
`mutateHandoffSession`, `leaveHousehold`, and `mutateRoutineOccurrence`.

The LT7-AC04 preservation seed must include synthetic sentinels for
household/member/invite/pet/task/routine; medication plan/version/occurrence;
Health v1/v2; handoff template/version/session; responsibility transfer and
active pointer; collaboration ledger/read cursor; and notification preference,
inbox/read cursor/delivery. LT7-AC05's five-class denominator includes only the
migration-source paths enumerated by `docs/legacy-firestore-contract.md` and
`docs/FIREBASE_PROMOTION_MIGRATION.md`. Other current canonical paths are
reconciled by LT7-AC04 but reported as `excludedByScope`; they are never
misclassified as malformed legacy input.

### Release, privacy, and platform

| ID | Scenario / precondition | Action | Observable expected result | Verification | Status / evidence |
| --- | --- | --- | --- | --- | --- |
| AC-026 | Clean worktree and dependency cache | Analyze, test, build iOS/Android | Required static/tests/build gates pass from declared environment; environment is visibly correct | CI-equivalent local commands | Not run |
| AC-027 | Sensitive feature data exists | Inspect logs, analytics, notification, Git diff/history | No pet/medication/health content, device token, secret, local username, or absolute path leaves allowed scope | Privacy/secret review | Not run |
| AC-028 | Two physical iPhones use real Firebase | Run complete create/join/assign/medication/restart/reconnect loop | Both devices converge on one authoritative state with observed provider evidence | Independent acceptance runner | Not run |
| AC-042 | A developer has no production Firebase client configuration | Start the local suite and launch `main_emulator.dart` | The full app connects only to `demo-copaw` Auth, Firestore, and Functions; Android/iOS use the correct host bridge, Firestore cache is disabled, push registration is unavailable, and an unconfigured service cannot fall back to production | Config tests + emulator startup + Android app launch + two-client SDK integration | Pass at local Android/emulator layer; real provider/device evidence remains under AC-020, AC-021, and AC-028 |

## Interface contracts

- The canonical target is documented in `docs/firestore-schema.md`; executable current behavior is expressed by `firestore.rules`, `tests/firestore.rules.test.mjs`, Functions, Swift models/service behavior, and Dart codec/repository contract tests. A mismatch remains open until independently resolved and tested.
- New `pets`, medication, health, handoff, notification-token, and report-source schemas must be added to Rules and tests in the same phase as their first write path.
- Firebase UID remains the member identity for this Beta. No UI may imply uninstall/other-device account recovery until an account-linking phase is implemented.
- SwiftUI and Flutter coexist during migration. Flutter dual-reads legacy fields; new schema rollout must not make the retained Swift reference app crash before retirement is approved.

## Release evidence required

- Automated: Dart model/state/unit/widget/integration tests; Firestore Rules positive and negative tests; function tests when functions exist; formatting; analysis; iOS Simulator and Android builds.
- Visible UI: clean install, create/join, task lifecycle, pet filtering, medication terminal outcomes, error/retry, empty/loading, English/Japanese, accessibility and layout review.
- External: real Firebase project identity, two physical iPhones, APNs/FCM for notification claims, and a physical Android only if later promoted to release scope.
- Data: five-class legacy fixture dual-read, migration dry-run counts, restricted backup, per-write rollback manifest, second-run idempotence, and before/after semantic reconciliation before any production migration.
- Privacy/security: Rules deployed-project confirmation, notification redaction, log/analytics review, ignored configuration audit, and exact outgoing Git scope review before any push/deploy.

## Known unverified dependencies

- Android local emulator development no longer needs production Firebase client configuration. Real Android provider acceptance still lacks the ignored `google-services.json`. The 2026-08-16 iOS-local run required an isolated build with the ignored production plist excluded; a dedicated reproducible iOS-local scheme is still open.
- The Rules Emulator runs with Android Studio's bundled JBR. Under host Node 24 the Functions port opened but source discovery timed out; under Node 22 all callable definitions loaded. The interactive start script already rejects non-Node-22 runtimes, but Rules, Functions, migration, export, and restore entry points do not yet share one repository-pinned Node 22 gate and discovery receipt.
- Firebase Installations is not emulated. The iOS-local build remained on `demo-copaw` but still made a failed Installations request, so it is production-isolated rather than fully offline.
- FlutterFire tooling and Android emulator execution are confirmed locally; production App Check, FCM/APNs, deployed Rules/Functions, and Android client configuration remain unverified.
- No physical phone is currently connected; physical-device acceptance is necessarily pending.
- Deployed Firestore Rules and live Firebase data shape have not yet been inspected.

## Deferred decisions

| Decision | Default for this build | Revisit before |
| --- | --- | --- |
| Recoverable sign-in | Anonymous Auth retained | Production health-data release |
| Physical Android acceptance | Emulator/build only | Android release candidate |
| Health photos | Show local attachment affordance; defer Firebase Storage and cross-device photo sync | Dedicated media/privacy phase |
| External Sitter Pass | Internal handoff only | New external-role phase |
| PDF | After in-app reconciliation | Report release |
| Monetization boundary | No gating | Separate future pricing project |
