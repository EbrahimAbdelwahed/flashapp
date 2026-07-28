# Task Bead: fu-03-fsrs-spike Pin and prove the FSRS adapter contract

Status: Done (2026-07-28) — report: `docs/worker-reports/flash-up-v1/fu-03-fsrs-spike.md`
Priority: P0
Type: spike
Depends On: fu-00-scaffold
Run ID: `flash-up-v1`
Spec: `docs/specs/flash-up-v1-batch-spec.md`

## Outcome

A pinned swift-fsrs dependency, deterministic FlashUpDomain adapter, and ADR-003 mapping table.

## Slice Strategy

tracer-bullet

Fresh Context Fit: yes

## Spec Coverage

- B0.4

## Grilling Evidence

- The external FSRS API is isolated before schedules persist its representation.

## Worker Profile

create study-domain-engineer

Rationale:

FSRS, queueing, replay, import codecs, and pure domain tests share deterministic-domain expertise.

## Context

Retires third-party API uncertainty without coupling storage to library types.

## What To Do

- Pin swift-fsrs, add FSRSService protocol/adapter, prove deterministic replay and interval preview, and write ADR-003.

## Likely Files / Packages

- Packages/FlashUpKit/Sources/FlashUpDomain/
- Packages/FlashUpKit/Tests/FlashUpDomainTests/
- docs/decisions/ADR-003-fsrs.md

## Acceptance Criteria

- [x] All B0.4 mapping and determinism requirements are covered by tests and ADR-003.

## Verification

- `Swift Testing deterministic adapter cases`: passed — 12 tests in `SwiftFSRSAdapterTests`,
  covering determinism across folds and adapter instances, retention configurability,
  four-grade preview ordering and non-commitment, lapse handling, and the persisted raw
  value contract.
- Full pipeline: `ci/test.sh` green (SwiftLint 0 violations in 14 files, 12 domain tests,
  UI tests `** TEST SUCCEEDED **`).
- Deviation recorded in ADR-003 §2: the dependency is pinned to commit `4fbaf20` because
  tag `5.0.0` exposes no usable scheduler API.

## Out Of Scope

- CDSchedule, queues, or UI.

## Notes / Handoff

- Worker must report files changed, behavior implemented, verification results, unresolved questions, and follow-up beads.
