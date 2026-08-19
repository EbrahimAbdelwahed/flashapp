# Worker Profile: app-store-product-engineer

Generated: 2026-08-19
Source task: `docs/tasks/flash-app-store-v1/sas-05-release-surface.md`

## Reuse Trigger

Use this worker when a bead has the same implementation shape as `sas-05-release-surface Expose only the honest 1.0 product surface`.

## Mandate

Complete recurring work shaped like `sas-05-release-surface` without redesigning the feature.

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
- `docs/ux-principles.md`
- `specs/flash-app-store-v1/slices/05-release-surface.md`
- `docs/specs/flashapp-1-0-app-store-hardening.md`
- `docs/flywheel-runs/flash-app-store-v1/context-pack.md`
- `docs/tasks/flash-app-store-v1/sas-05-release-surface.md`
- applicable `AGENTS.md` files

Current-doc research:

- not needed

## Allowed Files

May edit:

- App/Features/
- App/Resources/Localizable.xcstrings
- App/Resources/DemoDeck/
- FlashUpUITests/

May inspect:

- `docs/specs/flashapp-1-0-app-store-hardening.md`
- `docs/flywheel-runs/flash-app-store-v1/context-pack.md`
- `docs/tasks/flash-app-store-v1/sas-05-release-surface.md`
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
-   - Exactly three tabs and no unavailable feature/false sync claim.
-   - Finish and skip both produce persistent useful demo content.
-   - Reminder denial, backup UI and EN/IT reviewer journey are covered.
-   - Accessibility and reduced-motion behavior remain correct.

## Verification

Run:

```bash
ci/test.sh
ci/lint.sh
```

Visual evidence additionally requires the production-route screenshot/diff and the
`screenshot-critique` gate named by the slice.

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

A separate reviewer and an unprimed screenshot critique must approve the release surface
before dispatch is closed.
