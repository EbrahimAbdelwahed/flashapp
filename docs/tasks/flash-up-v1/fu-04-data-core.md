# Task Bead: fu-04-data-core Build the CloudKit-safe data core

Status: Open
Priority: P0
Type: task
Depends On: fu-01-store-spike
Run ID: `flash-up-v1`
Spec: `docs/specs/flash-up-v1-batch-spec.md`

## Outcome

The app has a V1 two-store Core Data model, repositories, affinity guarantees, trash/purge lifecycle, and remote-change extension points.

## Slice Strategy

tracer-bullet

Fresh Context Fit: yes

## Spec Coverage

- B1.1
- B1.2
- B1.3
- B1.4

## Grilling Evidence

- ADR-001 controls topology; any contradiction is an ADR, not an implementation choice.

## Worker Profile

reuse cloudkit-systems-engineer

Rationale:

One owner prevents incompatible model, repository, and sync assumptions across the shared persistence seam.

## Context

Combines original data beads because the model's store-affinity and history hooks cannot be honestly verified in isolation.

## What To Do

- Implement V1 model and PersistenceController.
- Add content/study repositories, tag scope, trash/purge, SyncMonitor, remote history processing, and tag dedup hooks.
- Add model-lint, affinity, dedup, token-resume, and purge tests.

## Likely Files / Packages

- Packages/FlashUpKit/Sources/FlashUpData/
- Packages/FlashUpKit/Tests/FlashUpDataTests/
- App/

## Acceptance Criteria

- [ ] Every B1.1–B1.4 stop condition holds.
- [ ] Study objects are asserted private even when a shared store exists.

## Verification

- `ci/test.sh`: expected to pass or produce documented output
- `SwiftLint`: expected to pass or produce documented output
- `Two-simulator same-account convergence check`: expected to pass or produce documented output

## Out Of Scope

- Feature screens, production sharing, card reconciliation, schedule replay.

## Notes / Handoff

- Worker must report files changed, behavior implemented, verification results, unresolved questions, and follow-up beads.
