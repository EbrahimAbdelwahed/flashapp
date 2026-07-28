# Log: GAP-06B local promotion materialization

Date: 2026-07-25
Area: capability-gap

## Summary

Implemented deterministic promotion receipts, durable sink claims and receipt
CAS, optional sink injection in the resolution service, and a reference local
Flywheel sink. The sink writes a validated self-contained run through
descriptor-relative staging and an atomic no-clobber rename; it does not create
task state, dispatch workers, or publish repository changes.

## Files Changed

- `src/study_agent_devkit/capability_gap/resolution_contracts.py`: exact
  promotion receipt codec/factory and technical sink protocol.
- `src/study_agent_devkit/capability_gap/resolution_store.py`: durable claim
  creation, receipt CAS, and full stored-receipt validation.
- `src/study_agent_devkit/capability_gap/resolution_service.py`: DB-first
  materialization workflow with the external sink outside transactions.
- `src/study_agent_devkit/capability_gap/local_flywheel_promotion.py`:
  descriptor-relative, symlink-resistant, staged local materialization.
- `src/study_agent_devkit/capability_gap/__init__.py`: additive public receipt,
  protocol, and reference sink exports.
- `tests/capability_gap/resolution/materialization/`: baseline and adversarial
  receipt, claim, retry, process-loss, concurrency, and filesystem coverage.

## Verification

- `pytest -q`: 226 passed.
- `ruff check .`: passed.
- strict mypy with the pinned harness: passed, 49 source files.
- `scripts/run-runner-smoke.sh`: passed.
- `scripts/check-flywheel.sh`: passed.
- `git diff --check`: passed.
- Independent correctness review: approved.
- Independent defensive filesystem/data-integrity review: approved.
- Post-implementation architecture review: accepted.
- GitHub Actions run `30170541667`: passed on Python 3.12 and 3.13, including
  tests, Ruff, mypy, wheel build, clean-wheel import, and pinned harness
  provenance.

## Notes

- The stable sink ID is cached at injection; completed retries validate the
  database and return the persisted receipt without invoking sink properties or
  filesystem code.
- Synchronous failures remove only the inode-verified stage created by that
  call. Process-loss orphan stages remain ignored and never authorize reuse.
- Warning-only materialization findings remain reviewable; only errors block
  an accepted promotion.
