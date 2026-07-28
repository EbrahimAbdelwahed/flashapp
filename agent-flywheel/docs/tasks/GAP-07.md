# GAP-07: Adversarial local-chain closure

Status: Done
Priority: P1
Depends on: GAP-06B

## Goal

Prove the completed local capability-gap chain end to end, from a trusted
public-harness outbox export through private import/reproduction, immutable
proposal, authenticated terminal resolution, accepted-only promotion, and
idempotent local Flywheel materialization.

## Risk

Medium. This bead adds no production behavior, authority, persistence, or
dependency. Its value is independent cross-boundary evidence and release
closure.

## Allowed files

- `tests/capability_gap/e2e/**`
- narrow reusable test fixtures under that directory
- this task and one factual log

## Forbidden

- production source changes
- new dependencies
- provider/model/network calls
- product or learner state
- `br`, dispatch packets, worker spawn, Codex goal API, Git/GitHub, merge,
  release, or deployment
- weakening existing unit or adversarial assertions

## Required scenarios

- Accepted `planning_only` resolves and materializes one validator-clean,
  self-contained, non-dispatched Flywheel run with no goal file.
- Accepted `planning_and_implementation_goal` adds the exact authorized goal
  artifact but does not start it or create task state.
- Rejected, deferred, and duplicate outcomes create no promotion, claim,
  receipt, or run tree.
- Exact resolution and materialization retries skip all callbacks and return
  the first canonical winner.
- A simulated loss after the local atomic rename but before receipt persistence
  converges through the same claimed sink and exact existing tree.
- Corruption at each persisted boundary fails closed before later callbacks or
  filesystem effects.
- Architecture assertions prove the chain remains model/provider agnostic and
  excludes dispatch, publication, and product behavior.

## Done

- Independent end-to-end tests pass offline on the pinned public harness.
- Full pytest, Ruff, strict mypy, runner smoke, scaffold checks, wheel build,
  clean-wheel import, and Python 3.12/3.13 CI are green.
- Independent semantic review finds no missing cross-boundary invariant.
