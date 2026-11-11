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
status=false
for arg in "$@"; do
  case "$arg" in
    --force) force=true ;;
    --status) status=true ;;
    *) echo "Bruk: $0 [--force | --status]" >&2; exit 2 ;;
  esac
done

# --status: vis om fnr-guard er aktiv i hvert repo, uten å endre noe.
# Exit 1 hvis noe mangler.
if [ "$status" = true ]; then
  missing=0
  if ! command -v node >/dev/null 2>&1; then
    echo -e "  ${RED}✗${NC} node mangler, hooken stopper alle commits"
    missing=$((missing + 1))
  fi
  found=0
  for repo_path in "$REPOS_DIR"/*/; do
    [ -d "$repo_path" ] || continue
    git -C "$repo_path" rev-parse --git-dir >/dev/null 2>&1 || continue
    found=$((found + 1))
    name="$(basename "$repo_path")"
    current="$(git -C "$repo_path" config --get core.hooksPath || true)"
    if [ "$current" = "$HOOKS_PATH" ]; then
      echo -e "  ${GREEN}✓${NC} $name"
    elif [ -z "$current" ]; then
      echo -e "  ${RED}✗${NC} $name: fnr-guard er ikke installert"
      missing=$((missing + 1))
    else
      echo -e "  ${RED}✗${NC} $name: core.hooksPath peker et annet sted ($current)"
      missing=$((missing + 1))
    fi
  done
  if [ "$found" -eq 0 ]; then
    echo -e "  ${YELLOW}⚠${NC} Fant ingen repoer i $REPOS_DIR"
  fi
  if [ "$missing" -gt 0 ]; then
    echo -e "  Kjør ${YELLOW}$SCRIPT_DIR/install-git-hooks.sh${NC} utenfor sandboxen for å installere."
    exit 1
  fi
  exit 0
fi

echo "🔧 Installerer fnr-guard Git-hooker"

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
