#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${CODEX_HOME:-$HOME/.codex}/skills"
MODE="symlink"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: scripts/install-skills.sh [--copy|--symlink] [--target PATH] [--dry-run]

Installs the flywheel Codex skills into the Codex skills directory.

Defaults:
  mode:   symlink
  target: ${CODEX_HOME:-$HOME/.codex}/skills
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --copy)
      MODE="copy"
      shift
      ;;
    --symlink)
      MODE="symlink"
      shift
      ;;
    --target)
      TARGET="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
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

skills=(
  feature-spec-architect
  implementation-orchestrator
  worker-profile-factory
  code-quality-governor
  simplify-and-refactor-code-isomorphically
  workflow-optimizer
  study-prompt-system-designer
  study-rag-architect
  generate-morphology-first-anatomy-cards
)

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY-RUN:'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

echo "Installing skills from $ROOT/skills to $TARGET ($MODE)"
run mkdir -p "$TARGET"

for skill in "${skills[@]}"; do
  source="$ROOT/skills/$skill"
  dest="$TARGET/$skill"
  if [[ ! -d "$source" ]]; then
    echo "Missing skill source: $source" >&2
    exit 1
  fi

  if [[ -e "$dest" || -L "$dest" ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "DRY-RUN: would replace $dest"
    else
      backup="$dest.backup.$(date +%Y%m%d%H%M%S)"
      mv "$dest" "$backup"
      echo "Backed up existing $dest to $backup"
    fi
  fi

  if [[ "$MODE" == "copy" ]]; then
    run cp -R "$source" "$dest"
  else
    run ln -s "$source" "$dest"
  fi
done

echo "Done. Restart Codex so skill metadata is loaded."
