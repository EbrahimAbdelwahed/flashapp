# Worker Profile: app-store-portability-engineer

Generated: 2026-08-19
Source task: `docs/tasks/flash-app-store-v1/sas-04-complete-backup.md`

## Reuse Trigger

Use this worker when a bead has the same implementation shape as `sas-04-complete-backup Ship complete media backups and safe restore`.

## Mandate

Complete recurring work shaped like `sas-04-complete-backup` without redesigning the feature.

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
- `specs/flash-app-store-v1/slices/04-complete-backup.md`
- `docs/specs/flashapp-1-0-app-store-hardening.md`
- `docs/flywheel-runs/flash-app-store-v1/context-pack.md`
- `docs/tasks/flash-app-store-v1/sas-04-complete-backup.md`
- applicable `AGENTS.md` files

Current-doc research:

- not needed

## Allowed Files

May edit:

- Packages/FlashUpKit/Sources/FlashUpDomain/Backup/
- Packages/FlashUpKit/Sources/FlashUpDomain/Repositories/
- Packages/FlashUpKit/Sources/FlashUpData/Backup/
- Packages/FlashUpKit/Sources/FlashUpData/Media/
- Packages/FlashUpKit/Tests/
- docs/decisions/backup-format.md
- App/AppEnvironment.swift
- App/Features/Settings/SettingsView.swift

May inspect:

- `docs/specs/flashapp-1-0-app-store-hardening.md`
- `docs/flywheel-runs/flash-app-store-v1/context-pack.md`
- `docs/tasks/flash-app-store-v1/sas-04-complete-backup.md`
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
-   - Image/audio bytes round-trip and render.
-   - Second restore adds nothing and overwrites nothing.
-   - Corrupt/truncated/missing/hash-mismatched archives cause zero partial mutations.
-   - Production Settings consumes the injected archive port; it does not use the legacy
      direct JSON path.

## Verification

Run:

```bash
swift test --package-path Packages/FlashUpKit
ci/test.sh
ci/lint.sh
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

## Independent Semantic Review Gate

A separate reviewer must confirm archive integrity, idempotence and zero-partial-mutation
behavior before dispatch is closed.
