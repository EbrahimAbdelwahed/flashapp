---
name: implementation-orchestrator
description: Convert an approved feature spec into grilled, polished tracer-bullet task beads, worker briefs, dependencies, and an execution order for Codex or multi-agent implementation.
---

# Implementation Orchestrator

Use this skill after a feature spec exists and the next step is implementation planning or worker delegation.

## Inputs

- Feature spec path or pasted spec.
- Current repo conventions.
- Any user constraints about speed, parallelism, or risk.

## Workflow

1. Require completed `grill-with-docs` evidence for the approved spec. If absent or decisions remain soft, run it before continuing.
2. Split the work into tracer-bullet task beads using `templates/task-bead.md`.
3. Add dependencies between beads.
4. For each bead, decide whether an existing worker profile fits or a new reusable profile should be created with `worker-profile-factory`.
5. Record the selected profile or profile-creation rationale in the bead.
6. Create worker briefs for ready beads using `templates/worker-brief.md`.
7. Define verification order.
8. Identify which tasks can run in parallel and which must be serialized.
9. Before each ready bead is dispatched, run `grill-with-docs` against that bead and persist the resulting decisions or explicit confirmation that no ADR/glossary change is needed.
10. Polish the graph: remove duplicate or unnecessary tasks and dependencies, reject cycles, and confirm every acceptance criterion is covered.

## Task Bead Rules

- One bead should be completable by one worker without redesigning the feature.
- One bead must fit a fresh context window and deliver an observable, independently verifiable outcome.
- Prefer vertical tracer bullets that cross the necessary layers. Do not split work into schema/API/UI/test layers when none is useful alone.
- Use `prefactor` only for a behavior-preserving change that makes a subsequent slice materially safer or smaller.
- Use `expand`, `migrate`, and `contract` for wide changes that cannot land as independently green vertical slices. Every migrate bead depends on expand; contract depends on every migrate bead.
- Each bead needs context, acceptance criteria, likely files/packages, verification, and out-of-scope boundaries.
- Each bead names the spec outcomes it covers and its grilling evidence. The graph is incomplete while any acceptance criterion has no owner.
- Avoid "implement X" beads without domain detail.
- Include a `Worker Profile` section that says `reuse <profile>`, `create <profile>`, or `none needed`.
- Use `worker-profile-factory` before launching a specialist if the work shape is likely to recur.
- If a bead changes public API, add docs or examples.
- If a bead changes prompt behavior, add eval fixtures.
- If a bead changes RAG behavior, add citation/source-grounding verification.

## Output

Return:

1. Execution summary.
2. Dependency graph as a short list or Mermaid diagram.
3. Task beads.
4. Worker profile reuse/create decisions.
5. Worker briefs for the first ready tasks.
6. Risks and review checkpoints.
