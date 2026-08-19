# Context Pack: FlashApp 1.0 App Store hardening

Date: 2026-08-19
Run ID: `flash-app-store-v1`

## Precedence

Read in this order:

1. `AGENTS.md`
2. `docs/decisions/ADR-006-app-store-v1-contract.md`
3. amended `flash-up-architecture-brief.md`
4. amended `flash-up-implementation-spec.md`
5. `docs/specs/flashapp-1-0-app-store-hardening.md`
6. applicable slice, task bead, worker profile and worker brief

ADR-006 supersedes old 1.0 assumptions about Groups/shared store, price, mandatory
onboarding, reference-only media backup and external TestFlight. Historical sections in
the old spec/run are not dispatchable when they conflict with ADR-006.

## Repository baseline

- Shipping composition: `App/AppEnvironment.swift` defaults to `InMemoryLibrary`; this is
  the release-blocking seam.
- Repository contract: `Packages/FlashUpKit/Sources/FlashUpDomain/Repositories/LibraryRepository.swift`.
- Preview oracle: `Packages/FlashUpKit/Sources/FlashUpData/Preview/` implements the complete
  app behavior in memory.
- Production media: `Packages/FlashUpKit/Sources/FlashUpData/Media/FileMediaStore.swift`.
- Backup today: `FlashUpDomain/Backup/BackupCodec.swift` plus
  `FlashUpData/Preview/InMemoryLibrary+Portability.swift`; it stores media references but
  not blobs.
- UI shell: `App/Features/Shared/RootTabView.swift` still exposes Groups.
- Groups placeholder: `App/Features/Groups/GroupsView.swift`.
- Sync UI: `App/Features/Settings/SettingsView.swift` currently consumes a simulated
  `SyncStatus` from the in-memory repository.
- Onboarding: `App/Features/Onboarding/OnboardingView.swift` is skippable but its callbacks
  only set completion state; production demo installation is not wired.
- Demo fixture: `FlashUpData/Preview/DemoContent.swift` is medical and conflicts with the
  approved generalist positioning.
- Reminder implementation: `App/Features/Settings/ReminderScheduler.swift` already uses
  local notifications at the enable action; denial guidance needs the final Settings path.
- Config: `Config/FlashUp.xcconfig` has placeholder bundle/container and an empty team;
  entitlements/remote notification remain appropriate for personal CloudKit.
- Tests: domain/data/UI behavior exists, but no Core Data/model/relaunch/CloudKit release
  evidence exists. CI is primarily iPhone 15/iOS 17.4.

## Fixed invariants

- iOS/iPadOS 17+, SwiftUI, Core Data via `NSPersistentCloudKitContainer`; no SwiftData.
- App → FlashUpData → FlashUpDomain dependency direction.
- One versioned `Private.sqlite`; no shared store or group entities in 1.0.
- Local/offline personal use is complete; iCloud sync is automatic and non-blocking.
- Never delete a user store for migration/sync recovery.
- No card text in logs; no proprietary account, StoreKit, tracking, ads or third-party
  analytics.
- English and Italian, accessibility and reduced motion in every UI change.
- `assets/emma-avatar/` is an untracked user-owned path and must not be inspected, edited,
  staged or committed.
- Apple-account/schema/signing/archive/TestFlight/ASC gates remain `HUMAN_REQUIRED` until
  primary evidence exists.

## Working-tree and publication policy

- Work occurs on `codex/flash-app-store-v1` in focused commits.
- Preserve unrelated user changes.
- Do not push, publish, create a remote repository or submit without explicit owner
  authorization.

