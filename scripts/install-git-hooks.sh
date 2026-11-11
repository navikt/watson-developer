#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPOS_DIR="$ROOT_REPO_DIR/repos"
HOOKS_PATH="$SCRIPT_DIR/git-hooks"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

force=false
for arg in "$@"; do
  case "$arg" in
    --force) force=true ;;
    *) echo "Bruk: $0 [--force]" >&2; exit 2 ;;
  esac
done

echo "🔧 Installerer fnr-guard Git-hooker"
if ! (cd "$SCRIPT_DIR/fnr-guard" && npm ci --ignore-scripts >/dev/null 2>&1); then
  echo -e "${RED}✗${NC} Kunne ikke installere fnr-guard-avhengigheter"
  exit 1
fi

installed=0
skipped=0
for repo_path in "$REPOS_DIR"/*/; do
  [ -d "$repo_path" ] || continue
  if ! git -C "$repo_path" rev-parse --git-dir >/dev/null 2>&1; then
    continue
  fi

  existing_hooks_path="$(git -C "$repo_path" config --get core.hooksPath || true)"
  if [ -z "$existing_hooks_path" ] || [ "$existing_hooks_path" = "$HOOKS_PATH" ] || [ "$force" = true ]; then
    git -C "$repo_path" config core.hooksPath "$HOOKS_PATH"
    echo -e "  ${GREEN}✓${NC} $(basename "$repo_path"): fnr-guard installert"
    installed=$((installed + 1))
  else
    echo -e "  ${YELLOW}⚠${NC} $(basename "$repo_path"): eksisterende core.hooksPath beholdt ($existing_hooks_path); bruk --force for å overstyre"
    skipped=$((skipped + 1))
  fi
done

echo "✅ Ferdig: $installed installert, $skipped hoppet over"
