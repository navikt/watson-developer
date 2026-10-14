#!/usr/bin/env bash
set -euo pipefail

# Henter og lagrer tokens for testidentene som brukes i lasttesten av watson-admin-api.
# Tokenene hentes manuelt fra azure-token-generator (innlogging som testident i nettleseren)
# og limes inn skjult. Fila er git-ignorert og lesbar bare for eieren.
#
# Bruk:
#   ./scripts/lasttest-tokens.sh            # legg til eller erstatt identer
#   ./scripts/lasttest-tokens.sh --nullstill # start med tom tokenfil
#   ./scripts/lasttest-tokens.sh --status    # vis identer og utløpstid, uten tokens
#
# Idempotent: samme navIdent erstattes, ikke dupliseres.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TOKEN_DIR="$ROOT_DIR/loadtest/.tokens"
TOKEN_FIL="$TOKEN_DIR/tokens.json"
AUD="${LASTTEST_AUD:-dev-gcp:holmes:watson-admin-api}"
GENERATOR_URL="https://azure-token-generator.intern.dev.nav.no/api/obo?aud=$AUD"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $1"; }
skip() { echo -e "${YELLOW}⟳${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1" >&2; }

command -v jq >/dev/null || { fail "jq mangler"; exit 1; }

umask 077
mkdir -p "$TOKEN_DIR"
[ -f "$TOKEN_FIL" ] || echo "[]" > "$TOKEN_FIL"
chmod 600 "$TOKEN_FIL"

# Leser JWT-payload (base64url) uten å skrive tokenet noe sted.
jwt_payload() {
  local del
  del="$(cut -d. -f2 <<< "$1" | tr '_-' '/+')"
  while [ $(( ${#del} % 4 )) -ne 0 ]; do del="${del}="; done
  base64 -d <<< "$del" 2>/dev/null
}

vis_status() {
  local naa
  naa="$(date +%s)"
  if [ "$(jq length "$TOKEN_FIL")" -eq 0 ]; then
    skip "Ingen tokens lagret"
    return
  fi
  jq -r '.[] | "\(.navIdent) \(.rolle) \(.token)"' "$TOKEN_FIL" | while read -r ident rolle token; do
    local exp
    exp="$(jwt_payload "$token" | jq -r '.exp // 0' 2>/dev/null || echo 0)"
    local min=$(( (exp - naa) / 60 ))
    if [ "$min" -gt 0 ]; then
      ok "$ident ($rolle): gyldig i $min min"
    else
      fail "$ident ($rolle): utløpt"
    fi
  done
}

case "${1:-}" in
  --status)
    vis_status
    exit 0
    ;;
  --nullstill)
    echo "[]" > "$TOKEN_FIL"
    ok "Tokenfila er tømt"
    ;;
  "") ;;
  *)
    fail "Ukjent argument: $1"
    exit 1
    ;;
esac

echo "Logg inn som testident i et privat nettleservindu og åpne:"
echo "  $GENERATOR_URL"
echo "Lim inn tokenet når du blir bedt om det. Det vises ikke på skjermen."
echo ""

while true; do
  read -r -p "navIdent (tom linje for å avslutte): " ident
  [ -z "$ident" ] && break
  read -r -p "Rolle [saksbehandler/leder] (saksbehandler): " rolle
  rolle="${rolle:-saksbehandler}"
  if [ "$rolle" != "saksbehandler" ] && [ "$rolle" != "leder" ]; then
    fail "Ugyldig rolle: $rolle"
    continue
  fi
  read -r -s -p "Token: " token
  echo ""

  payload="$(jwt_payload "$token" || true)"
  if ! jq -e . >/dev/null 2>&1 <<< "$payload"; then
    fail "Kunne ikke lese tokenet. Prøv igjen."
    continue
  fi
  token_ident="$(jq -r '.NAVident // empty' <<< "$payload")"
  if [ -n "$token_ident" ] && [ "$token_ident" != "$ident" ]; then
    fail "Tokenet tilhører $token_ident, ikke $ident"
    continue
  fi

  tmp="$(mktemp "$TOKEN_DIR/tokens.XXXXXX")"
  jq --arg ident "$ident" --arg rolle "$rolle" --arg token "$token" \
    'map(select(.navIdent != $ident)) + [{navIdent: $ident, rolle: $rolle, token: $token}]' \
    "$TOKEN_FIL" > "$tmp"
  mv "$tmp" "$TOKEN_FIL"
  unset token
  ok "Lagret token for $ident ($rolle)"
done

echo ""
vis_status
