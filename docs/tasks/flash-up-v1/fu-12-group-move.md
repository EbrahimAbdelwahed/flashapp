# Task Bead: fu-12-group-move Manage group membership and move deck graphs

Status: Open
Priority: P0
Type: task
Depends On: fu-05-note-domain, fu-11-group-connect
Run ID: `flash-up-v1`
Spec: `docs/specs/flash-up-v1-batch-spec.md`

## Outcome

Participants can inspect/leave groups and owners can move or copy deck graphs while private study progress survives.

## Slice Strategy

tracer-bullet

Fresh Context Fit: yes

## Spec Coverage

- B7.3
- B7.4

## Grilling Evidence

- ADR-002 move algorithm and private-study affinity are immutable constraints.

## Worker Profile

reuse cloudkit-systems-engineer

Rationale:

Shared-zone migration must have one CloudKit-focused owner and test fixture family.

## Context

Membership operations and movement touch the same share graph and failure-reconciliation logic.

## What To Do

- Build GroupDetail leave/remove flows, DeckMover with failure reconciliation, group destination UI, and two-account movement evidence.

## Likely Files / Packages

- Packages/FlashUpKit/Sources/FlashUpData/
- App/Features/Groups/
- App/Features/Library/
- docs/testing/

## Acceptance Criteria

- [ ] B7.3 and B7.4 stop conditions hold.
- [ ] UUID, tags, revisions, and private schedule continuity follow the source contract.

## Verification

- `Data move failure tests`: expected to pass or produce documented output
- `Two-account move and progress checklist`: expected to pass or produce documented output

## Out Of Scope

- Revision history or group deletion.

## Notes / Handoff

- Worker must report files changed, behavior implemented, verification results, unresolved questions, and follow-up beads.
