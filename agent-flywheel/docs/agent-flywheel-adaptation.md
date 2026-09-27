# Agent Flywheel Adaptation

## What We Keep

Agent Flywheel's strongest ideas are workflow primitives. Their public guides emphasize front-loaded markdown planning, plan-to-bead translation, dependency-aware routing, Agent Mail coordination, and repeated review/hardening before close:

- create a serious markdown plan before implementation;
- turn that plan into explicit tasks with dependencies;
- route work based on the dependency graph;
- coordinate agents outside chat scrollback;
- reserve edit surfaces when agents work concurrently;
- review with fresh context before closing work.

These ideas map well to the study-agent project.

References:

- Agent Flywheel complete guide: https://agent-flywheel.com/complete-guide
- Agent Flywheel core loop: https://agent-flywheel.com/core-flywheel
- Agent Flywheel setup repository: https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup

## What We Do Not Adopt Immediately

We do not require the full VPS/tmux/swarm environment on day one. The early project needs discipline more than maximum parallelism.

Deferred or selectively reused tools:

- `br` / beads: already supported through `flywheel-core.py` and `flywheel-runner.py beads --create-br-beads`; keep markdown task artifacts as fallback.
- `bv`: already wrapped for graph-aware triage; use it when bead volume makes manual ordering unreliable.
- Agent Mail: already wrapped but not treated as durable source of truth until strict readiness is clean.
- NTM: adopt when terminal orchestration becomes the bottleneck.
- UBS / bug scanners: useful as optional extra review after native project verification, not as a replacement for project tests.
- Command guard / shell safety ideas: useful conceptually; our runner now uses explicit `--execute`, publication gates, and local overwrite preflights for mutating steps.

## Adapted Core Loop

```text
rough product request
-> grill-with-docs
-> feature-spec-architect
-> reviewed spec
-> implementation-orchestrator
-> task beads
-> grill-with-docs for each ready bead
-> worker briefs
-> implementation
-> worker reports
-> draft PR / GitHub Actions
-> automatic Codex GitHub review
-> docs/ADR/update
```

The runner implementation expands this into:

```text
intake
-> context
-> spec
-> validate --stage spec
-> beads
-> profiles
-> briefs
-> validate --stage dispatch
-> dispatch
-> worker-report
-> optimize
-> git-lane
-> pr-lane --draft
-> GitHub Actions CI
-> review --github-actions-run <actual-run-id>
-> pr-lane (existing draft becomes ready)
-> status
```

## Why This Fits Study-Agent Work

Study-agent features are cross-cutting. A single feature can touch:

- domain model;
- RAG retrieval;
- prompt policy;
- eval fixtures;
- UI;
- scheduling logic;
- persistence;
- audit trails.

Without an explicit task graph, agents will either duplicate work or make incompatible assumptions. The adapted flywheel keeps architecture decisions centralized while allowing implementation to run in parallel.

## Import Candidates

Import or mimic:

- Multi-model plan synthesis when starting large product areas. This belongs in planning prompts and skills, not in the runner CLI.
- Bead polishing passes before implementation. Add future runner checks for duplicate tasks, missing dependencies, weak acceptance criteria, and broad file scopes.
- Agent Mail thread discipline using bead IDs. Keep it optional until upstream strict readiness is reliable.
- Swarm monitoring concepts. A dashboard can come later, but the durable source of truth should stay in run manifests, beads, reports, and review artifacts.

Do not import wholesale:

- VPS-first setup and dangerous velocity defaults. Our workflow should work locally inside Codex and remain conservative around git, filesystem, and publication.
- A fixed worker taxonomy. The orchestrator should generate reusable worker profiles from actual task shape.
- Any flow that treats chat memory, Agent Mail archives, or command output alone as publication proof.

## Integrated Planning Discipline

The Flywheel remains the only execution and state system. `grill-with-docs` is mandatory before spec approval and again before every ready bead is dispatched. Its ADR, glossary, and decision outputs become durable inputs to the normal Flywheel artifacts; a bead with unresolved grilling decisions is blocked.

Task graphs additionally follow these rules:

- default to vertical tracer bullets that produce independently observable behavior;
- keep each bead small enough for one worker in a fresh context window;
- use a behavior-preserving `prefactor` bead only when it materially simplifies later delivery;
- model unavoidable wide changes as `expand -> migrate batches -> contract` while keeping the repository green;
- polish graphs for duplicate tasks, cycles, weak acceptance criteria, unnecessary dependencies, and spec-to-bead coverage before dispatch.

These rules enrich task creation and validation; they do not introduce `.scratch` tickets or another issue-tracker source of truth.

## Current Divergences From Agent Flywheel

- Agent Flywheel prefers direct `br` beads after planning; our runner creates markdown artifacts first and links `br` when requested. This is slower but safer for early evolution and OSS polish.
- Agent Flywheel assumes humans monitor Agent Mail threads; our runner now requires explicit worker-report artifacts so status can be checked without reading chat.
- Agent Flywheel optimizes for high parallelism on dedicated VPS infrastructure; our current target is reliable local orchestration that scales with Codex workers while preserving reviewable code quality.
- Agent Flywheel's core rhythm is plan, encode, route, coordinate, execute/close; our runner adds publication gates between execute and close so git/PR actions cannot run from incomplete evidence.
