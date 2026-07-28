# GAP-05B: Devkit import, deduplication, and reproduction

Status: Done
Priority: P1
Depends on: public harness GAP-05A at
`e74c4da9c737f97dd460c606dbb7afcc66137b84`

## Goal

Implement the private, deterministic import of one hostile redacted outbox
bundle into candidate aggregates and allowlisted offline reproduction evidence.

## Required context

- `docs/specs/capability-gap-private-factory.md`
- Public `specs/capability-gap-feedback/beads/GAP-05B-devkit-import-reproduction.md`
- Public `docs/decisions/ADR-0011--capability-gap-observation-and-promotion.md`
- Public `src/study_agent/feedback/outbox.py`

## Allowed files

- `pyproject.toml`
- `.github/workflows/ci.yml`
- `src/study_agent_devkit/capability_gap/**`
- `src/study_agent_devkit/__init__.py`
- `tests/capability_gap/**`
- This task and the private-factory spec
- One focused implementation log

## Forbidden changes

- Public harness code or codec copies
- Existing flywheel runner behavior
- `sbobby-web`, medical materials, model calls, transports, GitHub adapters
- Proposal, decision, promotion, goal, dispatch, merge, release, or deployment

## Acceptance criteria

- All GAP-05B acceptance criteria in the private-factory plan pass.
- Failure and retry behavior is atomic across a real SQLite reopen.
- Candidate/reproduction public snapshots contain no delivery identity.
- Dependency and authority architecture tests pass.
- Build, clean-wheel import, Ruff, strict mypy, and focused/full tests pass.

## Verification

```bash
python -m pytest tests/capability_gap
python -m ruff check .
python -m mypy
python -m build
```
