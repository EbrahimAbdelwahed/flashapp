# Task Bead: fu-07-portability Deliver portable import, export, and backup services

Status: Open
Priority: P1
Type: task
Depends On: fu-05-note-domain, fu-06-study-engine
Run ID: `flash-up-v1`
Spec: `docs/specs/flash-up-v1-batch-spec.md`

## Outcome

CSV and backup codecs safely import, export, undo, restore, and preserve data without requiring UI.

## Slice Strategy

tracer-bullet

Fresh Context Fit: yes

## Spec Coverage

- B4.1
- B4.2
- B4.4
- B4.5

## Grilling Evidence

- Import atomicity and backup merge behavior are protected data-integrity contracts.

## Worker Profile

reuse study-domain-engineer

Rationale:

Parsers, codecs, and transactional data tests share the same pure/data boundary.

## Context

The UI can use a cohesive portability service instead of separately wiring four transport paths.

## What To Do

- Implement RFC 4180 parsing, planner/committer/undo, deck export, BackupCodec, and BackupService integration tests.

## Likely Files / Packages

- Packages/FlashUpKit/Sources/FlashUpDomain/
- Packages/FlashUpKit/Sources/FlashUpData/
- Packages/FlashUpKit/Tests/

## Acceptance Criteria

- [ ] Every B4.1, B4.2, B4.4, and B4.5 stop condition holds.
- [ ] Import has no partial commit; backup round trip preserves schedules and logs.

## Verification

- `CSV round-trip tests`: expected to pass or produce documented output
- `Backup restore integration test`: expected to pass or produce documented output
- `ci/test.sh`: expected to pass or produce documented output

## Out Of Scope

- File importer/exporter views and settings UI.

## Notes / Handoff

- Worker must report files changed, behavior implemented, verification results, unresolved questions, and follow-up beads.
