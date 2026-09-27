# Flywheel Runner

`scripts/flywheel-runner.py` is the orchestrator-facing CLI for moving one feature through the internal flywheel. Run `grill-with-docs` before approving the spec and again before dispatching each ready bead; persist its decision, ADR, and glossary evidence in the corresponding artifacts.

```text
intake -> context -> spec -> validate -> beads -> worker profiles -> worker briefs -> validate -> dispatch -> worker reports -> review -> optimize -> git lane -> PR lane
```

The runner is deliberately deterministic. It writes artifacts, links them in a manifest, and calls `flywheel-core.py` only when asked to materialize `br` beads. It does not call an LLM or silently spawn workers. The primary user is a Codex orchestrator agent that can read the generated files, fill missing product details, launch workers through `multi_agent_v1.spawn_agent`, and verify the result.

This is still inspired by Agent Flywheel's operating model: keep a task graph, select ready work, dispatch narrow workers, coordinate file ownership, review before merge, and improve the workflow after each cycle. The adaptation is that Codex subagent spawning is a conversation tool, not a local shell API, so the runner produces durable dispatch packets that the orchestrator uses to call real workers.

Run phases that write the same `run_id` sequentially, or use the `run` command. Parallelism belongs after `dispatch`, where independent workers own distinct file scopes.

## Core Contract

- Every feature run has a `run_id`.
- The run manifest lives at `docs/flywheel-runs/<run-id>/manifest.json` in the target project.
- Markdown remains the durable fallback source of truth.
- Dispatch requires a context pack and a non-Draft spec.
- `br`/`bv` become the active task graph after `beads --create-br-beads`.
- Worker profiles are generated as reusable markdown contracts before worker briefs when a bead says `create <profile>`.
- Material blockers become decision-request artifacts, not chat-only questions.
- Agent Mail may coordinate live workers, but it is not required for the runner and is not treated as strict-ready storage.
- Git actions are inspect-only unless `git-lane --execute` is passed with explicit branch/stage/commit/push flags.
- PR creation is inspect-only unless `pr-lane --execute` is passed with explicit GitHub auth/network intent.
- Git publication and draft creation require scope/decision gates. Marking a PR ready additionally requires final technical verification; semantic review is automatic on GitHub.
- Worker dispatch is prepared as JSON packets; the orchestrator calls `multi_agent_v1.spawn_agent` with each packet.
- PR readiness requires complete worker reports and passing technical verification. Publish a draft first; do not invoke a local semantic reviewer. Before any authorized merge, inspect current CI and automatic Codex review on GitHub.

## Recommended Orchestrator Flow

Start with read-only discovery when an agent is unfamiliar with the CLI:

```bash
study-agent-devkit/scripts/flywheel-runner.py commands
study-agent-devkit/scripts/flywheel-runner.py doctor --project study-agent-platform
study-agent-devkit/scripts/flywheel-core.py commands
```

Start by asking the runner for the command sequence:

```bash
study-agent-devkit/scripts/flywheel-runner.py plan \
  --project study-agent-platform \
  --feature "Add source-grounded answer generation for uploaded study material"
```

Create the run:

```bash
study-agent-devkit/scripts/flywheel-runner.py intake \
  --project study-agent-platform \
  --feature "Add source-grounded answer generation for uploaded study material"
```

Collect context:

```bash
study-agent-devkit/scripts/flywheel-runner.py context \
  --project study-agent-platform \
  --run-id latest \
  --query "retrieval" \
  --query "Source"
```

Create a spec scaffold:

```bash
study-agent-devkit/scripts/flywheel-runner.py spec \
  --project study-agent-platform \
  --run-id latest
```

The orchestrator must then fill the spec. If details are missing, use `feature-spec-architect` before implementation planning.

Validate before creating live task state:

```bash
study-agent-devkit/scripts/flywheel-runner.py validate \
  --project study-agent-platform \
  --run-id latest \
  --stage spec
```

Materialize beads after scope is clear. Prefer JSON when an agent is generating tasks:

```json
{
  "tasks": [
    {
      "id": "retrieval-port-contract",
      "title": "Define source-grounded retrieval port contract",
      "priority": "P1",
      "type": "task",
      "depends_on": [],
      "outcome": "A caller can retrieve source-grounded spans through the portable contract.",
      "slice_strategy": "tracer-bullet",
      "fresh_context_fit": "yes",
      "spec_coverage": ["Retrieval results expose source spans and citations."],
      "grilling_evidence": ["docs/decisions/retrieval-contract.md", "Decision state: approved"],
      "worker_profile": "create `retrieval-contract-worker`",
      "context": "The answer generator needs a portable retrieval boundary before adapters are added.",
      "what_to_do": [
        "Define retrieval request/result types.",
        "Document citation and unsupported-answer semantics."
      ],
      "files": [
        "`packages/retrieval/src/index.ts`: retrieval contract"
      ],
      "acceptance_criteria": [
        "Core types expose source spans and citation metadata.",
        "No framework-specific objects leak into the domain contract."
      ],
      "verification": [
        "pnpm -w typecheck"
      ],
      "out_of_scope": [
        "Implementing a concrete vector database adapter."
      ]
    }
  ]
}
```

Then run:

```bash
study-agent-devkit/scripts/flywheel-runner.py beads \
  --project study-agent-platform \
  --run-id latest \
  --beads-json tasks.json \
  --create-br-beads
```

Generate reusable worker profiles for beads that request them:

```bash
study-agent-devkit/scripts/flywheel-runner.py profiles \
  --project study-agent-platform \
  --run-id latest
```

Generate worker briefs:

```bash
study-agent-devkit/scripts/flywheel-runner.py briefs \
  --project study-agent-platform \
  --run-id latest
```

Validate and prepare worker dispatch:

```bash
study-agent-devkit/scripts/flywheel-runner.py validate \
  --project study-agent-platform \
  --run-id latest \
  --stage dispatch

study-agent-devkit/scripts/flywheel-runner.py dispatch \
  --project study-agent-platform \
  --run-id latest \
  --ready-only
```

Then the orchestrator reads `docs/flywheel-runs/<run-id>/dispatch/worker-dispatch.json` and calls `multi_agent_v1.spawn_agent` once per selected packet:

```json
{
  "agent_type": "worker",
  "fork_context": false,
  "message": "<packet prompt>"
}
```

If a worker or orchestrator needs a material decision before continuing, write a structured request:

```bash
study-agent-devkit/scripts/flywheel-runner.py decision-request \
  --project study-agent-platform \
  --run-id latest \
  --task retrieval-port-contract \
  --id retrieval-port-framework-boundary \
  --severity blocking \
  --decision-type architecture \
  --question "Should the retrieval port expose framework-neutral source spans?" \
  --context "The first adapter can use LlamaIndex, but the core domain should remain replaceable." \
  --option "neutral|Framework-neutral contract|More mapping code now, less coupling later" \
  --option "llamaindex|Expose LlamaIndex objects|Faster first adapter, harder provider replacement" \
  --recommendation neutral \
  --reason "The platform should stay reusable and open-source friendly." \
  --default-if-unanswered "do not proceed"
```

Resolve it after the user or orchestrator decides:

```bash
study-agent-devkit/scripts/flywheel-runner.py decision-request \
  --project study-agent-platform \
  --run-id latest \
  --id retrieval-port-framework-boundary \
  --resolve "neutral" \
  --answered-by orchestrator
```

When a worker finishes, ingest its report:

```bash
study-agent-devkit/scripts/flywheel-runner.py worker-report \
  --project study-agent-platform \
  --run-id latest \
  --task retrieval-port-contract \
  --agent retrieval-contract-worker \
  --file-changed "packages/retrieval/src/index.ts: retrieval contract types" \
  --behavior "Defined framework-neutral retrieval request/result contracts" \
  --verification "pnpm -w typecheck: passed"
```

After publishing a draft so GitHub Actions can run, capture technical verification:

```bash
study-agent-devkit/scripts/flywheel-runner.py review \
  --project study-agent-platform \
  --run-id latest \
  --github-actions-run 123456789 \
  --finding "Technical verification captured; semantic review is automatic on GitHub."
```

Prepare the git lane:

```bash
study-agent-devkit/scripts/flywheel-runner.py git-lane \
  --project study-agent-platform \
  --run-id latest
```

Prepare the workflow optimization and PR lane:

```bash
study-agent-devkit/scripts/flywheel-runner.py optimize \
  --project study-agent-platform \
  --run-id latest

study-agent-devkit/scripts/flywheel-runner.py pr-lane \
  --project study-agent-platform \
  --run-id latest \
  --draft
```

Execute git steps only when the orchestrator has explicit branch/stage/commit/push intent:

```bash
study-agent-devkit/scripts/flywheel-runner.py git-lane \
  --project study-agent-platform \
  --run-id latest \
  --create-branch \
  --branch codex/source-grounded-answers \
  --stage packages/retrieval \
  --stage docs/specs/source-grounded-answers.md \
  --commit-message "Add source-grounded answer contract" \
  --execute
```

Use `--push --execute` only when the user or current workflow explicitly asks for remote publication.

Create the PR only after push/auth intent is explicit:

```bash
study-agent-devkit/scripts/flywheel-runner.py pr-lane \
  --project study-agent-platform \
  --run-id latest \
  --draft \
  --execute
```

## Phase Semantics

### `commands`

Prints a machine-readable command manifest with summaries, side-effect classes, output conventions, dry-run support, and dangerous flags. Use this before generating or executing runner commands from an agent.

### `doctor`

Runs read-only checks for the runner environment and optional project state. It reports Python, runner/core script presence, `rg`, `git`, project existence, `.git` presence, flywheel run directory presence, and latest run id as JSON.

### `intake`

Creates the run manifest and `intake.md` from a raw feature description. This is the only phase that can start without an existing run.

Required input:

- `--feature` or `--feature-file`

Output:

- `docs/flywheel-runs/<run-id>/intake.md`
- `docs/flywheel-runs/<run-id>/manifest.json`

### `context`

Reads standard project orientation files and optional `rg` queries into `context-pack.md`.

Use this before generating a spec. Add `--file` for important docs the default collector did not find.

### `spec`

Creates a feature spec scaffold in `docs/specs/`. The orchestrator must fill it before beads are final. Do not launch implementation from placeholder sections.

### `beads`

Writes task bead markdown files under `docs/tasks/<run-id>/`.

Use `--beads-json` for precise task graphs. Without JSON, the runner can parse simple entries under `## Task Beads` in the spec:

```text
- `task-id`: Task title
```

Use `--create-br-beads` only after the task graph is approved enough to become live coordination state.

### `profiles`

Generates reusable worker profile markdown files under `docs/worker-profiles/` for every task bead whose `Worker Profile` section says `create <profile-id>`.

Profiles are deterministic contracts for recurring worker shapes. They include:

- reuse trigger;
- mandate;
- in-scope and out-of-scope boundaries;
- required context;
- allowed edit and inspect paths;
- forbidden decisions;
- quality gates;
- verification;
- report format.

Use overrides such as `--research-note`, `--allowed-edit`, `--forbidden-decision`, and `--quality-gate` when the orchestrator has stronger context than the task bead.

### `validate`

Checks the current run for missing context or grilling evidence, missing or placeholder spec sections, Draft specs, duplicate tasks, dependency cycles, weak slice contracts, missing worker profiles, broad task scopes, missing worker briefs, open decision requests, worker report coverage, and failed or missing review evidence.

Use stages:

- `--stage spec`: validate only the feature spec before beads exist.
- `--stage dispatch`: validate context, non-Draft spec, task beads, worker profiles, worker briefs, and open blocking decisions without blocking on failed review commands.
- `--stage final`: validate publication readiness after worker execution, including dispatch packets, complete worker reports, and passing technical command results. This does not authorize a merge or replace automatic GitHub review.
- `--stage auto`: validate the spec before task beads, dispatch readiness before worker execution artifacts exist, and final publication readiness once dispatch, worker reports, and review are present.

The command writes:

- `docs/flywheel-runs/<run-id>/validation.md`
- `docs/flywheel-runs/<run-id>/validation.json`

Exit code is non-zero if errors are found. Use `--fail-on-warnings` to make warnings blocking too.

### `briefs`

Creates one worker brief per task bead under `docs/worker-briefs/<run-id>/`. Worker briefs inherit scope from the task bead and add consistent report-back rules.

If a task references a worker profile, the brief includes it in `Read First`.

### `decision-request`

Creates or resolves a structured decision request under `docs/decision-requests/<run-id>/`.

Use this when a worker discovers a product, architecture, safety, dependency, release, or implementation decision that should not be guessed. Open blocking requests fail validation and dispatch; important requests produce warnings.

### `dispatch`

Creates worker spawn packets under:

- `docs/flywheel-runs/<run-id>/dispatch/worker-dispatch.json`
- `docs/flywheel-runs/<run-id>/dispatch/worker-dispatch.md`

Each packet contains:

- task id and linked `br` id when available;
- task and brief paths;
- file hints for collision avoidance;
- a `spawn_agent` object for `multi_agent_v1.spawn_agent`;
- coordination command hints;
- required report fields.

Use `--ready-only` to dispatch only tasks that have a linked `br` id and are returned by `br ready`. Tasks without linked `br` ids are skipped in this mode. The sequenced `run` command automatically uses ready-only dispatch when the manifest has linked `br` beads.

`dispatch` validates spec/task/brief readiness before preparing packets, but it does not block on failed review command results. That is intentional: after a review failure, the orchestrator should be able to redispatch a worker for rework. Failed technical commands block PR readiness. Git publication and draft submission remain possible so GitHub Actions can verify the change.

### `worker-report`

Records a worker completion report under `docs/worker-reports/<run-id>/<task-id>.md` and links it in the manifest.

Use this after reading each worker's final response. Publication gates require one complete report for every task bead in the run. A report may be marked `blocked` or `partial`, but those statuses keep final validation red until the orchestrator resolves the blocker or redispatches work.

### `review`

Creates `docs/reviews/<run-id>.md` and captures verification command outputs in `review-command-results.json`.

This command captures technical verification, not semantic approval. Use `--github-actions-run <id>` to ingest the complete `CI` workflow from this repository for exact `HEAD`. Final validation and PR readiness recheck the live run; arbitrary local commands and older green commits cannot satisfy those gates. A report without commands exits non-zero unless `--allow-empty` is explicitly passed; an empty scaffold cannot satisfy final technical gates. Semantic review comes only from automatic Codex GitHub review. Run prescribed tests in GitHub Actions and capture their evidence rather than rerunning them locally.

### `optimize`

Generates workflow improvement proposals from the run manifest, validation findings, worker profile coverage, decision requests, dispatch state, worker reports, and review evidence.

This implements the end-of-conversation optimizer habit without requiring the user to remember it manually.

### `git-lane`

Captures branch, status, staged diff summary, unstaged diff summary, and proposed git commands. It does not mutate git unless `--execute` is present. Execution requires scope and decision gates to be green unless `--override-gates` is explicit.

### `pr-lane`

Prepares a PR body and command. With `--execute`, it looks up the branch’s open PR, creates it when absent, reuses it when present, or runs `gh pr ready` for a verified draft. Draft submission requires scope/decision gates and a git lane; readiness additionally requires final technical verification. It never merges.

When `--execute` is used, the runner checks local lane artifact overwrite safety before calling `gh`, so a remote PR is not created and then followed by a local overwrite failure.

### `run`

Chains deterministic phases. It stops when an agent judgment artifact is missing, such as `--beads-json` for the task graph, and propagates child phase failures such as incomplete `status`. When linked `br` beads exist, the dispatch phase uses ready-only routing automatically.

### `status`

Prints manifest state, missing phases, live validation issues, worker profile coverage, decision state, worker reports, and review evidence as JSON. Exit code is non-zero until all major artifacts exist and final gates are green.

## Failure Rules

- If the spec still contains placeholders, return to spec work.
- If the spec is still Draft or the context pack is missing, do not dispatch workers.
- If a task has broad or unclear file scope, refine the bead before launching a worker.
- If `br` materialization fails partway through, keep markdown artifacts as source of truth and inspect the manifest before retrying.
- If final validation reports missing worker reports, ingest reports with `worker-report` or redispatch unfinished work.
- If `review` exits non-zero with no commands, rerun it with real verification commands or use `--allow-empty` only for a non-merge-ready scaffold.
- If technical checks fail, keep the PR draft and fix the same branch. Before an authorized merge, require current CI and automatic Codex review evidence.
- If Agent Mail reports `usable=true` but `ready=false`, it can coordinate live work but must not be treated as the durable archive.

## Verification

Run these after modifying the runner:

```bash
python3 -m py_compile study-agent-devkit/scripts/flywheel-runner.py
study-agent-devkit/scripts/flywheel-runner.py --help
study-agent-devkit/scripts/flywheel-runner.py commands
study-agent-devkit/scripts/flywheel-runner.py doctor --project study-agent-platform
study-agent-devkit/scripts/flywheel-runner.py plan --project study-agent-platform --feature "Smoke test"
study-agent-devkit/scripts/check-flywheel.sh
```
