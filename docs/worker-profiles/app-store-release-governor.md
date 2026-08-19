# Worker Profile: app-store-release-governor

Generated: 2026-08-19
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

- `docs/decisions/ADR-006-app-store-v1-contract.md`
- applicable `specs/flash-app-store-v1/slices/` file
- `docs/testing/app-store-v1-gates.md`
- `docs/specs/flashapp-1-0-app-store-hardening.md`
- `docs/flywheel-runs/flash-app-store-v1/context-pack.md`
- `docs/tasks/flash-app-store-v1/sas-06-quality-evidence.md`
- applicable `AGENTS.md` files

Current-doc research:

- Required for volatile App Store requirements; use primary Apple sources and date every
  claim.

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
- `assets/emma-avatar/`.

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
ci/test.sh
ci/l10n-check.sh
```

Archive/TestFlight/App Store operations are evidence entries, not local commands, and stay
`HUMAN_REQUIRED` until the account holder supplies primary evidence.

If verification cannot run, report the reason and the narrowest manual check completed.

## Report Format

Return:

- files changed;
- behavior implemented;
- verification results;
- profile constraints followed;
- unresolved questions;
- recommended next worker or review step.

## Independent Semantic Review Gate

A separate release reviewer must confirm that every PASS has primary evidence and that
every missing external input remains blocking.
