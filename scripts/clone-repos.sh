#!/usr/bin/env bash
set -euo pipefail

# Resolve repos-katalogen (der sibling-repoer klones), oppretter den om nødvendig
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS_DIR="$SCRIPT_DIR/../repos"
mkdir -p "$REPOS_DIR"
REPOS_DIR="$(cd "$REPOS_DIR" && pwd)"

# Watson repos to clone
REPOS=(
  "https://github.com/navikt/holmes-brain.git"
  "https://github.com/navikt/nav-persondata-api.git"
  "https://github.com/navikt/watson-admin-api.git"
  "https://github.com/navikt/watson-guide.git"
  "https://github.com/navikt/watson-sak-frontend.git"
  "https://github.com/navikt/watson-sok.git"
  "https://github.com/navikt/watson-pdfgen.git"
  "https://github.com/navikt/watson-agentpakke.git"
)

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "📁 Kloner watson-repoer til: $REPOS_DIR"
echo ""

clone_repo() {
  local repo_url="$1"
  local repo_name
  local repo_path

  repo_name=$(basename "$repo_url" .git)
  repo_path="$REPOS_DIR/$repo_name"

  if [ -d "$repo_path" ]; then
    echo -e "${YELLOW}⟳${NC} $repo_name eksisterer allerede — oppdaterer..."
    if git -C "$repo_path" pull --ff-only --quiet 2>/dev/null; then
      echo -e "  ${GREEN}✓${NC} Oppdatert"
    else
      echo -e "  ${RED}✗${NC} Kunne ikke oppdatere (sjekk lokale endringer)"
    fi
  else
    echo -e "${GREEN}⬇${NC} Kloner $repo_name..."
    if git clone --quiet "$repo_url" "$repo_path"; then
      echo -e "  ${GREEN}✓${NC} Klonet"
    else
      echo -e "  ${RED}✗${NC} Kloning feilet"
      return 1
    fi
  fi

  # Run setup.sh if it exists in the cloned repo
  if [ -f "$repo_path/setup.sh" ]; then
    echo -e "  ${YELLOW}⚙${NC}  Kjører setup.sh..."
    (cd "$repo_path" && bash setup.sh)
  fi

  if [[ "$repo_name" == "watson-sak-frontend" || "$repo_name" == "watson-sok" ]]; then
    echo -e "  ${YELLOW}📦${NC} Installerer frontend-avhengigheter..."
    (cd "$repo_path" && pnpm install --frozen-lockfile)
  fi
}

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT
pids=()
output_files=()

for repo_url in "${REPOS[@]}"; do
  repo_name=$(basename "$repo_url" .git)
  output_file="$temp_dir/$repo_name"

  clone_repo "$repo_url" >"$output_file" 2>&1 &
  pids+=("$!")
  output_files+=("$output_file")
done

failed=0
for i in "${!pids[@]}"; do
  if ! wait "${pids[$i]}"; then
    failed=$((failed + 1))
  fi
  cat "${output_files[$i]}"
done

echo ""
if [ "$failed" -gt 0 ]; then
  echo -e "${RED}✗${NC} Ferdig med $failed feil"
  exit 1
fi

echo "✅ Ferdig!"
