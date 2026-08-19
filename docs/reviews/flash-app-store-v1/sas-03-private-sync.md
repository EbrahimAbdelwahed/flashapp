# SAS-03 private sync review

Status: `BLOCKED`
Date: 2026-08-19
Worker: Luna

## Verification evidence

- Focused monitor/history/recovery/convergence/repository tests: pass.
- `swift test`: 277 tests in 33 suites passed.
- `ci/test.sh`: passed, including 21 UI tests.
- `ci/lint.sh`: 0 violations in 139 files.
- `git diff --check`: passed.
- Apple account, container, schema, two-device and deletion-propagation evidence remains
  `HUMAN_REQUIRED` / `UNVERIFIED`.

## Correctness verdict

`BLOCKED`. The implementation needs: remote revoked-log reset convergence; initial account
refresh; availability/activity separation with overlapping event tracking; observable
processor failures; changed-note card reconciliation; safe malformed-identity handling;
recoverable corrupt/stale cursors; and a reachable Settings retry. Tests must cover these
behaviors rather than only the happy-path fixtures.

## Security and data-loss verdict

`BLOCKED`. In addition to the correctness items, review found: no safe Apple Account A→B
identity boundary; malformed rows may win destructive deduplication; duplicate review-log
UUIDs can be replayed twice; and the current cursor failure can wedge convergence
permanently. Checkpoint-before-prune ordering, container-filtered event observation,
metadata-only diagnostics, and honest human gates were accepted.

## Blocking decision

Resolve
`docs/decision-requests/flash-app-store-v1/account-switch-data-boundary.md` before another
worker edits SAS-03. The resolution must amend ADR-006, the architecture brief,
implementation spec, feature spec/slice, and graph as necessary. No later batch is
dispatchable while this decision is open.
