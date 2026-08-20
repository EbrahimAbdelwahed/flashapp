# Task Bead: sas-04b-scoped-transfer-erasure Copy profiles and erase only the active scope

Status: Open
Priority: P0
Type: task
Depends On: sas-04-complete-backup
Run ID: `flash-app-store-v1`
Spec: `docs/specs/flashapp-1-0-app-store-hardening.md`

## Outcome

Explicit Anonymous/Legacy transfer is source-preserving and deletion affects only the named active profile.

## Slice Strategy

tracer-bullet

Fresh Context Fit: yes

## Spec Coverage

- AC-04A
- AC-05
- Slice 04B

## Grilling Evidence

- ADR-007 forbids implicit transfer and cross-profile deletion.

## Worker Profile

reuse app-store-data-engineer

Rationale:

Transfer and erase coordinate account routing, repository, media and archive state.

## Context

The archive interface is frozen by SAS-04 and profiles are never loaded simultaneously.

## What To Do

- Implement explicit copy-first Anonymous/Legacy transfer through the validated archive service.
- Scope delete-all and persist identified deletion pending until qualifying export.

## Likely Files / Packages

- Packages/FlashUpKit/Sources/FlashUpData/AccountStores/
- Packages/FlashUpKit/Sources/FlashUpData/Backup/
- Packages/FlashUpKit/Sources/FlashUpData/Repositories/
- Packages/FlashUpKit/Tests/FlashUpDataTests/
- App/AppEnvironment.swift

## Acceptance Criteria

- [ ] Transfer is media-complete, source-preserving, idempotent and transactionally safe.
- [ ] Malformed conflicts never delete valid data.
- [ ] Delete B never mutates A/Anonymous/Legacy.
- [ ] Pending cloud deletion survives sign-out.
- [ ] Cloud deletion evidence remains HUMAN_REQUIRED.

## Verification

- `Focused transfer/erase/failure tests`: expected to pass or produce documented output
- `swift test`: expected to pass or produce documented output
- `ci/test.sh`: expected to pass or produce documented output
- `ci/lint.sh`: expected to pass or produce documented output

## Out Of Scope

- Visible UI, direct SQLite copy, Apple operations, assets/emma-avatar/.

## Notes / Handoff

- Worker must report files changed, behavior implemented, verification results, unresolved questions, and follow-up beads.
