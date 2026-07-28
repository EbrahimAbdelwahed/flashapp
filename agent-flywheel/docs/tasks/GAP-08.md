# GAP-08: Accepted-only GitHub branch and draft pull request

Status: Done
Priority: P2
Depends on: GAP-07

## Goal

Implement `docs/specs/capability-gap-github-draft-pr.md` without widening
maintainer acceptance into merge, release, deployment, or GitHub issue
authority.

## Risk

High. This bead adds an external provider adapter, public contracts, outbound
authentication, separate persistence, and restart reconciliation.

## Allowed files

- `src/study_agent_devkit/capability_gap/github_*.py`
- additive exports in `src/study_agent_devkit/capability_gap/__init__.py`
- `tests/capability_gap/github/**`
- `pyproject.toml` or CI only if an existing packaging gate requires an additive
  adjustment
- this task, its spec/ADR, and factual review/log artifacts

## Forbidden

- changes to GAP-05B/C or resolution-store schemas
- changes to accepted promotion bytes or GAP-07 local materialization
- `git`, `gh`, shell, provider SDK, model, learner/product, hosted intake,
  issue, merge, release, or deployment behavior
- secrets in arguments, persistence, receipts, logs, fixtures, or errors
- real GitHub calls in tests

## Required gates

- Architecture plan review before production edits.
- Resolve and persist a publication authorization before invoking `publish` so
  effects and retries remain explicit.
- Independent implementation and test ownership where file scopes do not
  overlap.
- Security and semantic code review.
- GitHub Actions for the exact commit must pass; local executable verification
  is forbidden by repository policy.

## Done

- Every acceptance criterion in the approved spec has executable offline
  evidence in `tests/capability_gap/github/**`.
- Reviews have no unresolved high- or medium-severity findings.
- The exact commit `ac884212eb05b5ca916bd6b2345ec4d77b5dbf3a` is green in
  [GitHub Actions run 30205827258](https://github.com/EbrahimAbdelwahed/study-agent-devkit/actions/runs/30205827258)
  on Python 3.12 and 3.13, including 317 tests, Ruff, strict mypy, wheel and
  clean-wheel import checks, and the Flywheel smoke.
- The approved behavior source is
  `docs/specs/capability-gap-github-draft-pr.md`; this task, that spec, and
  the factual GAP-08 log record the same completed contract.
