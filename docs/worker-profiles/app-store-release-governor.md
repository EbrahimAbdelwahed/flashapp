# Worker Profile: app-store-release-governor

Generated: 2026-08-20
Source task: `docs/tasks/flash-app-store-v1/sas-06-quality-evidence.md`

## Reuse Trigger

Use this worker when a bead has the same implementation shape as `sas-06-quality-evidence Build the App Store quality and evidence gates`.

## Mandate

Complete recurring work shaped like `sas-06-quality-evidence` without redesigning the feature.

## Scope

In scope:

- Implement the scoped task behavior described by the linked bead and worker brief.

Out of scope:

- Unrelated refactors.
- Changing public behavior outside the task acceptance criteria.
- Making product, architecture, prompt-policy, or data-model decisions reserved for the orchestrator.

## Required Context

Read first:

- `docs/specs/flashapp-1-0-app-store-hardening.md`
- `docs/flywheel-runs/flash-app-store-v1/context-pack.md`
- `docs/tasks/flash-app-store-v1/sas-06-quality-evidence.md`
- applicable `AGENTS.md` files

Current-doc research:

- not needed

## Allowed Files

May edit:

- ci/
- Config/
- docs/testing/
- docs/legal/
- docs/reviews/
- App/Resources/

May inspect:

- `docs/specs/flashapp-1-0-app-store-hardening.md`
- `docs/flywheel-runs/flash-app-store-v1/context-pack.md`
- `docs/tasks/flash-app-store-v1/sas-06-quality-evidence.md`
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
-   - All non-human matrix cells have evidence or honest FAIL.
-   - No secret, placeholder legal claim, unsupported accessibility claim or inferred archive PASS remains.
-   - Existing default coverage is preserved.

## Verification

Run:

```bash
`ci/test.sh`: expected to pass or produce documented output
`l10n check`: expected to pass or produce documented output
`release matrix inspection`: expected to pass or produce documented output
`Semantic release review`: expected to pass or produce documented output
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

- `ci/test.sh`: expected to pass or produce documented output
- `l10n check`: expected to pass or produce documented output
- `release matrix inspection`: expected to pass or produce documented output
- `Semantic release review`: expected to pass or produce documented output

If a verification command cannot run, state why and what remains unverified.

### Stop Conditions

- Stop and report when a required decision or verification cannot be completed.

### Independent Semantic Review Gate

A separate reviewer must confirm the diff remains within this contract before dispatch is closed.
