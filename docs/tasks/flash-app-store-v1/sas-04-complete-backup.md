# Task Bead: sas-04-complete-backup Ship complete media backups and safe restore

Status: Open
Priority: P0
Type: task
Depends On: sas-03b-sync-convergence
Run ID: `flash-app-store-v1`
Spec: `docs/specs/flashapp-1-0-app-store-hardening.md`

## Outcome

A versioned .flashupbackup archive atomically contains data and supported media, and restore validates before an idempotent non-overwriting merge.

## Slice Strategy

tracer-bullet

Fresh Context Fit: yes

## Spec Coverage

- AC-05
- Slice 04

## Grilling Evidence

- Owner explicitly requires media-complete backup and safe merge semantics.

## Worker Profile

reuse app-store-data-engineer

Rationale:

The serialized Data owner integrates archive I/O without opening two account stores or conflicting with AppEnvironment.

## Context

ADR-004 reference-only backup behavior is superseded by ADR-006.

## What To Do

- Version the scope-neutral manifest/archive layout, include media bytes, hash and validate every reference, stage restore before mutation, and merge UUID/log/media state idempotently.
- Preserve size/decompression limits and typed errors.
- Define the Domain BackupArchiveServicing port, implement it in Data, inject it from AppEnvironment, and replace the production legacy JSON path.

## Likely Files / Packages

- Packages/FlashUpKit/Sources/FlashUpDomain/Backup/
- Packages/FlashUpKit/Sources/FlashUpDomain/Repositories/
- Packages/FlashUpKit/Sources/FlashUpData/Backup/
- Packages/FlashUpKit/Sources/FlashUpData/Media/
- Packages/FlashUpKit/Tests/
- docs/decisions/backup-format.md
- App/AppEnvironment.swift
- App/Features/Settings/SettingsView.swift

## Acceptance Criteria

- [ ] Image/audio bytes round-trip and render.
- [ ] Second restore adds nothing and overwrites nothing.
- [ ] Corrupt/truncated/missing/hash-mismatched archives cause zero partial mutations.
- [ ] Production Settings resolves the injected archive port and contains no legacy direct JSON path.

## Verification

- `Focused backup archive/restore tests`: expected to pass or produce documented output
- `ci/test.sh`: expected to pass or produce documented output
- `SwiftLint`: expected to pass or produce documented output

## Out Of Scope

- Profile transfer orchestration, Settings visual redesign, CloudKit schema operations, Groups snapshots.

## Notes / Handoff

- Worker must report files changed, behavior implemented, verification results, unresolved questions, and follow-up beads.
