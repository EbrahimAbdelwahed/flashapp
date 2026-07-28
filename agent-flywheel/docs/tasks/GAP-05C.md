# GAP-05C: Immutable proposal and unresolved decision

Status: Done
Priority: P1
Depends on: GAP-05B

## Goal

Create one immutable draft proposal and one unresolved maintainer decision for
one frozen GAP-05B candidate or explicitly reviewed cohort, without granting
implementation or publication authority.

## Worker contract

### Allowed files

- `src/study_agent_devkit/capability_gap/proposal_*.py`
- `src/study_agent_devkit/capability_gap/__init__.py`
- `tests/capability_gap/proposals/**`
- `pyproject.toml` and `.github/workflows/ci.yml` only if an existing gate needs
  additive wiring
- This task, its spec, and one focused log

### Forbidden files and behavior

- GAP-05B contracts/store behavior or schema
- Public `study-agent-harness`
- Existing Flywheel runner behavior
- `sbobby-web`
- Model/provider calls, network, subprocess, arbitrary filesystem paths,
  Flywheel/GitHub mutations
- Resolution, promotion, goals, dispatch, repository merge, release, or
  deployment
- New dependencies

## Invariants

- Consume only immutable GAP-05B snapshots.
- Delivery identity and sender scope never enter proposal evidence.
- Independent gaps never share a proposal without exact trusted merge context.
- Every gap key belongs to at most one proposal.
- Cohort, evidence, proposal, and decision fingerprints are canonical and
  recomputed on decode; package bytes are the sole canonical stored record.
- Decision status is only `unresolved`; there is no resolution method.
- Multi-key cohorts require the injected merge authority; exact retry returns
  exact persisted bytes and skips merge authority, builder, and clock.
- All mutation is one SQLite transaction; corruption fails closed.

## Acceptance criteria

- All cases in
  `docs/specs/capability-gap-proposal-decision.md` pass.
- Before GAP-06, no accepted artifact, goal, code mutation, dependency,
  external issue, network effect, or dispatch can be created.
- Independent adversarial tests and semantic/security reviews have no open
  findings.
- Ruff, strict mypy, full tests, build, clean wheel, and Python 3.12/3.13 CI
  pass.

## Implementation order

1. Closed codecs and fingerprint contracts.
2. Draft/cohort validation and trusted builder protocol.
3. Exact SQLite proposal store and read reconstruction.
4. Creation service with retry/race/process-loss semantics.
5. Focused, adversarial, architecture, and packaging tests.
6. Independent semantic/security closeout.
