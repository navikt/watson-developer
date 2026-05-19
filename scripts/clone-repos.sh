#!/usr/bin/env bash
set -euo pipefail

# Resolve the parent directory (where sibling repos will be cloned)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Watson repos to clone
REPOS=(
  "git@github.com:navikt/nav-persondata-api.git"
  "git@github.com:navikt/watson-admin-api.git"
  "git@github.com:navikt/watson-sak-frontend.git"
  "git@github.com:navikt/watson-sok.git"
)

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "📁 Kloner watson-repoer til: $PARENT_DIR"
echo ""

for repo_url in "${REPOS[@]}"; do
  repo_name=$(basename "$repo_url" .git)
  repo_path="$PARENT_DIR/$repo_name"

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
      continue
    fi
  fi

  # Run setup.sh if it exists in the cloned repo
  if [ -f "$repo_path/setup.sh" ]; then
    echo -e "  ${YELLOW}⚙${NC}  Kjører setup.sh..."
    (cd "$repo_path" && bash setup.sh)
  fi
done

echo ""
echo "✅ Ferdig!"
