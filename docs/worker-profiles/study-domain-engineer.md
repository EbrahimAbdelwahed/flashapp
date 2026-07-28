# Worker Profile: study-domain-engineer

Generated: 2026-07-28
Source task: `docs/tasks/flash-up-v1/fu-03-fsrs-spike.md`

## Reuse Trigger

Use this worker when a bead has the same implementation shape as `fu-03-fsrs-spike Pin and prove the FSRS adapter contract`.

## Mandate

Complete recurring work shaped like `fu-03-fsrs-spike` without redesigning the feature.

## Scope

In scope:

- Implement the scoped task behavior described by the linked bead and worker brief.

Out of scope:

- Unrelated refactors.
- Changing public behavior outside the task acceptance criteria.
- Making product, architecture, prompt-policy, or data-model decisions reserved for the orchestrator.

## Required Context

Read first:

- `flash-up-implementation-spec.md`
- `docs/flywheel-runs/flash-up-v1/context-pack.md`
- `docs/tasks/flash-up-v1/fu-03-fsrs-spike.md`
- applicable `AGENTS.md` files

Current-doc research:

- not needed

## Allowed Files

May edit:

- Packages/FlashUpKit/Sources/FlashUpDomain/
- Packages/FlashUpKit/Tests/FlashUpDomainTests/
- docs/decisions/ADR-003-fsrs.md

May inspect:

- `flash-up-implementation-spec.md`
- `docs/flywheel-runs/flash-up-v1/context-pack.md`
- `docs/tasks/flash-up-v1/fu-03-fsrs-spike.md`
- applicable `AGENTS.md` files

Do not edit:

- Files outside the bead's approved scope.
- Files reserved by another active worker.

## Forbidden Decisions

Stop and report back before deciding:

- architecture boundaries outside the task bead
- product behavior not covered by acceptance criteria
- new dependencies or provider choices
- data model or persistence changes not specified by the orchestrator

## Quality Gates

- Change stays within the task file/package scope.
- Acceptance criteria are implemented or explicitly reported as blocked.
- Verification commands from the task bead are run or a concrete reason is reported.
- Acceptance criteria from the bead remain the source of truth:
-   - All B0.4 mapping and determinism requirements are covered by tests and ADR-003.

## Verification

Run:

```bash
`Swift Testing deterministic adapter cases`: expected to pass or produce documented output
```

If verification cannot run, report the reason and the narrowest manual check completed.

## Report Format

Return:

- files changed;
- behavior implemented;
- verification results;
- profile constraints followed;
- unresolved questions;
- recommended next worker or review step.

## Task Contract (verbatim)

### Goal / Outcome



### Context



### Allowed Scope

- <none>

### Forbidden Scope

- Unrelated refactors.
- Changing public behavior outside the task acceptance criteria.
- Making product, architecture, prompt-policy, or data-model decisions reserved for the orchestrator.

### Invariants

- <none>

### Acceptance Criteria

- <none>

### Verification

- `Swift Testing deterministic adapter cases`: expected to pass or produce documented output

If a verification command cannot run, state why and what remains unverified.

### Stop Conditions

- Stop and report when a required decision or verification cannot be completed.

### Independent Semantic Review Gate

A separate reviewer must confirm the diff remains within this contract before dispatch is closed.
