# Task Bead: fu-01-store-spike Prove the two-store CloudKit topology

Status: Open
Priority: P0
Type: spike
Depends On: fu-00-scaffold
Run ID: `flash-up-v1`
Spec: `docs/specs/flash-up-v1-batch-spec.md`

## Outcome

ADR-001 establishes whether the specified private/shared-store topology works with the configured CloudKit container.

## Slice Strategy

tracer-bullet

Fresh Context Fit: yes

## Spec Coverage

- B0.2

## Grilling Evidence

- Architecture brief is authoritative; an unexpected CloudKit behavior blocks production persistence.

## Worker Profile

create cloudkit-systems-engineer

Rationale:

Store topology, sharing, migration, and sync require recurring CloudKit/Core Data expertise.

## Context

This is the first irreversible architecture proof.

## What To Do

- Implement only throwaway topology proof code and document all verified options, entitlements, local mode behavior, and gotchas in ADR-001.

## Likely Files / Packages

- Spikes/
- docs/decisions/ADR-001-store-topology.md

## Acceptance Criteria

- [ ] All B0.2 verification points are evidenced in ADR-001.
- [ ] Any required deviation is explicitly escalated.

## Verification

- `CloudKit schema initialization and two-store manual proof`: expected to pass or produce documented output

## Out Of Scope

- Production Core Data model or ShareManager.

## Notes / Handoff

- Worker must report files changed, behavior implemented, verification results, unresolved questions, and follow-up beads.
