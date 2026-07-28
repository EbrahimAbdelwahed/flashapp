# Log: GAP-05C immutable proposal and unresolved decision

Date: 2026-07-25
Area: capability-gap

## Summary

Implemented the closed, model-neutral GAP-05C proposal boundary. The package
freezes validated GAP-05B evidence, requests (but never grants) maintainer
authority, and persists one canonical unresolved decision package. The separate
SQLite store validates schema, projections, members, fingerprints, and package
bytes on every read and write. Security hardening keeps the mutable store
private behind the authority-enforcing service, bounds every codec and iterable
before materialization, and rejects malformed or oversized SQLite values before
conversion. Adversarial review also closes concurrent-winner, authority
cross-link, and multi-member lookup edge cases.

## Files Changed

- `src/study_agent_devkit/capability_gap/proposal_contracts.py`: canonical
  evidence, draft, proposal, and decision codecs with closed validation.
- `src/study_agent_devkit/capability_gap/proposal_store.py`: immutable package
  SQLite schema and fail-closed reconstruction.
- `src/study_agent_devkit/capability_gap/proposal_service.py`: authority,
  builder, clock, retry, and race-safe creation order.
- `src/study_agent_devkit/capability_gap/__init__.py`: additive public exports.
- `tests/capability_gap/proposals/`: contract, store, service, and architecture
  regression coverage.

## Verification

- `PYTHONPATH=src:/private/tmp/study-agent-integrate/src /Users/ebrahimabdelwahed/Desktop/Med/Lezioni/Audio_to_Sbobina/study-agent-harness/.venv/bin/python -m pytest -q`: 92 passed.
- `.../.venv/bin/python -m ruff check .`: passed.
- `MYPYPATH=src:/private/tmp/study-agent-integrate/src .../.venv/bin/python -m mypy`: passed, 24 source/test files.
- `scripts/check-flywheel.sh`: passed.
- `git diff --check`: passed.
- Independent architecture, semantic, adversarial, and security closeouts:
  approved with no open findings at `ad09379`.
- GitHub Actions run `30162912109`: Python 3.12/3.13 tests, Ruff, strict
  mypy, exact harness provenance, wheel build, and clean-wheel import passed.

## Notes

- No model/provider, network, subprocess, filesystem-path, Flywheel, GitHub,
  resolution, promotion, goal, or dispatch behavior was added.
- GAP-05C is closed at `07146ba32b888687ad10457d031b20524e25af8c`.
- GAP-06 is the next dependency-ready bead.
