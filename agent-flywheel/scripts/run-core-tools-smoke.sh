#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.local/bin:$PATH"
SANDBOX="$ROOT/sandbox/core-tools-smoke"
REQUIRE_TOOLS=0
CLEAN=0

usage() {
  cat <<'EOF'
Usage: scripts/run-core-tools-smoke.sh [--clean] [--require-tools]

Runs a live integration smoke test for upstream Agent Flywheel core tools when
they are installed:
  - br
  - bv
  - mcp-agent-mail / am

Without --require-tools, missing tools are reported as SKIP instead of failure.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean)
      CLEAN=1
      shift
      ;;
    --require-tools)
      REQUIRE_TOOLS=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

missing=()
for cmd in br bv; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    missing+=("$cmd")
  fi
done

if ! command -v mcp-agent-mail >/dev/null 2>&1 && ! command -v am >/dev/null 2>&1; then
  missing+=("mcp-agent-mail-or-am")
fi

if [[ "${#missing[@]}" -gt 0 ]]; then
  printf 'SKIP: missing core tool(s): %s\n' "${missing[*]}"
  if [[ "$REQUIRE_TOOLS" -eq 1 ]]; then
    exit 1
  fi
  exit 0
fi

if [[ "$CLEAN" -eq 1 && -d "$SANDBOX" ]]; then
  rm -rf "$SANDBOX"
fi

mkdir -p "$SANDBOX"
cd "$SANDBOX"

echo "# Core tools smoke sandbox" > README.md

if [[ ! -d .git ]]; then
  git init >/dev/null
fi

if [[ ! -d .beads ]]; then
  br init
fi

issue_output="$(br create "Smoke: define dynamic worker profile" --type task --priority 2 --json)"
issue_id="$(printf '%s\n' "$issue_output" | python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get("id") or data.get("issue",{}).get("id") or data.get("identifier") or "")')"
if [[ -z "$issue_id" ]]; then
  echo "Could not parse br issue id from:"
  printf '%s\n' "$issue_output"
  exit 1
fi

br ready --json > br-ready.json
br show "$issue_id" --json > br-show.json
br sync --flush-only

bv --robot-triage > bv-triage.json

if command -v mcp-agent-mail >/dev/null 2>&1; then
  mcp-agent-mail --help > agent-mail-help.txt || true
fi
if command -v am >/dev/null 2>&1; then
  am --help > am-help.txt || true
fi

python3 - <<'PY'
import json
from pathlib import Path

checks = {
    "br_ready_json": Path("br-ready.json").exists(),
    "br_show_json": Path("br-show.json").exists(),
    "bv_triage_json": Path("bv-triage.json").exists(),
    "agent_mail_help": Path("agent-mail-help.txt").exists() or Path("am-help.txt").exists(),
}
Path("smoke-report.json").write_text(json.dumps(checks, indent=2, sort_keys=True) + "\n")
if not all(checks.values()):
    raise SystemExit(1)
PY

echo "PASS: core tools smoke completed in $SANDBOX"
