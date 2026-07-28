# Task Bead: fu-05-note-domain Complete the note lifecycle domain contract

Status: Open
Priority: P1
Type: task
Depends On: fu-04-data-core
Run ID: `flash-up-v1`
Spec: `docs/specs/flash-up-v1-batch-spec.md`

## Outcome

Notes parse clozes, fingerprint/tag safely, generate stable cards, reconcile edits, and convert types without losing study history.

## Slice Strategy

tracer-bullet

Fresh Context Fit: yes

## Spec Coverage

- B2.1
- B2.2
- B2.3
- B2.4
- B2.5

## Grilling Evidence

- Card UUID stability and no cross-scope tag merges are frozen contracts.

## Worker Profile

reuse study-domain-engineer

Rationale:

Pure parsing and persistence reconciliation share the note-domain test fixtures and type boundaries.

## Context

A complete note lifecycle avoids five agents rediscovering cloze/card invariants.

## What To Do

- Implement ClozeParser, ContentFingerprint, TagNormalizer, CardGenerator/Reconciler, and NoteTypeConverter; wire remote reconciliation and history provider seams.

## Likely Files / Packages

- Packages/FlashUpKit/Sources/FlashUpDomain/
- Packages/FlashUpKit/Sources/FlashUpData/
- Packages/FlashUpKit/Tests/

## Acceptance Criteria

- [ ] Every B2.1–B2.5 listed test case passes.
- [ ] Surviving template keys keep their UUID; removed clozes are soft-deleted.

## Verification

- `FlashUpDomain and FlashUpData test suites`: expected to pass or produce documented output
- `SwiftLint`: expected to pass or produce documented output

## Out Of Scope

- FSRS scheduling or editor UI.

## Notes / Handoff

- Worker must report files changed, behavior implemented, verification results, unresolved questions, and follow-up beads.
