# Study Agent Devkit

A Codex-oriented internal flywheel for repeatedly turning study-agent ideas into reviewed, merge-ready work.

This directory is not the study-agent product, and it is not the public OSS devkit that may eventually ship. It is the private factory used to build those things: skills, templates, review gates, reusable worker profiles, and workflow rules that turn rough feature ideas into precise specs, scoped work, reviewed code, and durable project memory.

## Why This Exists

The target product is a reusable study-agent platform with:

- source-grounded RAG over study material;
- course-aware prompt profiles;
- flashcard and quiz generation;
- integrated spaced repetition;
- simulation and question-bank workflows;
- review, audit, and repair loops for generated study objects.

That product should be built in a new codebase with public-project quality standards. This internal flywheel helps keep Codex fast without letting the codebase drift into one-off scripts, vague prompts, or unreviewed agent output.

## Operating Model

The workflow adapts the strongest ideas from Agent Flywheel:

```text
raw idea
-> product/technical spec
-> task graph
-> reusable worker profiles
-> worker briefs
-> implementation
-> review gates
-> merge-ready change
```

The key rule is to keep decisions in the right place:

- **Plan space**: product behavior, architecture, constraints, risks, verification.
- **Task space**: granular tasks with dependencies and acceptance criteria.
- **Worker-profile space**: reusable role profiles generated from actual task needs.
- **Code space**: local implementation by workers with narrow scope.

## Included Skills

- `feature-spec-architect`: turns a rough feature idea into an implementable spec.
- `implementation-orchestrator`: converts a spec into task beads and invokes worker-profile generation when specialization is useful.
- `worker-profile-factory`: generates reusable worker profiles from the current graph, constraints, and implementation patterns instead of relying on a fixed role taxonomy.
- `code-quality-governor`: retained legacy skill; do not invoke it in this repository. Semantic code review is automatic on GitHub.
- `simplify-and-refactor-code-isomorphically`: guides expert behavior-preserving simplification and refactoring.
- `workflow-optimizer`: reviews sessions and proposes reusable improvements to skills, worker profiles, templates, prompts, AGENTS rules, and quality gates.
- `study-prompt-system-designer`: designs course-aware prompts and eval fixtures.
- `study-rag-architect`: designs RAG integrations without overcoupling the domain to one framework.
- `generate-morphology-first-anatomy-cards`: generates source-grounded anatomy cards that combine morphology-first reconstruction with selective atomic discrimination, explicit provenance, and deterministic JSON validation.

## Directory Layout

```text
study-agent-devkit/
├── AGENTS.md
├── README.md
├── docs/
├── examples/
├── skills/
└── templates/
```

## First Workflow

1. Describe a feature in plain language.
2. Invoke `feature-spec-architect`.
3. Review the generated spec and answer any open questions.
4. Invoke `implementation-orchestrator`.
5. Let the orchestrator call `worker-profile-factory` for reusable worker profiles when the work needs specialization.
6. Assign or spawn workers from the generated task beads and profiles.
7. Invoke `simplify-and-refactor-code-isomorphically` for behavior-preserving cleanup before or during implementation when complexity blocks safe change.
8. Publish a scoped draft, capture its GitHub Actions CI and use automatic Codex GitHub review. Fix actionable findings in the same PR; merge only when authorized.
9. Run `workflow-optimizer` at the end of meaningful sessions or repeated friction.

## Tool Adoption Path

Start lightweight:

- Markdown specs in `docs/specs/`
- Task beads in `docs/tasks/`
- Worker briefs in `docs/worker-briefs/`
- ADRs in `docs/adr/`

Adopt heavier tooling only when it earns its keep:

- Reuse `br` directly for local-first beads once dependency graphs become large enough that markdown task files are awkward.
- Reuse `bv` directly for graph-aware ready-task routing once manual task selection becomes inefficient.
- Reuse Agent Mail directly when multiple agents regularly work concurrently in the same repository; use bead IDs as thread IDs and file reservations as advisory locks.
- Use UBS as an extra scanner after normal lint, typecheck, tests, and review.
- Use tmux/VPS orchestration only after the workflow already works with a small number of agents.

## Optional Oversight Layer

A dashboard or mobile oversight surface can be added later for monitoring active beads, answering blockers, and reviewing agent status from away from the workstation. It is not a current first-class requirement for the factory. The core workflow should remain usable from Codex, markdown artifacts, `br`/`bv`, and Agent Mail before any UI layer is treated as necessary.

## Operational Commands

Repository tests and smoke suites are CI-only. Do not execute
`pytest`, Ruff, mypy, package builds, validators, `check-flywheel.sh`, or
`run-runner-smoke.sh` locally. Push the branch and use the GitHub Actions result
for the exact commit.

The commands below are operational interfaces, not local completion gates:

```bash
scripts/flywheel-runner.py commands
scripts/flywheel-runner.py doctor --project ../study-agent-platform
scripts/flywheel-runner.py plan --project ../study-agent-platform --feature "Describe the next feature"
scripts/flywheel-runner.py intake --project ../study-agent-platform --feature "Describe the next feature"
scripts/flywheel-runner.py validate --project ../study-agent-platform --run-id latest
scripts/flywheel-runner.py profiles --project ../study-agent-platform --run-id latest
scripts/flywheel-runner.py decision-request --project ../study-agent-platform --run-id latest --help
scripts/flywheel-runner.py dispatch --project ../study-agent-platform --run-id latest --ready-only
scripts/flywheel-runner.py optimize --project ../study-agent-platform --run-id latest
scripts/flywheel.py status --json
scripts/flywheel-core.py commands
scripts/flywheel-core.py versions
scripts/flywheel-core.py reservations --project sandbox/core-tools-smoke --all
scripts/install-skills.sh --dry-run
scripts/run-sandbox-flow.py --clean
scripts/run-core-tools-smoke.sh --clean
scripts/install-core-tools.sh
```

`scripts/run-core-tools-smoke.sh` diagnoses optional, separately installed
Agent Flywheel tools. It is not part of repository verification until those
external binaries are pinned in CI.

See `docs/flywheel-runner.md` for the orchestrator-facing CLI contract and `docs/operations.md` for the full local workflow.

## References

- Agent Flywheel: https://agent-flywheel.com/
- Core Flywheel: https://agent-flywheel.com/core-flywheel
- beads_rust: https://github.com/Dicklesworthstone/beads_rust
- beads_viewer: https://github.com/Dicklesworthstone/beads_viewer
- Agent Mail: https://github.com/Dicklesworthstone/mcp_agent_mail_rust
