# Task Bead: sas-01-data-foundation Build the versioned private-store foundation

Status: Open
Priority: P0
Type: task
Depends On: sas-00-contract
Run ID: `flash-app-store-v1`
Spec: `docs/specs/flashapp-1-0-app-store-hardening.md`

## Outcome

FlashUpData can open, close, reopen and safely recover one versioned CloudKit-compatible Private.sqlite store without destructive repair.

## Slice Strategy

tracer-bullet

Fresh Context Fit: yes

## Spec Coverage

- AC-01
- AC-02
- AC-03
- Slice 01

## Grilling Evidence

- ADR-006 fixes one private store and forbids destructive recovery.

## Worker Profile

create app-store-data-engineer

Rationale:

One owner must control model, store options, migration and later sync assumptions.

## Context

No Core Data model or persistence controller exists; this is the first production-data seam.

## What To Do

- Implement the V1 model, PersistenceController, one Private.sqlite description, local/on-disk/in-memory test modes, history/remote-change options, migration backup and recovery state.
- Exclude group/shared entities and keep real CloudKit proof unverified until the account is active.

## Likely Files / Packages

- Packages/FlashUpKit/Package.swift
- Packages/FlashUpKit/Sources/FlashUpData/CoreData/
- Packages/FlashUpKit/Sources/FlashUpData/Persistence/
- Packages/FlashUpKit/Tests/FlashUpDataTests/
- FlashUp.xcodeproj/

## Acceptance Criteria

- [ ] Model lint is CloudKit-compatible and versioned.
- [ ] V1 contains `CDStudySettings` with the approved singleton/dedup fields; it contains no session/tutorial/system-authorization entity.
- [ ] On-disk data survives close/reopen.
- [ ] Corrupt/migration failure preserves original store files and never deletes them.
- [ ] Account-dependent evidence remains UNVERIFIED.

## Verification

- `Focused FlashUpData model/reopen/recovery tests`: expected to pass or produce documented output
- `ci/test.sh`: expected to pass or produce documented output
- `SwiftLint`: expected to pass or produce documented output

## Out Of Scope

- LibraryRepository implementation, CloudKit E2E proof, views, backup archive.

## Notes / Handoff

- Worker must report files changed, behavior implemented, verification results, unresolved questions, and follow-up beads.
