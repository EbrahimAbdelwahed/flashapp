# Task Bead: fu-02-sharing-spike Prove sharing, acceptance, and graph movement

Status: Open
Priority: P0
Type: spike
Depends On: fu-01-store-spike
Run ID: `flash-up-v1`
Spec: `docs/specs/flash-up-v1-batch-spec.md`

## Outcome

ADR-002 proves or amends share acceptance and the UUID-preserving deck move algorithm with two Apple accounts.

## Slice Strategy

tracer-bullet

Fresh Context Fit: yes

## Spec Coverage

- B0.3

## Grilling Evidence

- No production sharing work may begin until ADR-002 resolves the zone-move assumption.

## Worker Profile

reuse cloudkit-systems-engineer

Rationale:

Uses the same CloudKit relationship-graph and manual-account discipline as fu-01.

## Context

The shared zone boundary is the highest data-integrity risk in the product.

## What To Do

- Extend spike code to share, accept, list participants, leave, move graphs both directions, and record lifecycle hooks in ADR-002.

## Likely Files / Packages

- Spikes/
- docs/decisions/ADR-002-sharing-and-move.md

## Acceptance Criteria

- [ ] B0.3 stop conditions and two-account evidence are recorded.

## Verification

- `Two-account simulator/device sharing checklist`: expected to pass or produce documented output
- `CloudKit Console residual-record inspection`: expected to pass or produce documented output

## Out Of Scope

- Production group UI or ShareManager.

## Notes / Handoff

- Worker must report files changed, behavior implemented, verification results, unresolved questions, and follow-up beads.
