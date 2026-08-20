# Worker Dispatch: FlashApp 1.0 App Store hardening

Date: 2026-08-20
Run ID: `flash-app-store-v1`

## Orchestrator Instructions

Call `multi_agent_v1.spawn_agent` once per packet using the `spawn_agent` object in `worker-dispatch.json`.
Do not spawn two workers that own overlapping file scopes unless the task graph explicitly allows it.

## Packets

### `sas-03a-account-routing`

- Task: `docs/tasks/flash-app-store-v1/sas-03a-account-routing.md`
- Brief: `docs/worker-briefs/flash-app-store-v1/sas-03a-account-routing.md`
- br id: `none`
- File hints: Packages/FlashUpKit/Sources/FlashUpData/AccountStores/, Packages/FlashUpKit/Sources/FlashUpData/Persistence/, Packages/FlashUpKit/Sources/FlashUpData/Media/, Packages/FlashUpKit/Sources/FlashUpData/Repositories/, Packages/FlashUpKit/Tests/FlashUpDataTests/, App/AppEnvironment.swift

```text
You are a Codex worker implementing one scoped flywheel task.

You are not alone in this codebase. Other agents or the user may have active changes. Do not revert unrelated edits; inspect and work with the current tree.

Project: `/Users/ebrahimabdelwahed/Desktop/Dev/flashapp`
Run ID: `flash-app-store-v1`
Task ID: `sas-03a-account-routing`
- `br` bead id: not materialized or not linked

Read first:
- `docs/specs/flashapp-1-0-app-store-hardening.md`
- `docs/flywheel-runs/flash-app-store-v1/context-pack.md`
- `docs/tasks/flash-app-store-v1/sas-03a-account-routing.md`
- `docs/worker-briefs/flash-app-store-v1/sas-03a-account-routing.md`
- Applicable `AGENTS.md` files for any path you touch.

Assignment:
- Implement only the task described by `docs/tasks/flash-app-store-v1/sas-03a-account-routing.md` and `docs/worker-briefs/flash-app-store-v1/sas-03a-account-routing.md`.
- Keep the change small, reviewable, and within the file/package scope listed in the task.
- If scope is unclear or product/architecture risk appears, write a decision request instead of guessing.
- Add or update tests for changed behavior.
- Run the verification commands listed in the task bead.

Coordination protocol:
- If `br` is available and a bead id is listed, claim/update that bead before editing.
- If Agent Mail is active, reserve the likely file paths before editing and release reservations at the end.
- Leave progress in the task bead or coordination thread if work is partial.

Final report format:
- Files changed:
- Behavior implemented:
- Verification commands and outcomes:
- Open questions or blockers:
- Follow-up beads needed:

```
