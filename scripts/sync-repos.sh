#!/usr/bin/env bash
set -euo pipefail

# Sjekker ut standardbranch (via origin/HEAD, fallback main/master) og henter
# nyeste endringer i watson-developer og alle git-repoer i repos-mappen.
# Idempotent og trygt å kjøre flere ganger.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPOS_DIR="$ROOT_REPO_DIR/repos"
mkdir -p "$REPOS_DIR"
REPOS_DIR="$(cd "$REPOS_DIR" && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "🔄 Synkroniserer watson-developer og repoer i: $REPOS_DIR"
echo ""

failed=0
found=0
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

sync_repo() {
  local repo_path="$1"
  local repo_name
  local default_branch
  local current_branch

  repo_name="$(basename "$repo_path")"
  echo "📦 $repo_name"

  # Usporede filer ignoreres bevisst. De blokkerer ikke checkout eller ff-only pull,
  # og lokale artefakter (build/, .env, .DS_Store) skal ikke hindre synkronisering.
  if [ -n "$(git -C "$repo_path" status --porcelain --untracked-files=no)" ]; then
    echo -e "  ${YELLOW}⟳${NC} Hopper over: ukommiterte endringer i sporede filer"
    return 0
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
      return 1
    fi
  fi

  current_branch="$(git -C "$repo_path" rev-parse --abbrev-ref HEAD)"
  if [ "$current_branch" != "$default_branch" ]; then
    if git -C "$repo_path" checkout --quiet "$default_branch"; then
      echo -e "  ${GREEN}✓${NC} Byttet fra $current_branch til $default_branch"
    else
      echo -e "  ${RED}✗${NC} Kunne ikke bytte til $default_branch"
      return 1
    fi
  fi

  if git -C "$repo_path" pull --ff-only --quiet; then
    echo -e "  ${GREEN}✓${NC} Oppdatert ($default_branch)"
  else
    echo -e "  ${RED}✗${NC} Kunne ikke hente nyeste"
    return 1
  fi
}

pids=()
output_files=()
repo_paths=("$ROOT_REPO_DIR")

for repo_path in "$REPOS_DIR"/*/; do
  [ -d "$repo_path/.git" ] || continue
  repo_paths+=("$repo_path")
done

for repo_path in "${repo_paths[@]}"; do
  found=$((found + 1))
  output_file="$temp_dir/$found"

  sync_repo "$repo_path" >"$output_file" 2>&1 &
  pids+=("$!")
  output_files+=("$output_file")
done

for i in "${!pids[@]}"; do
  if ! wait "${pids[$i]}"; then
    failed=$((failed + 1))
  fi
  sed 's/^/  /' "${output_files[$i]}"
done

echo ""
if [ "$found" -eq 0 ]; then
  echo -e "${YELLOW}⟳${NC} Fant ingen git-repoer i $REPOS_DIR eller i $ROOT_REPO_DIR"
  exit 0
fi

if [ "$failed" -gt 0 ]; then
  echo -e "${RED}✗${NC} Ferdig med $failed feil"
  exit 1
fi

echo ""
echo "🛡️  fnr-guard"
if [[ -n "${__CPLT_WRAPPED:-}" ]]; then
  # pnpm install og git config er sperret i sandboxen. Sjekk bare status.
  if ! "$SCRIPT_DIR/install-git-hooks.sh" --status; then
    echo -e "  ${YELLOW}⚠${NC}  fnr-guard mangler eller er ikke aktiv i alle repoer. Kjør ./scripts/install-git-hooks.sh i en vanlig terminal utenfor sandboxen"
  fi
elif "$SCRIPT_DIR/install-git-hooks.sh" --status >/dev/null 2>&1; then
  echo -e "  ${GREEN}✓${NC} Installert"
elif ! "$SCRIPT_DIR/install-git-hooks.sh"; then
  echo -e "  ${YELLOW}⚠${NC}  Kunne ikke installere fnr-guard. Kjør ./scripts/install-git-hooks.sh på nytt"
fi

echo ""
echo "🔌 MCP-servere"
if [[ -n "${__CPLT_WRAPPED:-}" ]]; then
  if missing_mcp="$("$ROOT_REPO_DIR/scripts/setup-mcp.sh" --check 2>/dev/null)"; then
    :
  else
    missing_mcp_list="$(printf '%s\n' "$missing_mcp" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    echo -e "  ${YELLOW}⚠${NC}  Mangler MCP-servere: $missing_mcp_list. Kjør ./scripts/setup-mcp.sh i en vanlig terminal"
  fi
else
  if ! "$ROOT_REPO_DIR/scripts/setup-mcp.sh" --missing-only; then
    echo -e "  ${YELLOW}⚠${NC}  Kunne ikke sette opp MCP-serverne automatisk. Kjør ./scripts/setup-mcp.sh i en vanlig terminal."
  fi
fi

echo "✅ Alle repoer er oppdatert!"
