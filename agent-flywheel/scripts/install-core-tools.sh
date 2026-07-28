#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

DRY_RUN=1

usage() {
  cat <<'EOF'
Usage: scripts/install-core-tools.sh [--execute]

Installs or prints the upstream core tools used by the internal flywheel:
  - br  (beads_rust)
  - bv  (beads_viewer)
  - Agent Mail (mcp-agent-mail / am)

Default is dry-run. Pass --execute only after reviewing the commands.
Network access and writes outside this repository are required.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --execute)
      DRY_RUN=0
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

run_shell() {
  local cmd="$1"
if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN: %s\n' "$cmd"
  else
    bash -lc "$cmd"
fi
}

echo "Core tool install plan"
echo "Mode: $([[ "$DRY_RUN" -eq 1 ]] && echo dry-run || echo execute)"
echo ""

run_shell 'curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/beads_rust/main/install.sh?$(date +%s)" | bash'
run_shell 'curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/beads_viewer/main/install.sh?$(date +%s)" | bash'
run_shell 'curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/mcp_agent_mail_rust/main/install.sh?$(date +%s)" | bash'

echo ""
if [[ "$DRY_RUN" -eq 0 ]]; then
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
    printf 'Install incomplete; missing: %s\n' "${missing[*]}" >&2
    exit 1
  fi
fi

echo "After install, run:"
echo "  scripts/check-flywheel.sh"
echo "  scripts/run-sandbox-flow.py --clean"
