# Task Bead: sas-02-persistent-library Replace the shipping in-memory library

Status: Open
Priority: P0
Type: task
Depends On: sas-01-data-foundation
Run ID: `flash-app-store-v1`
Spec: `docs/specs/flashapp-1-0-app-store-hardening.md`

## Outcome

Every existing LibraryRepository behavior persists in Private.sqlite and AppEnvironment has no production in-memory fallback.

## Slice Strategy

tracer-bullet

Fresh Context Fit: yes

## Spec Coverage

- AC-01
- AC-03
- Slice 02

## Grilling Evidence

- Existing in-memory behavior is the test oracle, not a second production architecture.

## Worker Profile

reuse app-store-data-engineer

Rationale:

The same data owner preserves entity, transaction and context invariants across the repository swap.

## Context

The complete app surface already consumes LibraryRepository, so the adapter can replace storage without redesigning views.

## What To Do

- Implement CoreDataLibraryRepository for content, study, settings, session, import, trash and erasure behavior.
- Wire AppEnvironment to the persistent repository and persistent media store; keep in-memory adapters preview/test-only.
- Add a stable, versioned, idempotent demo-install repository operation with `isDemo = true`.
- Remove dormant `Deck.groupID` and `BackupDeck.sharedSnapshot` from the 1.0 Domain contract and update fixtures/codecs.

## Likely Files / Packages

- Packages/FlashUpKit/Sources/FlashUpData/Repositories/
- Packages/FlashUpKit/Sources/FlashUpDomain/Content/
- Packages/FlashUpKit/Sources/FlashUpDomain/Backup/
- Packages/FlashUpKit/Sources/FlashUpDomain/Repositories/
- Packages/FlashUpKit/Tests/FlashUpDataTests/
- App/AppEnvironment.swift
- App/FlashUpApp.swift

## Acceptance Criteria

- [ ] Behavior contract tests agree across in-memory and on-disk adapters.
- [ ] Relaunch preserves all user state.
- [ ] Production composition contains no InMemoryLibrary or InMemoryMediaStore fallback.
- [ ] Repeated demo installation yields exactly one persistent `isDemo` deck.
- [ ] No group/shared-snapshot field remains in the 1.0 Domain or backup contract.

## Verification

- `Focused repository contract and relaunch tests`: expected to pass or produce documented output
- `ci/test.sh`: expected to pass or produce documented output
- `SwiftLint`: expected to pass or produce documented output

## Out Of Scope

- CloudKit remote processing, backup archive, UI redesign.

## Notes / Handoff

- Worker must report files changed, behavior implemented, verification results, unresolved questions, and follow-up beads.
