# Task Bead: fu-13-group-history Complete shared revision and ownership lifecycle

Status: Open
Priority: P1
Type: task
Depends On: fu-12-group-move
Run ID: `flash-up-v1`
Spec: `docs/specs/flash-up-v1-batch-spec.md`

## Outcome

Shared edits have restorable revision history and group deletion is safe and understandable for owners and participants.

## Slice Strategy

tracer-bullet

Fresh Context Fit: yes

## Spec Coverage

- B7.5
- B7.6

## Grilling Evidence

- Ownership transfer is not silently invented; owner deletion behavior follows ADR-002.

## Worker Profile

reuse cloudkit-systems-engineer

Rationale:

Revision concurrency, ownership, and zone disappearance are continuations of collaboration lifecycle behavior.

## Context

Both source beads are ownership/history semantics at the end of the group lifecycle.

## What To Do

- Implement revision recorder/history/restore/pruning wiring, owner deletion UI, participant disappearance state, and manual checklists.

## Likely Files / Packages

- Packages/FlashUpKit/Sources/FlashUpData/
- App/Features/Groups/
- docs/testing/

## Acceptance Criteria

- [ ] B7.5 and B7.6 stop conditions hold.
- [ ] Concurrent edit and owner-deletion behavior is documented and safe.

## Verification

- `Revision tests`: expected to pass or produce documented output
- `Two-account edit/restore/deletion checklist`: expected to pass or produce documented output

## Out Of Scope

- Delete all user data, final accessibility audit.

## Notes / Handoff

- Worker must report files changed, behavior implemented, verification results, unresolved questions, and follow-up beads.
