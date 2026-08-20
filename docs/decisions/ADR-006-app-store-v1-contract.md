# ADR-006 — FlashApp 1.0 App Store contract

Status: Accepted
Date: 2026-08-19
Run: `flash-app-store-v1`
Decider: product owner (explicit decisions recorded 2026-08-19)

Amendment (2026-08-20): ADR-007 supersedes the single global `Private.sqlite` URL and the
prohibition on a shipping local-only store. The logical one-private-store model remains,
but it is instantiated per isolated Anonymous, Legacy or identified Apple Account profile;
only an identified profile receives CloudKit options.

## Context

The approved brief originally made collaborative Groups, a shared CloudKit store,
mandatory onboarding, a €1.99 launch price, and an external TestFlight cohort part of
version 1.0. The implementation reached a complete product surface on an in-memory
repository, but production persistence and CloudKit were still absent. Shipping the
placeholder Groups surface or a simulated sync state would violate the App Store
completeness and metadata-accuracy gates.

The owner chose a narrower but still cloud-enabled 1.0. This is a product and persistence
decision, so it amends the brief and implementation specification rather than being hidden
inside a release task.

## Decision

### 1. Release surface

- Version 1.0 contains personal flashcards, study, CSV and `.apkg` import, backup/restore,
  local reminders, statistics, and automatic personal iCloud synchronization.
- Collaborative Groups, `CKShare`, the shared CloudKit database, invitations, group
  revisions, and every Groups UI/tutorial are deferred beyond 1.0.
- The primary navigation is Today, Library, and Settings. Import is available from
  Library (and may also be linked from Today); Statistics is pushed from Today.
- The app is a paid download: €2.99 at launch, changed manually in App Store Connect to
  €4.99 one calendar month after the actual launch date. There is no StoreKit code, IAP,
  trial, subscription, feature gate, advertising, tracking, or third-party analytics.

### 2. Persistence and synchronization

- One versioned Core Data model and one `NSPersistentCloudKitContainer` own production
  persistence.
- Version 1.0 has one SQLite store, `Private.sqlite`, mirrored only to the user's private
  CloudKit database. There is no `Shared.sqlite` and no group entity graph.
- The release configuration always attaches private CloudKit options to `Private.sqlite`;
  a missing/restricted/offline account is an availability state, not a different store
  topology. Data created in that state stays in the same store and becomes eligible for
  mirroring when the account/network returns. Pure-local configuration exists only for
  deterministic tests/previews or an explicitly non-CloudKit build, never as a shipping
  runtime fallback.
- Synchronization is automatic when iCloud is available. Settings exposes a subtle status,
  actionable recovery guidance, and manual retry; it does not expose an enable/disable
  switch.
- The domain-facing repository exposes an explicit sync retry operation. Retry requests a
  save/event refresh; it never swaps stores, deletes files, or fabricates a successful state.
- Production must not fall back to `InMemoryLibrary`. In-memory implementations remain
  valid test/preview fixtures only.
- Store or migration failure never deletes or recreates user data. The original files are
  preserved and the app offers retry, recovery/export, and support guidance.

### 3. Onboarding, demo, and reminders

- First-launch onboarding remains at most three short screens but is skippable.
- Completing or skipping it leaves a useful, original, generalist university demo deck
  available through the real persistent repository. Installation is idempotent.
- The persistent repository owns a stable-version demo-install operation that marks the
  deck `isDemo`; UI code supplies no Core Data detail and invokes the same operation for
  completion and skip.
- Notification permission is requested directly after the user enables the optional
  reminder. A denied permission keeps the user's preference visible and provides
  actionable guidance to iOS Settings; there is no additional pre-permission modal.

### 4. Backup and restore

- A FlashApp backup is a versioned archive containing the data manifest and the bytes for
  every referenced supported media asset. Reference-only backups are not complete enough
  for 1.0.
- Export validates references and hashes and completes atomically.
- Restore validates and stages the whole archive before mutation, then performs a safe,
  idempotent merge. Existing live UUIDs are never overwritten or implicitly deleted;
  append-only review logs and content-addressed media are deduplicated.
- A corrupt, incomplete, or unsupported archive makes no partial data changes.
- The portable archive port is composed by `AppEnvironment`; Settings consumes that port
  and never constructs a Data service or JSON-encodes the legacy document directly.

### 5. Release verification and human gates

- Internal TestFlight is required; an external student cohort is not a 1.0 gate.
- The submission is delayed unless personal CloudKit synchronization passes real
  end-to-end verification, including local/offline behavior, reconnect, convergence, and
  relaunch on the intended device matrix.
- Apple Developer membership/team, App ID, final bundle ID, CloudKit container and
  production schema, legal identity, support/privacy URLs, signing, archive validation,
  TestFlight processing, price scheduling, and App Store submission are human-account
  gates.
- Agents may prepare instructions and record supplied evidence, but must leave these gates
  `HUMAN_REQUIRED` or `UNVERIFIED`; absence of evidence can never be converted to PASS.

## Consequences

- The 1.0 data model and UI become materially smaller and easier to review.
- Adding Groups later is a new product and architecture cycle. It may add a shared store
  through a versioned migration, but 1.0 carries no dormant shared-store complexity.
- Existing group batches in `flash-up-v1` are superseded for 1.0 rather than completed.
- Existing UI behavior on fakes is an oracle, not production architecture. Persistent
  adapters replace the shipping in-memory composition without preserving dev-only
  compatibility layers.
- ADR-004 section 7 is superseded: media bytes now belong to the complete FlashApp backup.
- The price change is an App Store Connect operation tied to the actual launch date, not an
  in-app timer.

## Alternatives considered

- **Keep Groups in 1.0:** rejected because it expands the persistence topology, review
  surface, multi-account evidence, and delivery time before the Apple account is active.
- **Ship local-only:** rejected because automatic personal iCloud sync remains a 1.0
  product requirement.
- **Predispose an unused shared store:** rejected because dormant CloudKit complexity has
  no 1.0 user value and weakens the release proof.
- **Back up media references only:** rejected because a successful restore could silently
  produce missing attachments.
- **Replace live data during restore:** rejected because CloudKit and stale backups make
  destructive replacement unsafe.
