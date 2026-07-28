#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/flywheel-runner-smoke.XXXXXX")"
trap 'rm -rf "$TMPROOT"' EXIT
EXPECT_OUT="$TMPROOT/expect.out"
EXPECT_ERR="$TMPROOT/expect.err"

log() {
  printf '%s\n' "$*"
}

expect_failure() {
  local description="$1"
  shift
  if "$@" >"$EXPECT_OUT" 2>"$EXPECT_ERR"; then
    log "FAIL: expected failure: $description"
    cat "$EXPECT_OUT" || true
    cat "$EXPECT_ERR" || true
    exit 1
  fi
  log "PASS: $description"
}

RUNNER="$ROOT/scripts/flywheel-runner.py"

python3 -m py_compile "$RUNNER"
log "PASS: runner compiles"

python3 - "$RUNNER" <<'PY'
import importlib.util
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("flywheel_runner", path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
cycle = module.dependency_cycle({"a": ["b"], "b": ["c"], "c": ["a"]})
if cycle != ["a", "b", "c", "a"]:
    raise SystemExit(f"dependency cycle not detected: {cycle!r}")
if module.dependency_cycle({"a": [], "b": ["a"]}):
    raise SystemExit("acyclic graph reported as cyclic")
PY
log "PASS: dependency graph polishing detects cycles"

"$RUNNER" plan --project "$TMPROOT/plan-project" --feature "Plan placeholder smoke" >"$TMPROOT/plan.json"
if rg -n -- "--query <|--beads-json <|--task <" "$TMPROOT/plan.json" >/dev/null; then
  log "FAIL: runner plan emitted unquoted shell placeholder"
  exit 1
fi
log "PASS: runner plan quotes shell placeholders"

INCOMPLETE="$TMPROOT/incomplete"
"$RUNNER" intake --project "$INCOMPLETE" --run-id incomplete --feature "Incomplete status smoke" >/dev/null
expect_failure "run propagates failing status" "$RUNNER" run --project "$INCOMPLETE" --run-id incomplete --phase status

READYONLY="$TMPROOT/readyonly"
mkdir -p "$READYONLY"
printf '%s\n' '# Ready-only smoke' >"$READYONLY/README.md"
"$RUNNER" intake --project "$READYONLY" --run-id readyonly --feature "Ready-only dispatch smoke" >/dev/null
"$RUNNER" context --project "$READYONLY" --run-id readyonly >/dev/null
"$RUNNER" spec --project "$READYONLY" --run-id readyonly >/dev/null
cat >"$READYONLY/docs/specs/ready-only-dispatch-smoke.md" <<'SPEC'
# Feature Spec: Ready-only dispatch smoke

Status: Approved
Owner: orchestrator
Date: 2026-06-24

## Grilling Evidence

- Session/artifact: synthetic smoke approval
- Decision state: approved
- ADR/glossary changes: none

## Goal

Verify ready-only dispatch requires linked ready br beads.

## Problem

Ready-only dispatch must not launch untracked tasks.

## In Scope

- Generate one markdown task without a br id.

## Out of Scope

- Creating live br beads.

## Acceptance Criteria

- [ ] Dispatch ready-only produces no worker packets.

## Verification

- Integration: dispatch command exits non-zero with zero packets.

## Open Questions

- none
SPEC

cat >"$READYONLY/tasks.json" <<'JSON'
{
  "tasks": [
    {
      "id": "untracked-task",
      "title": "Untracked task",
      "priority": "P2",
      "type": "task",
      "depends_on": [],
      "outcome": "Ready-only dispatch visibly rejects an untracked task.",
      "slice_strategy": "tracer-bullet",
      "fresh_context_fit": "yes",
      "spec_coverage": ["Dispatch ready-only produces no worker packets."],
      "grilling_evidence": ["synthetic smoke approval", "Decision state: approved"],
      "worker_profile": "create `smoke-worker`",
      "worker_profile_rationale": "Exercise dynamic worker profile generation.",
      "context": "Verify ready-only filtering.",
      "what_to_do": ["Inspect dispatch output."],
      "files": ["`docs/flywheel-runs/readyonly/dispatch/worker-dispatch.json`: dispatch packet output"],
      "acceptance_criteria": ["No packet is generated when br id is missing."],
      "verification": ["test -f docs/flywheel-runs/readyonly/manifest.json"],
      "out_of_scope": ["Creating live br beads."]
    }
  ]
}
JSON

"$RUNNER" beads --project "$READYONLY" --run-id readyonly --beads-json "$READYONLY/tasks.json" >/dev/null
expect_failure "profiles rejects unknown task ids" "$RUNNER" profiles --project "$READYONLY" --run-id readyonly --task typo-task
"$RUNNER" profiles --project "$READYONLY" --run-id readyonly >/dev/null
test -f "$READYONLY/docs/worker-profiles/smoke-worker.md"
log "PASS: profiles generated required worker profile"
"$RUNNER" briefs --project "$READYONLY" --run-id readyonly >/dev/null

if ! rg -n "docs/worker-profiles/smoke-worker.md" "$READYONLY/docs/worker-briefs/readyonly/untracked-task.md" >/dev/null; then
  log "FAIL: worker brief does not reference generated profile"
  exit 1
fi
log "PASS: worker brief references generated profile"

"$RUNNER" validate --project "$READYONLY" --run-id readyonly --stage dispatch >/dev/null
log "PASS: dispatch validation passed before decision request"

"$RUNNER" decision-request \
  --project "$READYONLY" \
  --run-id readyonly \
  --task untracked-task \
  --id smoke-blocker \
  --severity blocking \
  --decision-type implementation \
  --question "Should the smoke task proceed?" \
  --context "The smoke test needs a blocking decision to verify validation gates." \
  --option "yes|Proceed|Validation should pass after resolution" \
  --option "no|Stop|Validation should remain blocked" \
  --recommendation yes \
  --reason "The test is deterministic and reversible." \
  --default-if-unanswered "do not proceed" >/dev/null
expect_failure "open blocking decision fails dispatch validation" "$RUNNER" validate --project "$READYONLY" --run-id readyonly --stage dispatch
expect_failure "open blocking decision blocks dispatch" "$RUNNER" dispatch --project "$READYONLY" --run-id readyonly
"$RUNNER" decision-request --project "$READYONLY" --run-id readyonly --id smoke-blocker --resolve "yes" --answered-by smoke >/dev/null
"$RUNNER" validate --project "$READYONLY" --run-id readyonly --stage dispatch >/dev/null
log "PASS: resolved decision unblocks dispatch validation"

expect_failure "review without commands is not merge-ready" "$RUNNER" review --project "$READYONLY" --run-id readyonly
"$RUNNER" review --project "$READYONLY" --run-id readyonly --command "test -f docs/flywheel-runs/readyonly/manifest.json" --force >/dev/null
log "PASS: review requires command evidence"

expect_failure "ready-only dispatch skips tasks without br ids" "$RUNNER" dispatch --project "$READYONLY" --run-id readyonly --ready-only

python3 - "$READYONLY/docs/flywheel-runs/readyonly/dispatch/worker-dispatch.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text())
if payload.get("packets") != []:
    raise SystemExit(f"expected zero packets, got: {payload.get('packets')!r}")
PY
log "PASS: ready-only dispatch wrote zero packets"

NOCONTEXT="$TMPROOT/nocontext"
"$RUNNER" intake --project "$NOCONTEXT" --run-id nocontext --feature "No context dispatch smoke" >/dev/null
"$RUNNER" spec --project "$NOCONTEXT" --run-id nocontext >/dev/null
cat >"$NOCONTEXT/docs/specs/no-context-dispatch-smoke.md" <<'SPEC'
# Feature Spec: No context dispatch smoke

Status: Approved
Owner: orchestrator
Date: 2026-06-25

## Grilling Evidence

- Session/artifact: synthetic smoke approval
- Decision state: approved
- ADR/glossary changes: none

## Goal

Verify dispatch requires context.

## Problem

Worker prompts should not contain context placeholders.

## In Scope

- Generate one task after skipping context.

## Out of Scope

- Product code changes.

## Acceptance Criteria

- [ ] Dispatch is blocked.

## Verification

- Unit: validate dispatch exits non-zero.

## Open Questions

- none
SPEC
cat >"$NOCONTEXT/tasks.json" <<'JSON'
{"tasks":[{"id":"context-task","title":"Context task","priority":"P2","type":"task","depends_on":[],"outcome":"Dispatch visibly rejects a missing context pack.","slice_strategy":"tracer-bullet","fresh_context_fit":"yes","spec_coverage":["Dispatch is blocked without context."],"grilling_evidence":["synthetic smoke approval","Decision state: approved"],"worker_profile":"none needed","context":"Check context gate.","what_to_do":["Inspect gate."],"files":["`docs/flywheel-runs/nocontext/manifest.json`: manifest"],"acceptance_criteria":["Context is required before dispatch can succeed."],"verification":["test -f docs/flywheel-runs/nocontext/manifest.json"],"out_of_scope":["Product code."]}]}
JSON
"$RUNNER" beads --project "$NOCONTEXT" --run-id nocontext --beads-json "$NOCONTEXT/tasks.json" >/dev/null
"$RUNNER" briefs --project "$NOCONTEXT" --run-id nocontext >/dev/null
expect_failure "dispatch requires context pack" "$RUNNER" dispatch --project "$NOCONTEXT" --run-id nocontext
expect_failure "context blocks external files by default" "$RUNNER" context --project "$NOCONTEXT" --run-id nocontext --file /etc/hosts --force

DRAFT="$TMPROOT/draft"
"$RUNNER" intake --project "$DRAFT" --run-id draft --feature "Draft dispatch smoke" >/dev/null
"$RUNNER" context --project "$DRAFT" --run-id draft >/dev/null
"$RUNNER" spec --project "$DRAFT" --run-id draft >/dev/null
cat >"$DRAFT/docs/specs/draft-dispatch-smoke.md" <<'SPEC'
# Feature Spec: Draft dispatch smoke

Status: Draft
Owner: orchestrator
Date: 2026-06-25

## Grilling Evidence

- Session/artifact: synthetic smoke approval
- Decision state: approved
- ADR/glossary changes: none

## Goal

Verify Draft specs do not dispatch.

## Problem

Draft specs are not approved implementation contracts.

## In Scope

- Generate one task from a Draft spec.

## Out of Scope

- Product code changes.

## Acceptance Criteria

- [ ] Dispatch is blocked.

## Verification

- Unit: dispatch exits non-zero.

## Open Questions

- none
SPEC
cat >"$DRAFT/tasks.json" <<'JSON'
{"tasks":[{"id":"draft-task","title":"Draft task","priority":"P2","type":"task","depends_on":[],"outcome":"Dispatch visibly rejects an unapproved draft.","slice_strategy":"tracer-bullet","fresh_context_fit":"yes","spec_coverage":["Draft dispatch is blocked."],"grilling_evidence":["synthetic smoke approval","Decision state: approved"],"worker_profile":"none needed","context":"Check draft gate.","what_to_do":["Inspect gate."],"files":["`docs/flywheel-runs/draft/manifest.json`: manifest"],"acceptance_criteria":["Draft status prevents worker dispatch."],"verification":["test -f docs/flywheel-runs/draft/manifest.json"],"out_of_scope":["Product code."]}]}
JSON
"$RUNNER" beads --project "$DRAFT" --run-id draft --beads-json "$DRAFT/tasks.json" >/dev/null
"$RUNNER" briefs --project "$DRAFT" --run-id draft >/dev/null
expect_failure "dispatch blocks Draft spec" "$RUNNER" dispatch --project "$DRAFT" --run-id draft

PUBLISH="$TMPROOT/publish"
mkdir -p "$PUBLISH"
git -C "$PUBLISH" init >/dev/null 2>&1
printf '%s\n' '# Publish smoke' >"$PUBLISH/README.md"
"$RUNNER" intake --project "$PUBLISH" --run-id publish --feature "Publication gate smoke" >/dev/null
"$RUNNER" context --project "$PUBLISH" --run-id publish >/dev/null
"$RUNNER" spec --project "$PUBLISH" --run-id publish >/dev/null
cat >"$PUBLISH/docs/specs/publication-gate-smoke.md" <<'SPEC'
# Feature Spec: Publication gate smoke

Status: Approved
Owner: orchestrator
Date: 2026-06-25

## Grilling Evidence

- Session/artifact: synthetic smoke approval
- Decision state: approved
- ADR/glossary changes: none

## Goal

Verify final validation requires worker reports and approved semantic review.

## Problem

Publication should not rely only on artifact presence.

## In Scope

- Generate one dispatchable task and complete its report.

## Out of Scope

- Product code changes.

## Acceptance Criteria

- [ ] Status is green only after worker report, approved review, optimization, git lane, and PR lane exist.

## Verification

- Integration: status exits zero after all publication artifacts exist.

## Open Questions

- none
SPEC
cat >"$PUBLISH/tasks.json" <<'JSON'
{"tasks":[{"id":"publish-task","title":"Publish task","priority":"P2","type":"task","depends_on":[],"outcome":"The publication happy path remains independently verifiable.","slice_strategy":"tracer-bullet","fresh_context_fit":"yes","spec_coverage":["Publication requires passing evidence."],"grilling_evidence":["synthetic smoke approval","Decision state: approved"],"worker_profile":"none needed","context":"Check the publication gate happy path.","what_to_do":["Inspect publication gates."],"files":["`README.md`: synthetic project marker"],"acceptance_criteria":["README marker remains present after publication checks."],"verification":["test -f README.md"],"out_of_scope":["Product code."]},{"id":"publish-second-task","title":"Publish second task","priority":"P2","type":"task","depends_on":[],"outcome":"Publication waits visibly for every worker report.","slice_strategy":"tracer-bullet","fresh_context_fit":"yes","spec_coverage":["Every task has a completed report."],"grilling_evidence":["synthetic smoke approval","Decision state: approved"],"worker_profile":"none needed","context":"Check that publication waits for all task reports.","what_to_do":["Inspect all-task report coverage."],"files":["`README.md`: synthetic project marker"],"acceptance_criteria":["The second worker report is required before publication."],"verification":["test -f README.md"],"out_of_scope":["Product code."]}]}
JSON
"$RUNNER" beads --project "$PUBLISH" --run-id publish --beads-json "$PUBLISH/tasks.json" >/dev/null
"$RUNNER" briefs --project "$PUBLISH" --run-id publish >/dev/null
"$RUNNER" dispatch --project "$PUBLISH" --run-id publish >/dev/null
expect_failure "final validation requires worker report and review" "$RUNNER" validate --project "$PUBLISH" --run-id publish --stage final
expect_failure "complete worker report requires verification evidence" \
  "$RUNNER" worker-report --project "$PUBLISH" --run-id publish --task publish-task --behavior "Incomplete report should fail."
"$RUNNER" worker-report \
  --project "$PUBLISH" \
  --run-id publish \
  --task publish-task \
  --agent smoke-worker \
  --file-changed "No product files changed." \
  --behavior "Publication gate path verified." \
  --verification "test -f README.md: passed" >/dev/null
expect_failure "final validation requires reports for all task beads" "$RUNNER" validate --project "$PUBLISH" --run-id publish --stage final
"$RUNNER" worker-report \
  --project "$PUBLISH" \
  --run-id publish \
  --task publish-second-task \
  --agent smoke-worker \
  --file-changed "No product files changed." \
  --behavior "All-task worker report coverage verified." \
  --verification "test -f README.md: passed" >/dev/null
"$RUNNER" review --project "$PUBLISH" --run-id publish --command "test -f README.md" >/dev/null
expect_failure "final validation requires approved semantic review" "$RUNNER" validate --project "$PUBLISH" --run-id publish --stage final
"$RUNNER" review \
  --project "$PUBLISH" \
  --run-id publish \
  --command "test -f README.md" \
  --semantic-verdict approved \
  --finding "No correctness issues found in the synthetic publication gate run." \
  --test-gap "No residual test gap for the smoke scenario." \
  --force >/dev/null
"$RUNNER" validate --project "$PUBLISH" --run-id publish --stage final >/dev/null
"$RUNNER" validate --project "$PUBLISH" --run-id publish --stage auto >/dev/null
"$RUNNER" optimize --project "$PUBLISH" --run-id publish >/dev/null
"$RUNNER" git-lane --project "$PUBLISH" --run-id publish >/dev/null
"$RUNNER" pr-lane --project "$PUBLISH" --run-id publish --draft >/dev/null
"$RUNNER" status --project "$PUBLISH" --run-id publish >/dev/null
log "PASS: publication gate requires worker report and approved semantic review"

BEFORE_BRANCH="$(git -C "$PUBLISH" branch --show-current)"
expect_failure "git-lane execute preflights artifact overwrite before branch mutation" \
  "$RUNNER" git-lane --project "$PUBLISH" --run-id publish --create-branch --branch codex/publish-smoke --execute
AFTER_BRANCH="$(git -C "$PUBLISH" branch --show-current)"
if [[ "$BEFORE_BRANCH" != "$AFTER_BRANCH" ]]; then
  log "FAIL: git-lane changed branch before local overwrite preflight"
  exit 1
fi
log "PASS: git-lane preflight prevented branch mutation"

if command -v br >/dev/null 2>&1; then
  RUNREADY="$TMPROOT/runready"
  "$RUNNER" intake --project "$RUNREADY" --run-id runready --feature "Run ready-only smoke" >/dev/null
  "$RUNNER" context --project "$RUNREADY" --run-id runready >/dev/null
  "$RUNNER" spec --project "$RUNREADY" --run-id runready >/dev/null
  cat >"$RUNREADY/docs/specs/run-ready-only-smoke.md" <<'SPEC'
# Feature Spec: Run ready-only smoke

Status: Approved
Owner: orchestrator
Date: 2026-06-25

## Grilling Evidence

- Session/artifact: synthetic smoke approval
- Decision state: approved
- ADR/glossary changes: none

## Goal

Verify `run --phase dispatch` respects br ready tasks.

## Problem

Sequenced orchestration must not launch dependent beads early.

## In Scope

- Create two dependent br beads.

## Out of Scope

- Product code changes.

## Acceptance Criteria

- [ ] Only the base task is dispatched.

## Verification

- Integration: inspect worker-dispatch.json.

## Open Questions

- none
SPEC
  cat >"$RUNREADY/tasks.json" <<'JSON'
{"tasks":[{"id":"base-task","title":"Base task","priority":"P2","type":"task","depends_on":[],"outcome":"The base capability becomes independently observable.","slice_strategy":"tracer-bullet","fresh_context_fit":"yes","spec_coverage":["Base capability exists."],"grilling_evidence":["synthetic smoke approval","Decision state: approved"],"worker_profile":"none needed","context":"Base task.","what_to_do":["Do base work."],"files":["`docs/flywheel-runs/runready/base.md`: base"],"acceptance_criteria":["The base capability exists and can be verified independently."],"verification":["test -f docs/flywheel-runs/runready/manifest.json"],"out_of_scope":["Dependent work."]},{"id":"dependent-task","title":"Dependent task","priority":"P2","type":"task","depends_on":["base-task"],"outcome":"Dependent work becomes observable only after its blocker clears.","slice_strategy":"tracer-bullet","fresh_context_fit":"yes","spec_coverage":["Dependency frontier is enforced."],"grilling_evidence":["synthetic smoke approval","Decision state: approved"],"worker_profile":"none needed","context":"Dependent task.","what_to_do":["Do dependent work."],"files":["`docs/flywheel-runs/runready/dependent.md`: dependent"],"acceptance_criteria":["The dependent task remains blocked until base work completes."],"verification":["test -f docs/flywheel-runs/runready/manifest.json"],"out_of_scope":["Base work."]}]}
JSON
  "$RUNNER" beads --project "$RUNREADY" --run-id runready --beads-json "$RUNREADY/tasks.json" --create-br-beads >/dev/null
  "$RUNNER" briefs --project "$RUNREADY" --run-id runready >/dev/null
  "$RUNNER" run --project "$RUNREADY" --run-id runready --phase dispatch >/dev/null
  python3 - "$RUNREADY/docs/flywheel-runs/runready/dispatch/worker-dispatch.json" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text())
ids = [packet["task_id"] for packet in payload.get("packets", [])]
if ids != ["base-task"]:
    raise SystemExit(f"expected only base-task, got {ids!r}")
PY
  log "PASS: run dispatch auto-filters br-ready tasks"
else
  log "SKIP: br not available for run ready-only smoke"
fi

log "PASS: flywheel runner smoke passed"
