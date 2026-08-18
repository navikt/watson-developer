#!/usr/bin/env bash
set -euo pipefail

# Sjekker ut main og henter nyeste endringer i alle git-repoer i foreldremappen.
# Idempotent — trygt å kjøre flere ganger.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "🔄 Synkroniserer repoer i: $PARENT_DIR"
echo ""

failed=0
found=0

for repo_path in "$PARENT_DIR"/*/; do
  [ -d "$repo_path/.git" ] || continue
  found=$((found + 1))
  repo_name="$(basename "$repo_path")"

  echo "📦 $repo_name"

  if [ -n "$(git -C "$repo_path" status --porcelain --untracked-files=no)" ]; then
    echo -e "  ${YELLOW}⟳${NC} Hopper over — ukommiterte endringer"
    continue
  fi

  # Finn standardbranch (main, evt. master eller det remote peker på)
  default_branch="$(git -C "$repo_path" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)"
  if [ -z "$default_branch" ]; then
    if git -C "$repo_path" show-ref --verify --quiet refs/heads/main; then
      default_branch="main"
    elif git -C "$repo_path" show-ref --verify --quiet refs/heads/master; then
      default_branch="master"
    else
      echo -e "  ${RED}✗${NC} Fant ingen standardbranch"
      failed=$((failed + 1))
      continue
    fi
  fi

  current_branch="$(git -C "$repo_path" rev-parse --abbrev-ref HEAD)"
  if [ "$current_branch" != "$default_branch" ]; then
    if git -C "$repo_path" checkout --quiet "$default_branch"; then
      echo -e "  ${GREEN}✓${NC} Byttet fra $current_branch til $default_branch"
    else
      echo -e "  ${RED}✗${NC} Kunne ikke bytte til $default_branch"
      failed=$((failed + 1))
      continue
    fi
  fi

  if git -C "$repo_path" pull --ff-only --quiet; then
    echo -e "  ${GREEN}✓${NC} Oppdatert ($default_branch)"
  else
    echo -e "  ${RED}✗${NC} Kunne ikke hente nyeste"
    failed=$((failed + 1))
  fi
done

echo ""
if [ "$found" -eq 0 ]; then
  echo -e "${YELLOW}⟳${NC} Fant ingen git-repoer i $PARENT_DIR"
  exit 0
fi

if [ "$failed" -gt 0 ]; then
  echo -e "${RED}✗${NC} Ferdig med $failed feil"
  exit 1
fi

echo "✅ Alle repoer er oppdatert!"
