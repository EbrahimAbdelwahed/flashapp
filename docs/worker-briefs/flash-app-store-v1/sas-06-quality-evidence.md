# Worker Brief: sas-06-quality-evidence

## Assignment

Implement `sas-06-quality-evidence` from `docs/specs/flashapp-1-0-app-store-hardening.md`.

Task title: sas-06-quality-evidence Build the App Store quality and evidence gates

## Read First

- `docs/decisions/ADR-006-app-store-v1-contract.md`
- `specs/flash-app-store-v1/slices/06-quality-evidence.md`
- `docs/testing/app-store-v1-gates.md`
- `docs/specs/flashapp-1-0-app-store-hardening.md`
- `docs/tasks/flash-app-store-v1/sas-06-quality-evidence.md`
- `docs/flywheel-runs/flash-app-store-v1/context-pack.md`
- `docs/worker-profiles/app-store-release-governor.md`
- Project `AGENTS.md` files that apply to touched paths.

## Scope

You may change:

- Paths listed in the task bead after inspecting the codebase.

Do not change:

- Unrelated modules.
- Files reserved by another active worker.
- Public behavior outside the task acceptance criteria.

## Requirements

- Claim or reserve the bead before editing when `br`/Agent Mail are active.
- Inspect existing patterns before editing.
- Keep changes small and reviewable.
- Add or update tests for changed behavior.
- Update docs if public behavior changes.
- If a material decision is needed, create a decision request with
  `flywheel-runner.py decision-request` instead of burying the question in chat.

## Verification

Run the commands listed in the task bead. If a command cannot run, explain why.

## Report Back

Return:

- files changed;
- behavior implemented;
- verification results;
- unresolved questions;
- follow-up beads needed.
