# Feature Spec: FlashApp 1.0 App Store hardening

Status: Approved
Owner: product owner / orchestrator
Date: 2026-08-19
Run ID: `flash-app-store-v1`

## Grilling Evidence

- Product decisions: `docs/decisions/ADR-006-app-store-v1-contract.md` and
  `docs/decisions/ADR-007-account-scoped-stores.md`
- Source amendments: `flash-up-architecture-brief.md`, `flash-up-implementation-spec.md`
- Intake: `docs/flywheel-runs/flash-app-store-v1/intake.md`
- Context pack: `docs/flywheel-runs/flash-app-store-v1/context-pack.md`
- Live implementation handoff: `specs/flash-app-store-v1/README.md`
- Decision state: approved; account-dependent facts remain explicitly unverified.

## Goal

Turn the existing complete-on-fakes FlashApp surface into an honest App Store 1.0: user
data survives relaunch, remains fully usable offline, synchronizes automatically through
the user's private iCloud database, backs up and restores with media intact, and exposes no
placeholder feature or simulated release claim.

## Problem

The shipping composition root uses `InMemoryLibrary`, Settings reports a simulated sync
state, Groups is visible but unavailable, backup omits media bytes, and release evidence is
limited to development builds. The old Flywheel graph also assumes collaborative sharing
in 1.0 and no longer matches the owner-approved product scope.

## Users

- University students using FlashApp on iPhone, iPad, and the iPad app on Apple Silicon
  Mac, online or offline.
- The owner/release operator who must distinguish verified repository evidence from
  Apple-account actions that still require manual completion.

## In Scope

- One active versioned profile `Private.sqlite` managed by
  `NSPersistentCloudKitContainer`, isolated across Anonymous, Legacy and opaque
  Apple-Account scopes.
- Production persistent repositories for every existing `LibraryRepository` behavior.
- Automatic personal CloudKit sync, account/offline states, remote history, convergence,
  subtle status and retry.
- Non-destructive migration/recovery and original-store preservation.
- A complete versioned backup archive containing supported media bytes; safe idempotent
  merge restore.
- Three-tab 1.0 shell: Today, Library, Settings; no Groups release surface.
- Skippable onboarding and persistent original generalist demo content.
- Direct local-reminder permission UX with actionable denial guidance.
- Privacy/security/dependency/license audit; EN/IT, accessibility, iPhone/iPad/iOS 17+26
  release matrices and evidence scaffolding.
- Internal TestFlight and App Store operations as explicit human gates.

## Out of Scope

- Groups, `CKShare`, invitations, shared database/store, group revisions or moderation.
- Proprietary FlashApp accounts, credentials or authentication backend. Apple Account
  switching is in scope only as an isolated data-routing boundary.
- StoreKit, IAP, subscriptions, trials, paywalls, ads, tracking or third-party analytics.
- Dedicated macOS/Catalyst/Android targets.
- Remote-notification product features unrelated to CloudKit mirroring.
- Pushing, publishing, App Store submission, or claiming human gates PASS without explicit
  owner authorization and evidence.
- Any modification to `assets/emma-avatar/`.

## Product and interface contract

- Price is €2.99 at launch and €4.99 one calendar month after actual launch; this is an
  App Store Connect schedule, never app logic.
- iCloud is quiet reliability rather than the primary marketing claim.
- When iCloud is unavailable, all personal authoring/import/study/backup behavior works
  locally and the status is clear but non-blocking.
- Cold indeterminate identity opens Anonymous, not a cached account library. Sign-out and
  A→B hide the previous profile; no profile is implicitly merged, moved or deleted.
- Production never selects `InMemoryLibrary`; in-memory stores remain preview/test oracles.
- Import is reachable from Library; Statistics is reached from Today.
- Completing or skipping onboarding installs the same demo content idempotently through
  the real repository.
- Valid complete backups restore content, progress and media. Restore never overwrites or
  deletes an existing live UUID and never partially applies an invalid archive.
- Logs and diagnostics never contain card text.

## Data ownership and seams

- `FlashUpDomain` owns portable values, scheduling rules and backup manifest contracts.
- `FlashUpData` exclusively owns Core Data, CloudKit, filesystem media/archive services,
  migration/recovery and persistent `LibraryRepository` behavior.
- `AppEnvironment` is the single production composition root.
- Feature views consume domain/repository contracts and do not import Core Data/CloudKit.
- Exactly one profile `Private.sqlite` is active. Each Anonymous/Legacy/identified profile
  scopes Core Data, media, session, history and recovery together; no shared/Groups store
  exists.
- `CDStudySettings` stores and syncs study limits, appearance and reminder preference/time
  and is included in backup. Active session is an atomic device-local JSON file; onboarding
  flags are device-local `UserDefaults`; neither is synced or backed up. Notification
  authorization is re-read from the operating system.

## Risks and stop conditions

- Never delete/recreate a user store to recover migration or sync.
- Any model change that violates CloudKit schema rules stops the data batch.
- Any restore path that can partially mutate before archive validation stops portability.
- Any release UI backed by a simulated status stops the product batch.
- CloudKit code may be prepared before account activation, but its real-device/schema cells
  remain `HUMAN_REQUIRED`/`UNVERIFIED` and block submission.
- Real A→B behavior is not provable from fixtures. Cross-account inspection during pending
  import/export remains `HUMAN_REQUIRED`; any leakage blocks release and triggers a new
  architecture decision.
- A discovery that needs Groups/shared data to satisfy a 1.0 behavior creates a decision
  request; it is not absorbed into a worker batch.

## Acceptance Criteria

- **AC-01 Persistence:** decks, notes, schedules, logs, settings, trash, sessions and media
  survive process termination and on-disk reopen.
- **AC-02 Store safety:** model is versioned/CloudKit-compatible; migration failure,
  identity-catalog/key failure and global-store quarantine preserve originals and expose
  recovery without destructive reset.
- **AC-03 Offline:** the complete personal journey works in Anonymous with no account;
  an already-verified active account remains usable during ordinary network loss, while a
  cold unresolved identity never exposes cached account content.
- **AC-04 Sync:** real same-account multi-device tests prove private CloudKit convergence,
  offline/reconnect, soft-delete/restore/permanent-erasure propagation, and deterministic
  schedule replay before submission. Anonymous content remains intact and can enter an
  identified profile only through the explicit, validated, source-preserving transfer.
- **AC-04A Account boundary:** fixtures prove A/B/Anonymous/Legacy path and sidecar
  isolation; the signed build proves sign-out, return-to-A, A→B during active sync and both
  accounts' private databases without inferred PASS.
- **AC-05 Portability:** scope-neutral backup includes media bytes; restore/explicit
  Anonymous-or-Legacy transfer validates first, merges safely, preserves the source, is
  idempotent, and makes no partial mutation on corrupt input.
- **AC-06 Surface:** release UI has Today, Library, Settings only; no Groups or false sync
  claim; Import and Statistics remain correctly placed.
- **AC-07 First run:** onboarding may be skipped and still yields persistent, original,
  generalist demo content in EN/IT.
- **AC-08 Reminder:** permission is requested only from the enable action; denial provides
  localized Settings guidance and never blocks core use.
- **AC-09 Quality:** automated coverage plus documented iPhone/iPad, iOS 17/current,
  Apple-Silicon-Mac iPad-app smoke, localization, accessibility, appearance,
  import/security and upgrade matrices are green for every non-human cell.
- **AC-10 Human honesty:** Team/App ID/container/schema/legal URLs/signing/archive/
  TestFlight/price/submission cells cannot become PASS without real evidence.

## Verification

- Focused package/data/UI tests pin each changed contract; `ci/test.sh` remains the default
  regression gate and may not lose coverage.
- Visual UI changes require production-route screenshots, a changed-frame proof, and an
  unprimed screenshot critique before acceptance.
- Every worker returns a report; every batch receives semantic review and records evidence.
- The release governor uses `docs/testing/app-store-v1-gates.md` as a tri-state ledger:
  PASS, FAIL, or HUMAN_REQUIRED/UNVERIFIED.

## Task beads

- `sas-00-contract`: Freeze the 1.0 contract and new run.
- `sas-01-data-foundation`: Build the versioned private-store foundation and recovery seam.
- `sas-02-persistent-library`: Replace the shipping in-memory repository with Core Data.
- `sas-03-private-sync`: rejected initial pass retained as review evidence only.
- `sas-03a-account-routing`: implement account identity, scoped stores and legacy quarantine.
- `sas-03b-sync-convergence`: remediate truthful monitoring/history/convergence and retry.
- `sas-04-complete-backup`: Ship media-complete archive and merge-safe restore.
- `sas-04b-scoped-transfer-erasure`: implement explicit profile copy and active-scope erase.
- `sas-05-release-surface`: Remove Groups/fakes and finish onboarding/reminder/privacy UI.
- `sas-06-quality-evidence`: Harden CI, localization, accessibility, privacy, security and
  release evidence.
- `sas-07-human-release`: Execute account-dependent CloudKit, signing, TestFlight and ASC
  gates without agent-created PASS claims.

## Open inputs (not open decisions)

- Apple Developer team, App ID, final bundle/container identifiers.
- Legal identity, support/privacy contacts and public HTTPS URLs.
- Actual launch date used to schedule the price change.
- Real-device/account evidence for CloudKit, archive and TestFlight.
