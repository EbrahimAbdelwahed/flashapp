# Log: GAP-05B private import and reproduction

Date: 2026-07-25
Area: capability-gap

## Summary

Implemented the private deterministic intake boundary against the pinned
`study-agent-harness` GAP-05A outbox.  Exact canonical bundles are validated
before a single SQLite `BEGIN IMMEDIATE` transaction; delivery claims are
idempotent, candidate dimensions are collision checked, and every contribution
has one reproduction result.  Candidate snapshots aggregate occurrence counts
in Python and never expose delivery identity.  Reproduction callbacks are a
trusted offline allowlist and receive only parsed redacted records.
Review hardening adds full SQLite schema validation, canonical deterministic
snapshots, consistent read transactions, corruption-checked retries, and
BaseException-safe rollback.
Adversarial closure additionally requires an exact SQLite schema/index set and
revalidates every candidate contribution and reproduction row before an
idempotent retry succeeds.

## Files Changed

- `src/study_agent_devkit/capability_gap/contracts.py`: closed import context,
  receipts, evidence, active-work, and reproduction contracts.
- `src/study_agent_devkit/capability_gap/store.py`: SQLite v1 schema and atomic
  import/snapshot repository.
- `tests/capability_gap/`: canonical, retry, collision, rollback, aggregation,
  and architecture coverage.
- `.github/workflows/ci.yml`, `pyproject.toml`: pinned dependency provenance
  and Python 3.12/3.13 build/test gates.

## Verification

- `PYTHONPATH=src:/private/tmp/study-agent-integrate/src python -m pytest -q`:
  34 passed.
- `python -m ruff check .`: passed.
- `MYPYPATH=src:/private/tmp/study-agent-integrate/src python -m mypy`:
  strict checks passed for 12 source files.
- `scripts/check-flywheel.sh`: passed.
- GitHub Actions run `30160680836`: Python 3.12 and 3.13 test, Ruff, mypy,
  wheel build, pinned dependency provenance, and clean-wheel import passed.
- `git diff --check`: passed.

## Notes

- GAP-05B is closed at `dc2d0048e1411e28db84d3d4f8c3f6e4575f57da`.
- GAP-05C is the next dependency-ready bead; GAP-07 remains the later
  adversarial end-to-end closure.
