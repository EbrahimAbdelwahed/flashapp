# Worker Profile: app-store-data-engineer

Generated: 2026-08-19
Source task: `docs/tasks/flash-app-store-v1/sas-01-data-foundation.md`

## Reuse Trigger

Use this worker when a bead has the same implementation shape as `sas-01-data-foundation Build the versioned private-store foundation`.

## Mandate

Complete recurring work shaped like `sas-01-data-foundation` without redesigning the feature.

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
- `docs/specs/flashapp-1-0-app-store-hardening.md`
- `docs/flywheel-runs/flash-app-store-v1/context-pack.md`
- `docs/tasks/flash-app-store-v1/sas-01-data-foundation.md`
- applicable `AGENTS.md` files

Current-doc research:

- Required when CloudKit/Core Data behavior is uncertain; use current primary Apple
  documentation only and record assumptions that still need account evidence.

## Allowed Files

May edit:

- Packages/FlashUpKit/Package.swift
- Packages/FlashUpKit/Sources/FlashUpData/CoreData/
- Packages/FlashUpKit/Sources/FlashUpData/Persistence/
- Packages/FlashUpKit/Sources/FlashUpData/Repositories/
- Packages/FlashUpKit/Sources/FlashUpData/Sync/
- Packages/FlashUpKit/Sources/FlashUpDomain/Content/
- Packages/FlashUpKit/Sources/FlashUpDomain/Backup/
- Packages/FlashUpKit/Sources/FlashUpDomain/Repositories/
- Packages/FlashUpKit/Tests/FlashUpDataTests/
- FlashUp.xcodeproj/
- App/AppEnvironment.swift
- App/FlashUpApp.swift
- docs/testing/cloudkit-personal-checklist.md

May inspect:

- `docs/decisions/ADR-006-app-store-v1-contract.md`
- `specs/flash-app-store-v1/`
- `docs/specs/flashapp-1-0-app-store-hardening.md`
- `docs/flywheel-runs/flash-app-store-v1/context-pack.md`
- `docs/tasks/flash-app-store-v1/sas-01-data-foundation.md`
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
-   - Model lint is CloudKit-compatible and versioned, including the approved
      `CDStudySettings` inventory.
-   - On-disk data survives close/reopen.
-   - Corrupt/migration failure preserves original store files and never deletes them.
-   - Account-dependent evidence remains UNVERIFIED.
- For reused sas-02/sas-03 work, the active bead's acceptance criteria replace this
  source-task summary; its explicit Domain paths remain allowed.

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

A separate reviewer must confirm model safety, scope and evidence honesty before dispatch
is closed.
