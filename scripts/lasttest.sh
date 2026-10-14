#!/usr/bin/env bash
set -euo pipefail

# Kjører en k6-lasttest mot watson-admin-api og lagrer oppsummeringen i loadtest/resultater/.
#
# Bruk:
#   ./scripts/lasttest.sh smoke
#   ./scripts/lasttest.sh watson-sak baseline|last|stress|utholdenhet
#   SOK_IDENT=Z123456 TESTPERSONER=<fnr>[,<fnr>] ./scripts/lasttest.sh sok-ratelimit
#
# Miljøvariabler som sendes videre til k6: BASE_URL, ENHET, TESTPERSONER, SOK_IDENT,
# TENKETID_MIN, TENKETID_MAKS. Sett K6_PROMETHEUS_RW_SERVER_URL for å sende metrikker til Prometheus.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOADTEST_DIR="$ROOT_DIR/loadtest"
TOKEN_FIL="$LOADTEST_DIR/.tokens/tokens.json"
RESULTAT_DIR="$LOADTEST_DIR/resultater"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⟳${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1" >&2; }

SCENARIO="${1:-}"
PROFIL="${2:-baseline}"
SKRIPT="$LOADTEST_DIR/scenarioer/$SCENARIO.js"

if [ -z "$SCENARIO" ] || [ ! -f "$SKRIPT" ]; then
  fail "Ukjent scenario: '${SCENARIO}'"
  echo "Tilgjengelige: $(cd "$LOADTEST_DIR/scenarioer" && ls -- *.js | sed 's/\.js$//' | tr '\n' ' ')"
  exit 1
fi

if ! command -v k6 >/dev/null; then
  fail "k6 mangler. Installer i en vanlig terminal: brew install k6"
  exit 1
fi

if [ ! -s "$TOKEN_FIL" ] || [ "$(jq length "$TOKEN_FIL")" -eq 0 ]; then
  fail "Ingen tokens. Kjør ./scripts/lasttest-tokens.sh først."
  exit 1
fi
if ! "$SCRIPT_DIR/lasttest-tokens.sh" --status; then
  fail "Minst ett token er utløpt eller ugyldig. Hent nye med ./scripts/lasttest-tokens.sh."
  exit 1
fi

if [ "$SCENARIO" = "sok-ratelimit" ]; then
  if [ -z "${SOK_IDENT:-}" ] || [ -z "${TESTPERSONER:-}" ]; then
    fail "sok-ratelimit krever både SOK_IDENT og TESTPERSONER."
    exit 1
  fi
elif [ -z "${TESTPERSONER:-}" ]; then
  warn "TESTPERSONER er ikke satt. Skriveflyten (opprett sak) hoppes over."
fi

mkdir -p "$RESULTAT_DIR"
TIDSSTEMPEL="$(date +%Y%m%d-%H%M%S)"
RESULTAT_FIL="$RESULTAT_DIR/$TIDSSTEMPEL-$SCENARIO-$PROFIL.json"

OUTPUT_ARGS=()
if [ -n "${K6_PROMETHEUS_RW_SERVER_URL:-}" ]; then
  OUTPUT_ARGS+=(-o experimental-prometheus-rw)
fi

echo ""
ok "Kjører $SCENARIO ($PROFIL) mot ${BASE_URL:-https://watson-admin-api.intern.dev.nav.no}"

set +e
k6 run \
  --summary-export "$RESULTAT_FIL" \
  --tag "testid=$TIDSSTEMPEL-$SCENARIO-$PROFIL" \
  -e TOKEN_FIL="$TOKEN_FIL" \
  -e PROFIL="$PROFIL" \
  ${OUTPUT_ARGS[@]+"${OUTPUT_ARGS[@]}"} \
  "$SKRIPT"
STATUS=$?
set -e

echo ""
if [ "$STATUS" -eq 0 ]; then
  ok "Alle terskler holdt. Oppsummering: $RESULTAT_FIL"
else
  fail "k6 avsluttet med kode $STATUS (terskler brutt eller feil). Oppsummering: $RESULTAT_FIL"
fi
exit "$STATUS"
