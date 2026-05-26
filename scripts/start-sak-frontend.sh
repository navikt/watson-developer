#!/usr/bin/env bash
# Starter watson-sak-frontend lokalt via Tilt.
#
# Tilt kjører serve_cmd i ikke-interaktivt sh-subshell som ikke laster
# .zshrc/.bash_profile. pnpm er derfor ikke i PATH med mindre vi legger
# til vanlige installasjonslokasjoner manuelt.
set -euo pipefail

# Vanlige macOS-stier for pnpm (homebrew, corepack, volta, fnm)
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/share/pnpm:$HOME/Library/pnpm:$HOME/.volta/bin:$PATH"

if ! command -v pnpm &>/dev/null; then
    echo "FEIL: pnpm ikke funnet. Installer med: corepack enable"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TOKEN=$(curl -sf -X POST http://localhost:8090/azuread/token \
  -d "grant_type=client_credentials&client_id=watson-admin-api&client_secret=mock-secret" | \
  python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

cd "$SCRIPT_DIR/../../watson-sak-frontend"

exec env CLUSTER=local \
  FARO_URL=http://localhost:9999 \
  UMAMI_SITE_ID=local \
  IDENT_SESSION_SECRET=local-dev-secret \
  DEVELOPMENT_OAUTH_TOKEN="$TOKEN" \
  pnpm run dev:local
