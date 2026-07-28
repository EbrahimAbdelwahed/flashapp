#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.local/bin:$PATH"
FAILURES=0

log() {
  printf '%s\n' "$*"
}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  FAILURES=$((FAILURES + 1))
}

pass() {
  printf 'PASS: %s\n' "$*"
}

require_file() {
  local file="$1"
  if [[ -f "$ROOT/$file" ]]; then
    pass "$file exists"
  else
    fail "$file missing"
  fi
}

require_absent_pattern() {
  local pattern="$1"
  local description="$2"
  if rg -n "$pattern" "$ROOT" \
    --glob '!scripts/check-flywheel.sh' \
    --glob '!**/scripts/check-flywheel.sh' \
    --glob '!sandbox/**' >/tmp/flywheel-rg.$$ 2>/dev/null; then
    fail "$description"
    sed -n '1,20p' /tmp/flywheel-rg.$$ >&2
  else
    pass "$description"
  fi
  rm -f /tmp/flywheel-rg.$$
}

validate_skill() {
  local skill="$1"
  local path="$ROOT/skills/$skill/SKILL.md"
  if [[ ! -f "$path" ]]; then
    fail "skill $skill missing"
    return
  fi

  python3 - "$path" "$skill" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
expected_name = sys.argv[2]
text = path.read_text(encoding="utf-8")
if not text.startswith("---\n"):
    print(f"frontmatter missing: {path}", file=sys.stderr)
    sys.exit(1)
end = text.find("\n---\n", 4)
if end == -1:
    print(f"frontmatter terminator missing: {path}", file=sys.stderr)
    sys.exit(1)
frontmatter = text[4:end].strip().splitlines()
fields = {}
for line in frontmatter:
    if ":" not in line:
        print(f"invalid frontmatter line in {path}: {line}", file=sys.stderr)
        sys.exit(1)
    key, value = line.split(":", 1)
    fields[key.strip()] = value.strip()
if set(fields) != {"name", "description"}:
    print(f"frontmatter must contain only name and description in {path}: {sorted(fields)}", file=sys.stderr)
    sys.exit(1)
if fields["name"] != expected_name:
    print(f"skill name mismatch in {path}: {fields['name']} != {expected_name}", file=sys.stderr)
    sys.exit(1)
if not fields["description"]:
    print(f"description missing in {path}", file=sys.stderr)
    sys.exit(1)
PY
  pass "skill $skill frontmatter valid"
}

log "Checking flywheel scaffold at $ROOT"

require_file "README.md"
require_file "AGENTS.md"
require_file "docs/internal-flywheel-architecture.md"
require_file "docs/workflow.md"
require_file "docs/flywheel-runner.md"
require_file "docs/installing-skills.md"
require_file "templates/feature-spec.md"
require_file "templates/task-bead.md"
require_file "templates/worker-profile.md"
require_file "templates/worker-brief.md"
require_file "templates/decision-request.md"
require_file "templates/review-report.md"
require_file "templates/workflow-improvement.md"
require_file "templates/session-end-checklist.md"
require_file "scripts/flywheel.py"
require_file "scripts/flywheel-core.py"
require_file "scripts/flywheel-runner.py"
require_file "scripts/run-runner-smoke.sh"

validate_skill "feature-spec-architect"
validate_skill "implementation-orchestrator"
validate_skill "worker-profile-factory"
validate_skill "code-quality-governor"
validate_skill "simplify-and-refactor-code-isomorphically"
validate_skill "workflow-optimizer"
validate_skill "study-prompt-system-designer"
validate_skill "study-rag-architect"
validate_skill "generate-morphology-first-anatomy-cards"

require_file "skills/generate-morphology-first-anatomy-cards/agents/openai.yaml"
require_file "skills/generate-morphology-first-anatomy-cards/references/style-contract.md"
require_file "skills/generate-morphology-first-anatomy-cards/references/few-shot-examples.md"
require_file "skills/generate-morphology-first-anatomy-cards/scripts/validate_cards.py"

require_absent_pattern "Assign a worker type|domain-worker|backend-worker|frontend-worker|prompt-worker|rag-worker|srs-worker|test-worker|docs-worker|reviewer-worker" "no fixed worker taxonomy remains"
require_absent_pattern "mobile-first oversight is a core requirement|Mobile is oversight" "no mobile-first requirement remains"

log ""
log "Core tool availability:"
for cmd in br bv mcp-agent-mail am; do
  if command -v "$cmd" >/dev/null 2>&1; then
    version="$("$cmd" --version 2>/dev/null || true)"
    pass "$cmd available ${version:+($version)}"
  else
    log "WARN: $cmd not found"
  fi
done

if [[ -d "$ROOT/sandbox/sample-flow" ]]; then
  if "$ROOT/scripts/flywheel.py" --project "$ROOT/sandbox/sample-flow" doctor --json >/tmp/flywheel-doctor.$$ 2>/tmp/flywheel-doctor-err.$$; then
    pass "local flywheel doctor passed"
  else
    fail "local flywheel doctor failed"
    cat /tmp/flywheel-doctor.$$ >&2 || true
    cat /tmp/flywheel-doctor-err.$$ >&2 || true
  fi
  rm -f /tmp/flywheel-doctor.$$ /tmp/flywheel-doctor-err.$$
else
  log "WARN: sandbox/sample-flow not found; run scripts/run-sandbox-flow.py --clean for full local doctor"
fi

if python3 -m py_compile "$ROOT/scripts/flywheel.py" "$ROOT/scripts/flywheel-core.py" "$ROOT/scripts/flywheel-runner.py" >/tmp/flywheel-pycompile.$$ 2>/tmp/flywheel-pycompile-err.$$; then
  pass "python CLIs compile"
else
  fail "python CLIs failed to compile"
  cat /tmp/flywheel-pycompile.$$ >&2 || true
  cat /tmp/flywheel-pycompile-err.$$ >&2 || true
fi
rm -f /tmp/flywheel-pycompile.$$ /tmp/flywheel-pycompile-err.$$

if python3 "$ROOT/skills/generate-morphology-first-anatomy-cards/scripts/validate_cards.py" --self-test >/tmp/anatomy-card-validator.$$ 2>/tmp/anatomy-card-validator-err.$$; then
  pass "anatomy card validator self-test passed"
else
  fail "anatomy card validator self-test failed"
  cat /tmp/anatomy-card-validator.$$ >&2 || true
  cat /tmp/anatomy-card-validator-err.$$ >&2 || true
fi
rm -f /tmp/anatomy-card-validator.$$ /tmp/anatomy-card-validator-err.$$

if "$ROOT/scripts/flywheel-runner.py" plan --project "$ROOT/sandbox/runner-plan-smoke" --feature "Smoke feature" >/tmp/flywheel-runner-plan.$$ 2>/tmp/flywheel-runner-plan-err.$$; then
  pass "flywheel runner plan smoke passed"
else
  fail "flywheel runner plan smoke failed"
  cat /tmp/flywheel-runner-plan.$$ >&2 || true
  cat /tmp/flywheel-runner-plan-err.$$ >&2 || true
fi
rm -f /tmp/flywheel-runner-plan.$$ /tmp/flywheel-runner-plan-err.$$

if "$ROOT/scripts/flywheel-runner.py" commands >/tmp/flywheel-runner-commands.$$ 2>/tmp/flywheel-runner-commands-err.$$; then
  pass "flywheel runner commands manifest passed"
else
  fail "flywheel runner commands manifest failed"
  cat /tmp/flywheel-runner-commands.$$ >&2 || true
  cat /tmp/flywheel-runner-commands-err.$$ >&2 || true
fi
rm -f /tmp/flywheel-runner-commands.$$ /tmp/flywheel-runner-commands-err.$$

if "$ROOT/scripts/flywheel-runner.py" doctor --project "$ROOT" >/tmp/flywheel-runner-doctor.$$ 2>/tmp/flywheel-runner-doctor-err.$$; then
  pass "flywheel runner doctor smoke passed"
else
  fail "flywheel runner doctor smoke failed"
  cat /tmp/flywheel-runner-doctor.$$ >&2 || true
  cat /tmp/flywheel-runner-doctor-err.$$ >&2 || true
fi
rm -f /tmp/flywheel-runner-doctor.$$ /tmp/flywheel-runner-doctor-err.$$

if "$ROOT/scripts/flywheel-core.py" commands >/tmp/flywheel-core-commands.$$ 2>/tmp/flywheel-core-commands-err.$$; then
  pass "flywheel core commands manifest passed"
else
  fail "flywheel core commands manifest failed"
  cat /tmp/flywheel-core-commands.$$ >&2 || true
  cat /tmp/flywheel-core-commands-err.$$ >&2 || true
fi
rm -f /tmp/flywheel-core-commands.$$ /tmp/flywheel-core-commands-err.$$

if "$ROOT/scripts/flywheel-runner.py" run --help >/tmp/flywheel-runner-run.$$ 2>/tmp/flywheel-runner-run-err.$$; then
  pass "flywheel runner run smoke passed"
else
  fail "flywheel runner run smoke failed"
  cat /tmp/flywheel-runner-run.$$ >&2 || true
  cat /tmp/flywheel-runner-run-err.$$ >&2 || true
fi
rm -f /tmp/flywheel-runner-run.$$ /tmp/flywheel-runner-run-err.$$

if "$ROOT/scripts/run-runner-smoke.sh" >/tmp/flywheel-runner-smoke.$$ 2>/tmp/flywheel-runner-smoke-err.$$; then
  pass "flywheel runner end-to-end smoke passed"
else
  fail "flywheel runner end-to-end smoke failed"
  cat /tmp/flywheel-runner-smoke.$$ >&2 || true
  cat /tmp/flywheel-runner-smoke-err.$$ >&2 || true
fi
rm -f /tmp/flywheel-runner-smoke.$$ /tmp/flywheel-runner-smoke-err.$$

if [[ "$FAILURES" -gt 0 ]]; then
  log ""
  fail "$FAILURES check(s) failed"
  exit 1
fi

log ""
pass "flywheel scaffold checks passed"
