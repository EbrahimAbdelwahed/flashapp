# GAP-06A: Resolution CAS and accepted promotion outbox

Status: Done
Priority: P1
Depends on: GAP-06P

## Goal

Persist one maintainer-authorized terminal resolution and create one canonical
promotion job only for a fully ready accepted proposal.

## Allowed files

- `src/study_agent_devkit/capability_gap/resolution_*.py`
- additive read-only `get_by_decision_id` and `get_by_proposal_id` in the
  private GAP-05C store and public proposal service
- additive public exports
- `tests/capability_gap/resolution/**`
- this task/spec and one log

## Forbidden

- GAP-05B/GAP-05C schema or mutation changes
- filesystem adapters or Flywheel runner changes
- public mutable stores
- model/provider/network/subprocess/GitHub/Git/product behavior
- worker spawning, merge, release, or deployment

## Done

- All GAP-06A contract/CAS/outbox cases in the approved spec pass.
- Independent adversarial, semantic, and security review is clean.
- Full local and remote gates are green.
