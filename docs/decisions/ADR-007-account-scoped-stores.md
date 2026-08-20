# ADR-007 — Apple Account-scoped personal stores

Status: Accepted
Date: 2026-08-20
Run: `flash-app-store-v1`
Decider: product owner
Decision request: `account-switch-data-boundary`

## Context

ADR-006 selected one CloudKit-mirrored `Private.sqlite` for version 1.0 but did not define
what happens when a device changes from Apple Account A to Apple Account B. Account
availability alone cannot distinguish a return to A from a switch to B. Opening the same
local replica for B risks exporting A's cards to B or allowing B's imports to overwrite the
local view.

Both SAS-03 semantic reviews rejected an availability-only implementation. The owner chose
account-scoped stores rather than a single store bound forever to the first account or a
same-account-only release claim.

## Decision

### 1. Profile boundary

- FlashApp has one active **data profile** at a time: `anonymous` or one opaque Apple
  Account fingerprint.
- Every profile owns its own directory containing `Private.sqlite`, media, session state,
  persistent-history cursor and recovery artifacts. No profile may open, export, import,
  erase or schedule against another profile's files.
- The layout is `Application Support/FlashApp/Stores/Anonymous/`,
  `Stores/Accounts/<fingerprint>/`, and `Stores/Legacy/<migration-id>/`; each directory
  contains its scoped files. Exactly one profile store is loaded in a process.
- An Apple Account fingerprint is derived locally as
  `HMAC-SHA256(device-local-secret, containerIdentifier || 0x00 || userRecordName)`.
  The secret is nonsynchronizable, device-only Keychain material. Raw record names, email
  addresses, account names, fingerprints and paths are neither displayed nor logged. A
  missing key with existing account directories is a recovery state, never permission to
  silently create a replacement key.
- The fingerprint is routing metadata, not a proprietary FlashApp account. FlashApp still
  has no login, password, backend or account database.

### 2. Bootstrap and account transitions

- `AccountStoreCoordinator` is the sole owner of identity preflight, profile routing and
  repository replacement. `AppEnvironment` consumes its state; views and repositories do
  not choose file URLs.
- At launch, identity is resolved before any production store is loaded. If the current
  identity is known, its account directory opens with private CloudKit options. If identity
  cannot be determined temporarily on cold launch, the anonymous profile opens local-only;
  a cached account library is never exposed without current identity proof. An already-open
  account profile remains locally usable during an ordinary network outage that produces no
  account-change event.
- With no account or a restricted account, the anonymous profile opens local-only. This is
  an intentional shipping mode, not an in-memory fallback.
- On `CKAccountChanged`, new writes are gated, the current repository is quiesced and closed,
  identity is resolved again, and exactly one repository is opened for the resulting
  profile. A stale transition result may never replace a newer generation.
- Returning to the same fingerprint reopens the same profile. Switching A→B opens B's
  profile; A's local files remain sealed and are never merged automatically. Signing out
  opens the anonymous profile and hides the signed-in profile.
- A real sign-out/same-account return and A→B switch remain `HUMAN_REQUIRED / UNVERIFIED`
  until executed with the signed build. Repository fixtures cannot prove framework ordering
  or absence of a CloudKit race.

### 3. Anonymous content and explicit transfer

- Anonymous content is never silently exported when an Apple Account appears.
- If the anonymous profile contains user content, FlashApp continues to expose it locally
  and presents an explicit action to merge a validated snapshot into the current account
  profile. “Not now” leaves the anonymous profile unchanged and local-only.
- The transfer uses the same complete, media-bearing, validate-before-mutate archive engine
  as backup/restore. It is idempotent, never overwrites live UUIDs, and deletes neither
  source nor destination. Source removal, if later offered, requires a separate explicit
  confirmation after a verified merge.
- Therefore account routing precedes the archive batch, while final transfer and sync
  convergence follow it.

### 4. Legacy migration and erasure

- The pre-ADR-007 global `FlashApp/Private.sqlite` has no proven Apple Account provenance.
  A staged, recoverable migration clones it and its media/session state into a local-only
  `legacy` profile. Originals and sidecars remain untouched until a later explicit deletion;
  no migration failure opens a blank account store over the error.
- “Delete all data” is scoped to the active profile and names that scope. Anonymous/legacy
  deletion removes only that local profile. Identified-profile deletion keeps a durable
  pending state until CloudKit export is confirmed; signing out cannot turn pending into
  success. Inactive account and anonymous profiles are untouched.
- Remote erasure is scoped to the currently active Apple Account and remains a real-device
  human gate. Help/privacy copy explains how to return to another account to erase that
  account's remote FlashApp data.

### 5. Sync truthfulness

- Availability, active profile, transfer requirement and sync activity are separate state.
  Merely resolving an available account never means “Up to date.”
- Event identity and overlapping setup/import/export activity are tracked. “Up to date” is
  shown only after qualifying completion with no relevant operation still in flight.
- Persistent-history cursor corruption is recoverable: quarantine the derived cursor,
  replay idempotently from nil and checkpoint only after reconciliation. Never modify or
  replace `Private.sqlite` to repair a cursor.
- Changed notes run card reconciliation; review logs are unioned by UUID before deterministic
  schedule replay; malformed identities can never win destructive deduplication. Processing
  failure remains visible and retryable without blocking local authoring/study.

## Flywheel consequence

The rejected SAS-03 pass is retained as evidence but not accepted. Work is resliced:

1. `sas-03a-account-routing` — profile registry, identity preflight, safe legacy quarantine,
   single-owner transitions and local fixtures.
2. `sas-03b-sync-convergence` — finish truthful monitoring/history/convergence and every
   rejected SAS-03 correctness/security remediation.
3. `sas-04-complete-backup` — complete, scope-neutral media archive.
4. `sas-04b-scoped-transfer-erasure` — explicit anonymous/legacy copy and active-scope
   deletion semantics through the validated archive service.
5. `sas-05-release-surface` — expose transfer/retry/account guidance with EN/IT and
   accessibility coverage.

Only one Data/AppEnvironment owner is active across 03a, 03b, 04 and 04b.

## Consequences

- ADR-007 supersedes ADR-006's single physical store URL and prohibition on shipping
  local-only configuration. Each profile still has exactly one versioned `Private.sqlite`,
  and only a validated Apple Account profile attaches private CloudKit options.
- Account isolation adds bootstrap, migration, transition and privacy complexity, but makes
  the A→B boundary explicit and testable.
- Same-account and account-switch behavior cannot be marked PASS without Apple account,
  container, schema and device evidence.

## Alternatives rejected

- **One store bound to the first account:** rejected because safely preventing framework
  mirroring during an A→B switch requires a fragile race-sensitive bootstrap and strands
  the app until export/erase.
- **Same-account-only support statement:** rejected because metadata cannot enforce a data
  boundary and the submission would remain blocked.
- **Automatic anonymous merge:** rejected because a newly available account must not receive
  local content without an explicit user choice.
