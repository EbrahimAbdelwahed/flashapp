# Log: GAP-06A resolution CAS and promotion outbox

Date: 2026-07-25
Area: capability-gap

## Summary

Implemented closed maintainer-resolution contracts, a separately versioned
SQLite resolution database, DB-first exact retry, terminal compare-and-set
resolution, and accepted-only canonical Flywheel promotion bundles. Resolution
state remains provider- and filesystem-free; GAP-06B retains ownership of
materialization claims, receipts, and local filesystem effects.

## Files Changed

- `src/study_agent_devkit/capability_gap/resolution_contracts.py`: canonical
  decision, command, resolution, goal, approved-artifact, and promotion codecs.
- `src/study_agent_devkit/capability_gap/resolution_store.py`: private exact
  schema, full-store validation, CAS persistence, and duplicate-graph checks.
- `src/study_agent_devkit/capability_gap/resolution_service.py`: trusted
  source/authority workflow, accepted-only planning, and callback ordering.
- `src/study_agent_devkit/capability_gap/proposal_store.py`: read-only lookup
  by decision and proposal ID.
- `src/study_agent_devkit/capability_gap/proposal_service.py`: public
  forwarding for the two trusted read operations.
- `src/study_agent_devkit/capability_gap/__init__.py`: additive public
  resolution contracts and service exports; private stores remain hidden.
- `src/study_agent_devkit/flywheel/materialization.py`: precompute the complete
  task ID set so valid forward dependencies are recognized.
- `tests/capability_gap/resolution/` and `tests/flywheel/adversarial/`:
  baseline and independent adversarial coverage.

## Verification

- `pytest -q`: 188 passed.
- `ruff check .`: passed.
- strict mypy with the pinned harness: passed, 42 source files.
- `scripts/run-runner-smoke.sh`: passed.
- `scripts/check-flywheel.sh`: passed.
- `git diff --check`: passed.
- Independent correctness review: approved.
- Independent architecture audit: accepted.
- Defensive data-integrity review findings were fixed and regression-tested.
- GitHub Actions run `30169026344`: passed on Python 3.12 and 3.13, including
  tests, Ruff, mypy, wheel build, clean-wheel import, and pinned harness
  provenance.

## Notes

- Exact retries read the resolution database before proposal source,
  authority, planner, or clock callbacks.
- Accepted promotion context and manifest fields are deterministically rendered
  and bound to their authority-bearing bundle fields.
- Non-null materialization receipts are rejected until GAP-06B lands the exact
  receipt codec and claim CAS.
- Concurrent first-open schema creation is serialized under `BEGIN IMMEDIATE`;
  genuinely partial version-0 schemas remain fail-closed.
