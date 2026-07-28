# Task Bead: fu-06-study-engine Build deterministic private study scheduling

Status: Open
Priority: P0
Type: task
Depends On: fu-03-fsrs-spike, fu-04-data-core
Run ID: `flash-up-v1`
Spec: `docs/specs/flash-up-v1-batch-spec.md`

## Outcome

Private schedules and append-only review logs produce deterministic replay, queues, resumable sessions, undo, and metrics.

## Slice Strategy

tracer-bullet

Fresh Context Fit: yes

## Spec Coverage

- B3.1
- B3.2
- B3.3
- B3.4
- B3.5

## Grilling Evidence

- Review-log ordering and private-store-only invariants are non-negotiable.

## Worker Profile

reuse study-domain-engineer

Rationale:

One deterministic event-sourcing owner minimizes adapter and snapshot token overhead.

## Context

All five source beads form a causal chain from answer to replay to UI-ready metrics.

## What To Do

- Implement schedule persistence, answer logs, replay/dedup, queue limits, session persistence/undo/reset, and metrics cache with full deterministic tests.

## Likely Files / Packages

- Packages/FlashUpKit/Sources/FlashUpDomain/
- Packages/FlashUpKit/Sources/FlashUpData/
- Packages/FlashUpKit/Tests/

## Acceptance Criteria

- [ ] Every B3.1–B3.5 stop condition holds.
- [ ] Shuffled remote log orders converge identically and undo is replay-safe.

## Verification

- `Permutation replay tests`: expected to pass or produce documented output
- `ci/test.sh`: expected to pass or produce documented output
- `SwiftLint`: expected to pass or produce documented output

## Out Of Scope

- SwiftUI study experience or settings controls.

## Notes / Handoff

- Worker must report files changed, behavior implemented, verification results, unresolved questions, and follow-up beads.
