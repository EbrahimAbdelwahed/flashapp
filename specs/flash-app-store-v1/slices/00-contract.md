# Slice 00 — Contract and run

## Contract unlocked

All workers operate from one owner-approved 1.0 scope and one dependency graph; old Groups,
two-store, price, onboarding, backup and TestFlight assumptions are no longer dispatchable.

## Seam and ownership

ADR-006 owns the decision. The architecture brief remains product truth, the implementation
spec remains engineering truth, the feature spec owns acceptance criteria, and this folder
owns live handoff state. The Flywheel manifest owns execution state.

## Human-visible artifact

Review ADR-006, the amended source documents, the task graph and the human-gate ledger.

## Verification

- Flywheel spec and dispatch validation report zero errors.
- Every task has one owner, dependencies, file boundaries and evidence.
- The old `flash-up-v1` plan is marked superseded where it conflicts.
- Git status proves `assets/emma-avatar/` remains untracked and unchanged.

## Feedback that changes this slice

Only an owner change to launch scope, price, persistence topology, backup semantics or
release gates. Such a change amends ADR-006 before workers proceed.

