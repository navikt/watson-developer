#!/usr/bin/env bash
set -euo pipefail

# Henter og lagrer tokens for testidentene som brukes i lasttesten av watson-admin-api.
# Tokenene hentes manuelt fra azure-token-generator (innlogging som testident i nettleseren)
# og limes inn skjult. Fila er git-ignorert og lesbar bare for eieren.
#
# Bruk:
#   ./scripts/lasttest-tokens.sh            # legg til eller erstatt identer
#   ./scripts/lasttest-tokens.sh --nullstill # start med tom tokenfil
#   ./scripts/lasttest-tokens.sh --status    # vis identer og utløpstid, uten tokens.
#                                            # Avslutter med kode 1 hvis et token er utløpt eller ugyldig.
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

STTY_FOR=""
gjenopprett_terminal() { if [ -n "$STTY_FOR" ]; then stty "$STTY_FOR" 2>/dev/null || true; fi; }
trap gjenopprett_terminal EXIT

# Leser tokenet uten ekko. macOS-terminalen godtar høyst 1024 tegn per linje i vanlig modus,
# og Azure-tokens er lengre. Vi slår derfor av linjebufferen mens tokenet leses.
# Tom linje henter tokenet fra utklippstavla (pbpaste).
les_token() {
  token=""
  printf "Token (lim inn og trykk Enter, eller bare Enter for å bruke utklippstavla): "
  if [ -t 0 ]; then
    STTY_FOR="$(stty -g)"
    stty -icanon -echo
    IFS= read -r token || true
    gjenopprett_terminal
    STTY_FOR=""
  else
    IFS= read -r token || true
  fi
  echo ""
  if [ -z "$token" ] && command -v pbpaste >/dev/null; then
    token="$(pbpaste)"
  fi
  # Fjern mellomrom, linjeskift og et eventuelt «Bearer»-prefiks.
  token="$(printf '%s' "$token" | tr -d '[:space:]')"
  token="${token#Bearer}"
  # Godta også JSON-svar med access_token.
  if [ "${token:0:1}" = "{" ]; then
    token="$(printf '%s' "$token" | jq -r '.access_token // empty' 2>/dev/null || true)"
  fi
}

# Leser JWT-payload (base64url) uten å skrive tokenet noe sted.
jwt_payload() {
  local del
  del="$(cut -d. -f2 <<< "$1" | tr '_-' '/+')"
  while [ $(( ${#del} % 4 )) -ne 0 ]; do del="${del}="; done
  base64 -d <<< "$del" 2>/dev/null
}

# Returnerer 1 hvis minst ett token er utløpt eller ikke kan leses.
vis_status() {
  local naa ugyldige=0 ident rolle token exp min
  naa="$(date +%s)"
  if [ "$(jq length "$TOKEN_FIL")" -eq 0 ]; then
    skip "Ingen tokens lagret"
    return 0
  fi
  while read -r ident rolle token; do
    exp="$(jwt_payload "$token" | jq -r '.exp // 0' 2>/dev/null || true)"
    [[ "$exp" =~ ^[0-9]+$ ]] || exp=0
    min=$(( (exp - naa) / 60 ))
    if [ "$min" -gt 0 ]; then
      ok "$ident ($rolle): gyldig i $min min"
    else
      fail "$ident ($rolle): utløpt eller ugyldig"
      ugyldige=$((ugyldige + 1))
    fi
  done < <(jq -r '.[] | "\(.navIdent) \(.rolle) \(.token)"' "$TOKEN_FIL")
  [ "$ugyldige" -eq 0 ]
}

case "${1:-}" in
  --status)
    vis_status
    exit $?
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
echo "Kopier tokenet og lim det inn når du blir bedt om det, eller trykk bare Enter for å bruke"
echo "utklippstavla. Tokenet vises ikke på skjermen."
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
  les_token
  if [ -z "$token" ]; then
    fail "Fant ikke noe token. Prøv igjen."
    continue
  fi

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
  # Tokenet går inn på stdin, ikke som argument, så det ikke synes i prosesslista.
  printf '%s' "$token" | jq -R --arg ident "$ident" --arg rolle "$rolle" --slurpfile fil "$TOKEN_FIL" \
    '. as $token | $fil[0] | map(select(.navIdent != $ident)) + [{navIdent: $ident, rolle: $rolle, token: $token}]' \
    > "$tmp"
  mv "$tmp" "$TOKEN_FIL"
  unset token
  ok "Lagret token for $ident ($rolle)"
done

echo ""
vis_status
