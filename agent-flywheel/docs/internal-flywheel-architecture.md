# Internal Agent Flywheel Architecture

Status: Draft
Date: 2026-06-21

## 1. Purpose

This flywheel is an internal development system, not part of the future study-agent OSS core or product. Its job is to convert the user's available agent tokens into sustained, supervised implementation progress with minimal babysitting.

The system should let the user:

- describe work in rough natural language;
- receive refined specs and implementation plans;
- launch or assign agents against ready tasks;
- inspect beads, blockers, progress, and agent questions from desktop or CLI-first surfaces;
- answer product/architecture questions asynchronously;
- keep workers moving while the user is not actively babysitting each thread;
- improve prompts, skills, AGENTS rules, and worker protocols after each conversation.

## 2. Design Principles

- **Separate factory from product.** The flywheel builds the study-agent platform, but does not become part of that platform.
- **Externalize state.** Work cannot live only in chat. Specs, beads, messages, reservations, reviews, and decisions must be durable.
- **Plan before parallelism.** More agents only help after the task graph is good.
- **Make blockers inspectable.** An agent question must become a structured decision request, not a buried chat message.
- **Core loop before remote oversight.** Desktop, CLI, and local web surfaces are enough for the first version. Mobile/dashboard oversight is useful later, but only after the task graph, coordination, and review loop work.
- **Create worker profiles dynamically.** The orchestrator should create reusable worker profiles from the actual task scope, repository context, and needed expertise instead of relying on a fixed primary taxonomy.
- **Optimize for unattended forward motion.** Agents should assume minor reversible details, document assumptions, and only block on real product/architecture decisions.
- **Continuously improve the factory.** At the end of each conversation, a workflow optimizer reviews what slowed the session and proposes updates to skills, prompts, templates, or AGENTS rules.

## 3. High-Level Architecture

```text
Human
  |
  | rough idea, approvals, answers from desktop/CLI/local dashboard
  v
Oversight Surfaces
  |
  +-- Beads / task graph
  +-- Agent questions / decision requests
  +-- Agent status and reservations
  +-- Review queue
  +-- Workflow improvement queue
  |
  v
Flywheel Control Plane
  |
  +-- Spec Architect
  +-- Orchestrator
  +-- Router / Scheduler
  +-- Dynamic Worker Profile Manager
  +-- Review Manager
  +-- Workflow Optimizer
  |
  v
Execution Substrate
  |
  +-- Codex threads / CLI sessions
  +-- Optional NTM/tmux swarm
  +-- Git worktrees / branches
  +-- Project repository
  |
  v
Durable State
  |
  +-- br / beads or compatible task store
  +-- bv or compatible graph-aware routing
  +-- Agent Mail or compatible message store
  +-- Git archive / markdown ledger
  +-- Review and decision artifacts
```

## 4. Core Components

### 4.1 Spec Architect

Turns a rough user request into an implementation-ready feature spec.

Responsibilities:

- ask only material questions;
- identify product, architecture, prompt, RAG, SRS, and persistence implications;
- define scope and non-goals;
- create acceptance criteria;
- decide whether ADRs or evals are required;
- produce initial task candidates.

Outputs:

- feature spec;
- open questions;
- decision assumptions;
- candidate beads.

### 4.2 Orchestrator

Turns approved specs into executable task graphs and worker briefs.

Responsibilities:

- split work into beads;
- assign dependencies;
- identify parallel tracks;
- infer the worker profile each bead needs;
- reuse existing worker profiles when they fit;
- create new worker profiles when the task demands different expertise, tools, or context;
- decide when online/library/framework research is needed before implementation;
- create worker prompts from profile plus bead context;
- choose verification gates;
- mark tasks that require user decisions before execution.

Outputs:

- beads;
- dependency graph;
- worker profile definitions or profile reuse decisions;
- worker briefs;
- launch plan;
- risk checkpoints.

### 4.3 Task Graph / Beads Store

The source of truth for executable work.

Required fields:

- `id`
- `title`
- `status`
- `priority`
- `type`
- `depends_on`
- `blocks`
- `owner`
- `worker_profile`
- `files_scope`
- `acceptance_criteria`
- `verification`
- `decision_requests`
- `created_from_spec`
- `last_activity`

Recommended lifecycle:

```text
draft
-> ready
-> claimed
-> in_progress
-> review
-> rework
-> done
```

Blocked tasks use:

```text
blocked
-> waiting_user
-> waiting_worker
-> waiting_dependency
-> waiting_external
```

### 4.4 Router / Scheduler

Selects the next useful work.

Responsibilities:

- surface ready beads;
- prioritize unblockers;
- avoid oversaturating the same files or packages;
- keep a backlog of ready worker briefs;
- suggest when to spawn more agents or pause.

Agent Flywheel uses `bv` for this. Our version should initially wrap or consume `bv --robot-*` output when available rather than rebuild graph analysis.

### 4.5 Agent Coordination Layer

Coordinates claims, progress, questions, and file reservations.

Minimum capabilities:

- agent identity;
- task claim;
- thread per bead;
- progress updates;
- advisory file reservations;
- handoff messages;
- completion summaries.

Agent Flywheel uses Agent Mail. We should prefer direct reuse if it works well in the local environment because it already has:

- MCP tools;
- Git-backed archives;
- SQLite live state;
- file reservations;
- inboxes and threads;
- a `/mail` web UI surface;
- doctor/repair/reconstruct workflows.

### 4.6 Dynamic Worker Profile Manager

Defines reusable worker profiles and launch prompts. A worker profile is not a permanent job title; it is a scoped execution pattern for a recurring kind of work.

The primary model is:

```text
bead scope + repo context + risk + required expertise
-> profile reuse or profile creation
-> launch prompt
-> verification and review gates
```

Profile fields:

- `id`
- `purpose`
- `when_to_use`
- `required_context`
- `research_policy`
- `allowed_files`
- `forbidden_decisions`
- `tools_and_commands`
- `verification`
- `review_gate`
- `stop_conditions`
- `report_format`

The orchestrator should maintain a small registry of proven profiles, such as:

- spec/refinement profile;
- implementation profile for a specific package or subsystem;
- framework/library research profile;
- test/eval profile;
- automatic Codex GitHub review (external; no local reviewer profile);
- documentation/ADR profile;
- flywheel-improvement profile.

These are examples, not the primary architecture. If a bead needs a study-domain/RAG/SRS/frontend/backend specialist, the orchestrator creates or reuses a profile with that scope. If a bead depends on unfamiliar external behavior, the profile can explicitly include online/library/framework research before implementation.

Each worker prompt must specify:

- scope;
- allowed files/packages;
- forbidden decisions;
- whether research is allowed or required;
- expected verification;
- stop conditions;
- report format;
- when to create a decision request.

### 4.7 Review Manager

Keeps quality from degrading under parallelism.

Review gates:

- automatic Codex GitHub semantic review, with fixes returned to the task owner;
- relevant test/lint/typecheck/build/eval gates in GitHub Actions;
- human approval for product/architecture-sensitive changes.

Review output becomes:

- approval;
- required fixes;
- new beads;
- ADR update;
- workflow improvement suggestion.

### 4.8 Decision Request System

This is the key addition for asynchronous supervision.

Agents should not ask free-form chat questions unless the current conversation is active. They should create structured decision requests.

Decision request fields:

- `id`
- `bead_id`
- `agent`
- `severity`: `blocking | important | optional`
- `decision_type`: `product | architecture | implementation | safety | dependency | release`
- `question`
- `context`
- `options`
- `recommended_option`
- `consequence_if_unanswered`
- `default_after_timeout`
- `expires_at`
- `links`

Default policy:

- Blocking product/architecture decisions wait for the user.
- Reversible implementation details can proceed with documented assumptions.
- Safety/destructive actions require explicit approval.
- If unanswered optional requests expire, the agent proceeds with the recommended default and records it.

### 4.9 Dashboard / Remote Oversight

The dashboard is optional after the core flywheel works. It should not be a phase-one requirement, and mobile-first oversight is not currently required.

Early oversight can be handled through:

- markdown plans and handoffs;
- `br`/beads views;
- `bv` ready-work output;
- Agent Mail inboxes and threads;
- local terminal summaries;
- local web UI if Agent Mail already provides one.

A later dashboard can become the user's remote cockpit.

Primary jobs:

- show ready/in-progress/blocked beads;
- show agent questions requiring human input;
- show agent status and recent activity;
- show file reservations and collisions;
- show review queue;
- allow quick approvals, rejections, and answers;
- allow task reprioritization;
- allow pausing/resuming agents or tracks;
- show workflow improvement proposals.

Possible later views:

1. **Today**
   - active agents;
   - blocked beads;
   - urgent questions;
   - review items;
   - latest completions.

2. **Questions**
   - answer decision requests;
   - approve/reject recommended option;
   - mark "needs desktop";
   - ask orchestrator to synthesize a recommendation.

3. **Beads**
   - ready;
   - in progress;
   - blocked;
   - review;
   - done.

4. **Agent Threads**
   - bead-linked messages;
   - progress updates;
   - completion summaries;
   - handoffs.

5. **Review Queue**
   - changes awaiting review;
   - failed checks;
   - requested fixes;
   - PR/readiness state.

6. **Factory Improvements**
   - proposed edits to skills, prompts, AGENTS, templates;
   - approve/apply/defer/reject.

Possible later actions:

- answer decision request;
- approve default;
- reject path;
- mark blocked;
- change priority;
- assign/reassign owner;
- request review;
- pause agent/track;
- resume ready work;
- create follow-up bead;
- approve workflow improvement proposal.

Explicit non-goals for remote oversight:

- editing code;
- running arbitrary shell commands;
- approving destructive commands without full diff/context;
- merging large changes blindly.

### 4.10 Workflow Optimizer

Runs at the end of each conversation or batch.

Goal:

Detect where the flywheel itself wasted time, caused confusion, or needed human babysitting, then propose concrete improvements.

Inputs:

- conversation transcript or summary;
- beads touched;
- decision requests created;
- blockers encountered;
- review findings;
- verification failures;
- user corrections;
- repeated agent mistakes.

Checks:

- Did agents ask avoidable questions?
- Were worker prompts underspecified?
- Did AGENTS.md miss a rule?
- Did a task bead lack context or acceptance criteria?
- Did a reviewer repeatedly catch the same issue?
- Did prompt/eval/RAG/SRS rules need to be stricter?
- Did oversight need a new decision type, CLI summary, mail thread convention, or dashboard view?
- Did tool adoption need to move up a phase?

Outputs:

- workflow improvement proposals;
- suggested edits to `AGENTS.md`;
- suggested edits to skill instructions;
- new templates or checklist fields;
- new quality gates;
- follow-up beads.

Important rule:

The workflow optimizer proposes changes. Automatic Codex GitHub review assesses code changes; the user approves product and workflow decisions before they become canonical.

## 5. End-to-End Flows

### 5.1 Feature Creation Flow

```text
User rough idea
-> Spec Architect asks material questions
-> Spec is generated
-> User approves or edits
-> Orchestrator creates beads
-> Router identifies ready beads
-> Dynamic Worker Profile Manager selects or creates profiles
-> Orchestrator launches workers with scoped prompts
-> Agents coordinate through Mail/reservations
-> Workers implement and verify
-> Review Manager reviews
-> Completed beads update graph
-> Workflow Optimizer audits session
```

### 5.2 Asynchronous Decision Flow

```text
Worker hits real blocker
-> creates Decision Request
-> Agent Mail thread, CLI summary, or later dashboard notification
-> User opens the available oversight surface
-> sees context, options, recommended default
-> answers or defers
-> Agent receives answer in bead thread
-> Work resumes
```

### 5.3 Unattended Work Flow

```text
Before leaving desktop:
  orchestrator prepares ready queue
  oversight surface shows all blocking questions cleared
  agents are launched with ready beads

While away:
  agents claim beads
  reserve files
  implement
  create decision requests only when needed
  close or send to review

From oversight surface:
  user answers blockers
  reprioritizes
  pauses unsafe tracks

On return:
  review status, diffs, mail threads, and quality gates
  run merge/final quality gates
```

### 5.4 Workflow Improvement Flow

```text
Conversation ends
-> Workflow Optimizer reviews transcript/artifacts
-> creates improvement proposals
-> reviewer checks proposals
-> user approves high-impact changes
-> skills/prompts/AGENTS/templates updated
-> new workflow version recorded
```

## 6. Comparison With Agent Flywheel

### 6.1 Directly Useful Upstream Concepts

- **Core loop:** plan, encode, triage, coordinate, implement, close.
- **Artifact ladder:** raw idea, markdown plan, bead graph, ready bead, claimed bead, completed bead.
- **Plan/bead/code space separation:** debates in plan space, dependencies in bead space, implementation in code space.
- **Coordination triangle:** `br` for task state, `bv` for routing, Agent Mail for coordination.
- **File reservations:** advisory locks to reduce collisions.
- **Agent peer review:** agents review other agents' work.
- **Fresh-eyes review prompts:** useful for post-implementation quality passes.
- **Robot modes:** machine-readable outputs are better than TUI-only workflows.

### 6.2 Direct Reuse Candidates

- `br` / beads: use as task store when the workflow moves beyond markdown.
- `bv`: use for graph-aware ready work and triage.
- Agent Mail: use for claims, threads, inboxes, reservations, and possibly the first web UI.
- NTM: use later for local/VPS tmux-based agent orchestration.
- UBS: optional extra scanner after native quality gates.
- CASS/CM: later memory/search layer for prior agent sessions and repeated workflow lessons.
- RU: later multi-repo sync/commit automation if the work spans many repos.
- SLB/DCG: later safety layer for destructive approvals.

### 6.3 Differences From Agent Flywheel

| Area | Agent Flywheel | Our Flywheel |
| --- | --- | --- |
| Primary goal | Configure an agentic coding environment | Build and run a private development factory |
| Target user | General agentic coder | One user building a study-agent platform |
| Product coupling | Toolchain itself is product | Workflow must stay separate from study-agent product |
| Mobile | Not mobile-first; site notes mobile-first development is not the target | Same: mobile-first oversight is not a current requirement |
| Remote oversight | Web/mail surfaces can help observe and steer agents | Optional later dashboard after the local core loop works |
| Question handling | Agent Mail threads and overseer messages | Structured decision requests surfaced through Mail/CLI first, dashboard later |
| Quality focus | Broad bug scanning and peer review | Study-agent-specific gates: RAG, prompts, evals, SRS, provenance |
| Parallelism | VPS/tmux swarm is central | Start Codex-first, add NTM/VPS when justified |
| Prompt system | General coding prompts | Dynamic worker profiles plus workflow optimizer |

### 6.4 What Agent Flywheel Adds That We Had Not Fully Included

- **Overseer messages via Agent Mail:** useful for broadcasting human instructions to agents from Mail/CLI first and dashboard later.
- **Archive + SQLite split:** excellent pattern for our own control plane: SQLite for live dashboard state, Git/Markdown for durable audit.
- **Doctor/repair/reconstruct mindset:** the workflow state itself needs health checks and recovery.
- **Robot-first commands:** every future dashboard feature should have a machine-readable command/API, not only UI.
- **Approval workflows through inboxes:** useful for high-risk operations and later two-person review.
- **Session search and procedural memory:** CASS/CM-like layer is useful once the flywheel accumulates many sessions.
- **Resource protection:** if running many agents locally/VPS, resource limits and process health matter.

## 7. Dashboard Architecture Options

Dashboard work is optional until the core local loop works with durable beads, routing, Agent Mail coordination, dynamic worker profiles, and review gates.

### Option A: Reuse Agent Mail Web UI First

Use Agent Mail's `/mail` web UI as the initial remote inbox/threads surface.

Pros:

- fastest path;
- already connected to agent messages;
- already backed by SQLite/Git archive;
- less custom dashboard work.

Cons:

- may not expose beads/review/decision requests exactly how we want;
- mobile UX may be insufficient;
- tied to Agent Mail's model.

Use opportunistically if it works locally. Do not block the core flywheel on it.

### Option B: Build Thin Custom Dashboard Over Existing Stores

Create a small Next.js app that reads:

- Agent Mail HTTP/API or archive;
- `.beads/issues.jsonl` / `br --json`;
- `bv --robot-*`;
- local review artifacts.

Pros:

- best fit for eventual remote oversight;
- can show beads, decisions, reviews, and workflow improvements together;
- keeps Agent Mail as backend rather than UI constraint.

Cons:

- more implementation work;
- needs auth and safe remote access.

This is the likely long-term path.

### Option C: Hosted Control Plane

Run dashboard as a private hosted app with an agent-side bridge.

Pros:

- true mobile remote access;
- notifications;
- works while away from local network.

Cons:

- auth/security burden;
- external exposure of sensitive development metadata;
- more moving parts.

Only adopt after local/VPS flow is proven and remote oversight is worth the security cost.

## 8. Security and Remote Access

Remote access must be safe by default if/when it is added.

Requirements:

- authentication;
- HTTPS if exposed beyond localhost;
- no arbitrary shell execution from remote UI;
- explicit high-risk approval flow;
- redacted secrets;
- action audit log;
- per-action context before approval;
- read-only mode option;
- ability to pause agents quickly.

Recommended first remote deployment:

- run on a VPS or local machine;
- expose through Tailscale, Cloudflare Tunnel, or similar private tunnel;
- dashboard actions call constrained APIs, not shell commands.

## 9. Data Model Sketch

### Bead

```ts
type Bead = {
  id: string
  title: string
  status: "draft" | "ready" | "claimed" | "in_progress" | "review" | "rework" | "blocked" | "done"
  priority: "P0" | "P1" | "P2" | "P3" | "P4"
  type: "epic" | "feature" | "task" | "bug" | "review" | "chore"
  dependsOn: string[]
  owner?: string
  workerProfileId?: string
  filesScope: string[]
  acceptanceCriteria: string[]
  verification: string[]
  decisionRequestIds: string[]
  updatedAt: string
}
```

### DecisionRequest

```ts
type DecisionRequest = {
  id: string
  beadId: string
  agent: string
  severity: "blocking" | "important" | "optional"
  decisionType: "product" | "architecture" | "implementation" | "safety" | "dependency" | "release"
  question: string
  context: string
  options: Array<{ id: string; label: string; consequences: string }>
  recommendedOptionId?: string
  defaultAfterTimeout?: string
  expiresAt?: string
  status: "open" | "answered" | "deferred" | "expired" | "cancelled"
}
```

### WorkflowImprovement

```ts
type WorkflowImprovement = {
  id: string
  sourceConversationId: string
  target: "AGENTS.md" | "skill" | "worker_profile" | "template" | "quality_gate" | "dashboard"
  problem: string
  proposedChange: string
  expectedBenefit: string
  risk: string
  status: "proposed" | "approved" | "applied" | "rejected" | "deferred"
}
```

## 10. Implementation Phases

### Phase 0: Research Import

- Download upstream Agent Flywheel repos into a research folder.
- Inventory useful prompt, AGENTS, and coordination patterns.
- Keep upstream material separate from product code.

### Phase 1: Internal Protocol

- Rename or reframe current `study-agent-devkit` as internal flywheel material.
- Maintain the dynamic worker profile template and add a small registry of seed profiles once real repeated worker shapes emerge.
- Maintain the decision-request template and policy for asynchronous blockers.
- Install and use the existing `workflow-optimizer` skill.
- Add session-end checklist.

### Phase 2: Adopt Core Tools

- Install and test `br`, `bv`, and Agent Mail locally.
- Create a sandbox project with sample beads.
- Verify Codex can read ready beads, claim work, and use mail threads.
- Verify the orchestrator can select/reuse/create worker profiles from bead scope.
- Treat Agent Mail `/mail` web UI as optional discovery, not a blocker.

### Phase 3: Worker Launch and Routing

- Add launch prompts generated from worker profiles.
- Add a ready-queue protocol.
- Add file reservation discipline.
- Add branch/worktree naming conventions.
- Add review handoff protocol.

### Phase 4: Workflow Optimizer Loop

- Run it at session end.
- Store proposals as workflow-improvement artifacts.
- Review/apply approved improvements.

### Phase 5: Optional Dashboard / Remote Oversight

- Start with Agent Mail web UI if usable.
- Add a thin dashboard only if Mail/CLI surfaces are not enough:
  - Today view;
  - Questions view;
  - Beads view;
  - Review queue.
- Expose privately through a secure tunnel only after auth and approval boundaries are clear.

### Phase 6: Scale Out and Later Reuse

- Consider NTM/tmux orchestration.
- Consider CASS/CM for session search and procedural memory.
- Consider UBS and related Agent Flywheel tools after `br`, `bv`, and Agent Mail prove useful.
- Consider hosted dashboard only after local/VPS workflow is stable.

## 11. Immediate Next Beads

1. `fw-001`: Import upstream Agent Flywheel repos into `upstream-research/` and inventory reusable artifacts.
2. `fw-002`: Install and test `br`, `bv`, and Agent Mail on a sandbox repo.
3. `fw-003`: Exercise the decision-request template on a sample blocker and refine policy.
4. `fw-004`: Add 2-3 seed reusable profiles only after observing real repeated worker needs.
5. `fw-005`: Build a small orchestrator exercise that turns sample beads into profile reuse/create decisions.
6. `fw-006`: Run `workflow-optimizer` on this scaffold after the first real core-tool test.
7. `fw-007`: Evaluate Agent Mail `/mail` web UI as optional local oversight, not a required mobile MVP.
8. `fw-008`: Create a later-dashboard requirements note only after the core loop is proven.

## 12. Recommended Decision

Adopt Agent Flywheel's core tools rather than reimplementing them immediately:

- use `br` for task state;
- use `bv` for triage;
- use Agent Mail for coordination, claims, threads, and inboxes;
- build our custom layer around structured decision requests, dynamic worker profiles, study-agent-specific quality gates, and workflow optimization.

Do not adopt the full VPS/swarm stack or custom remote dashboard until the core loop is proven. The first milestone is not "many agents" or "mobile control"; it is "one agent can stop asking in chat, create a durable decision request, receive an answer through Mail/CLI/local oversight, and let other ready beads continue."
