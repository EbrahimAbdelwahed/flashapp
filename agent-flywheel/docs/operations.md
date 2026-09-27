# Operations

This directory is the internal agent flywheel. The first operational milestone is a local, file-based flow that works before upstream tools are installed, then direct reuse of `br`, `bv`, and Agent Mail when they are available.

## Health Check

The repository health check runs only in GitHub Actions:

```bash
scripts/check-flywheel.sh
```

Do not execute it locally. The workflow runs it on Python 3.13 after installing
the package and development tools. It verifies:

- required docs, templates, and skills exist;
- skill frontmatter is valid;
- stale fixed-worker taxonomy language is absent;
- mobile/dashboard oversight is not accidentally treated as phase-one;
- core tool availability is reported.

Pytest, Ruff, mypy, package builds, clean-wheel imports, validators, and runner
smoke tests are also CI-only. A change is verified only when the GitHub Actions
run for its exact commit is green.

The live core-tools smoke is different: it diagnoses optional local
installations of `br`, `bv`, and Agent Mail. It remains a manual environment
diagnostic, not repository test evidence, until those binaries are version
pinned and installed by CI.

## Install Codex Skills

Dry-run:

```bash
scripts/install-skills.sh --dry-run
```

Install with symlinks:

```bash
scripts/install-skills.sh
```

Use copies instead:

```bash
scripts/install-skills.sh --copy
```

Restart Codex after installing skills so metadata is loaded.

## Sandbox Flow

Generate and verify the file-based sandbox:

```bash
scripts/run-sandbox-flow.py --clean
```

The sandbox proves the artifact ladder:

```text
spec
-> task bead
-> worker profile
-> worker brief
-> decision request
-> review report
-> workflow improvement
-> session-end checklist
```

It does not prove live `br`/`bv`/Agent Mail integration. That is the next milestone after installing core tools.

## Local Control CLI

Inspect generated artifacts:

```bash
scripts/flywheel.py status --json
scripts/flywheel.py tasks --json
scripts/flywheel.py ready --json
scripts/flywheel.py decisions --json
scripts/flywheel.py profiles --json
scripts/flywheel.py doctor --json
```

Use `--project <path>` to inspect another file-based flywheel project. The CLI is read-only and exists so the orchestrator has a stable local control surface before `br`, `bv`, and Agent Mail are installed.

## Orchestrator Runner

Use `scripts/flywheel-runner.py` as the canonical workflow surface for a complete implementation lane:

```bash
scripts/flywheel-runner.py plan --project ../study-agent-platform --feature "Describe the next feature"
scripts/flywheel-runner.py intake --project ../study-agent-platform --feature "Describe the next feature"
scripts/flywheel-runner.py context --project ../study-agent-platform --run-id latest --query "relevant term"
scripts/flywheel-runner.py spec --project ../study-agent-platform --run-id latest
scripts/flywheel-runner.py validate --project ../study-agent-platform --run-id latest
scripts/flywheel-runner.py beads --project ../study-agent-platform --run-id latest --beads-json tasks.json --create-br-beads
scripts/flywheel-runner.py profiles --project ../study-agent-platform --run-id latest
scripts/flywheel-runner.py briefs --project ../study-agent-platform --run-id latest
scripts/flywheel-runner.py validate --project ../study-agent-platform --run-id latest --stage dispatch
scripts/flywheel-runner.py dispatch --project ../study-agent-platform --run-id latest --ready-only
scripts/flywheel-runner.py worker-report --project ../study-agent-platform --run-id latest --task "<task-id>" --file-changed "<path>: <summary>" --behavior "<summary>" --verification "pnpm -w typecheck: passed"
scripts/flywheel-runner.py review --project ../study-agent-platform --run-id latest --command "pnpm -w typecheck"
scripts/flywheel-runner.py optimize --project ../study-agent-platform --run-id latest
scripts/flywheel-runner.py git-lane --project ../study-agent-platform --run-id latest
scripts/flywheel-runner.py pr-lane --project ../study-agent-platform --run-id latest --draft
scripts/flywheel-runner.py status --project ../study-agent-platform --run-id latest
```

The runner is built for an agent orchestrator:

- it creates a run manifest under `docs/flywheel-runs/<run-id>/`;
- it keeps markdown artifacts as durable fallback state;
- it materializes `br` beads only when `--create-br-beads` is explicit;
- it generates reusable worker profiles from task bead directives;
- it validates context/spec/task/profile/brief/decision/review readiness before dispatch;
- it blocks dispatch on Draft specs and missing context packs;
- it turns material blockers into structured decision requests;
- it emits `multi_agent_v1.spawn_agent` packets for the Codex orchestrator;
- it requires complete worker reports for every task bead before publication;
- it uses `br ready` automatically during sequenced `run` dispatch when linked beads exist;
- it allows draft publication before CI, requires passing technical verification for readiness, and uses only automatic Codex GitHub review for semantic findings;
- it prepares review and git lanes but does not silently push;
- it prepares PR creation but does not call GitHub unless `--execute` is explicit;
- it blocks git/PR execution on failed final gates unless `--override-gates` is explicit;
- it generates workflow optimization proposals at the end of the run;
- it expects the orchestrator to fill specs and task JSON using the relevant skills.

See `docs/flywheel-runner.md` for phase semantics, failure rules, and examples.

## Core Tool Install Plan

Print install commands:

```bash
scripts/install-core-tools.sh
```

Execute install commands only after review:

```bash
scripts/install-core-tools.sh --execute
```

This requires network access and writes outside the repository. After installation, run the health check and sandbox flow again.

See `docs/core-tools-install-approval.md` for the exact approval text and risk summary before executing upstream installers.

## Core Tool Smoke Test

Run a non-failing smoke test that skips when tools are missing:

```bash
scripts/run-core-tools-smoke.sh --clean
```

Require all tools and fail if any are missing:

```bash
scripts/run-core-tools-smoke.sh --clean --require-tools
```

## Structured Core Tool Wrapper

Use `scripts/flywheel-core.py` instead of calling `br`, `bv`, and `am` ad hoc:

```bash
scripts/flywheel-core.py versions
scripts/flywheel-core.py init --project sandbox/core-tools-smoke
scripts/flywheel-core.py create-bead --project sandbox/core-tools-smoke --title "Implement feature" --type task --priority 2
scripts/flywheel-core.py update-bead --project sandbox/core-tools-smoke --id "<bead-id>" --claim
scripts/flywheel-core.py add-dependency --project sandbox/core-tools-smoke --issue "<dependent-bead-id>" --depends-on "<blocking-bead-id>"
scripts/flywheel-core.py close-bead --project sandbox/core-tools-smoke --id "<bead-id>" --reason "Verified"
scripts/flywheel-core.py ready --project sandbox/core-tools-smoke
scripts/flywheel-core.py triage --project sandbox/core-tools-smoke
scripts/flywheel-core.py agent-mail-preflight --project sandbox/core-tools-smoke
scripts/flywheel-core.py start-session --project sandbox/core-tools-smoke --agent-name BlueLake --task "Plan next bead" --reserve 'docs/**' --reserve-reason planning
scripts/flywheel-core.py release-reservations --project sandbox/core-tools-smoke --agent BlueLake --paths 'docs/**'
scripts/flywheel-core.py status --project sandbox/core-tools-smoke --agent BlueLake
scripts/flywheel-core.py reservations --project sandbox/core-tools-smoke --all
scripts/flywheel-core.py send --project sandbox/core-tools-smoke --from BlueLake --to BlueLake --thread-id "<bead-id>" --subject "[<bead-id>] Status" --body "Progress note."
```

The wrapper is intentionally thin: it keeps our workflow stable while still reusing upstream tool semantics directly.

Relative `--project` paths resolve from the caller's current directory. From inside a target repository, use `--project .`; from `study-agent-devkit/`, use paths such as `--project ../study-agent-platform`.

Agent Mail mutating commands write to `~/.local/share/mcp-agent-mail`, which is outside this repository. In Codex sandboxed runs, execute Agent Mail session, reservation, and mail commands with the required unsandboxed approval; otherwise false `Operation not permitted` failures can appear even when the mailbox is healthy.

Run Agent Mail commands serially. Do not launch multiple `am doctor`, `am robot`, reservation, or mail commands in parallel against the same storage root; concurrent probes can leave busy locks or transient SQLite WAL sidecars that obscure the real health signal.

Use isolated Agent Mail storage for repeatable flywheel tests or product bootstrap runs:

```bash
scripts/flywheel-core.py start-session \
  --project ../study-agent-platform \
  --task "Bootstrap next bead" \
  --reserve 'packages/prompts/**' \
  --reserve-reason bootstrap \
  --reserve-ttl 120 \
  --mailbox-storage-root sandbox/agent-mail-local

scripts/flywheel-core.py agent-mail-preflight \
  --project ../study-agent-platform \
  --mailbox-storage-root sandbox/agent-mail-local
```

`--mailbox-storage-root` sets `STORAGE_ROOT`, creates the directory, initializes it as a git repo, and sets `DATABASE_URL` to `sqlite:///<storage-root>/storage.sqlite3` unless `--mailbox-database-url` is supplied. Keep these runtime roots under ignored `sandbox/agent-mail-*` paths.

Quote reservation globs such as `'docs/**'` so the shell does not expand them before the wrapper passes them to Agent Mail.

Prefer `start-session --reserve ...` for normal worker startup. Omit `--agent-name` unless you already have a valid Agent Mail generated adjective+noun identity; Agent Mail rejects descriptive names. The standalone `reserve` command is available for follow-up locks; for exclusive reservations, the wrapper falls back to `start-session` if Agent Mail reports a busy mailbox activity lock. Reservation TTL must be at least 60 seconds.

Release worker reservations at the end of a verification or abandoned worker run with `release-reservations`; otherwise stale or test-only locks can pollute later triage.

`agent-mail-preflight` returns non-zero unless the basic Agent Mail commands succeed, `am doctor check --json` reports `healthy: true`, `am doctor health` exits cleanly, detect-only P1 archive/reservation drift checks have no findings, and `am robot status` reports `health: ok`. Treat its fields as:

- `functional=true`: commands can read/write enough for status, sessions, reservations, and messages.
- `usable=true`: the basic command path works and `am doctor check --json` is healthy.
- `ready=true`: the mailbox is clean enough for unattended coordination.

Do not treat `functional=true` or `usable=true` as equivalent to `ready=true`.

With Agent Mail `0.3.13`, strict `ready=true` may remain unavailable even on isolated storage because message and reservation DB rows can be created without matching stable archive artifacts. The wrapper intentionally reports this as detect-only P1 drift instead of hiding it. Until upstream provides a DB-to-archive repair path, treat Agent Mail as a useful coordination channel only when `usable=true`; keep `br`, `bv`, task beads, worker briefs, decision requests, logs, and handoffs as the durable source of truth.

## First Live Integration Target

After `br`, `bv`, and Agent Mail are available:

1. Run `br init` in a sandbox repo.
2. Create beads corresponding to the sandbox tasks.
3. Run `br ready --json`.
4. Run `bv --robot-triage` if available.
5. Start Agent Mail locally.
6. Register a project and at least two agent identities.
7. Create a thread using the bead ID.
8. Reserve the sandbox file scope.
9. Send a completion and review message.

Only after this works should a custom dashboard or remote oversight layer be considered.
