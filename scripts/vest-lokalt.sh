#!/usr/bin/env bash
# Tester Vest-migreringen (SAK-67-2) lokalt mot watson-admin-api på port 8080.
# 1. Lager testfiler (eller bruker dine egne fra FILER=<katalog>)
# 2. Henter leder-token fra mock-oauth2-server
# 3. Kjører tørrkjøring, deretter opprettelse, deretter opprettelse én gang til (skal være idempotent)
#
# Krever at Tilt kjører og at backend står på SAK-67-2/vest-opprett eller nyere.
# For politisaker uten NAVIDENT: start backend med MIGRERING_VEST_POLITI_IDENT=<ident>.
# Eksempel: ./scripts/vest-lokalt.sh
#           OPPRETT=false ./scripts/vest-lokalt.sh        (bare tørrkjøring)
#           FILER=~/mine-filer ./scripts/vest-lokalt.sh   (M_SV_RESTANSER_VEST2.txt og M_SV_VENTER_POL_DOM_VEST2.txt)
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

API="${API:-http://localhost:8080}"
AUTH="${AUTH:-http://localhost:8090}"
BRUKERPROFIL="${BRUKERPROFIL:-leder-vest}"
OPPRETT="${OPPRETT:-true}"
MAKS="${MAKS:-100}"
FILER="${FILER:-}"
# Syntetisk testperson som lokal nav-persondata-api kjenner, samme som seed-local-data.sh
FNR="${FNR:-01010050205}"
IDENT="${IDENT:-L999999}"

RESTANSER="M_SV_RESTANSER_VEST2.txt"
POLITI="M_SV_VENTER_POL_DOM_VEST2.txt"

if ! curl -sf "$API/actuator/health" >/dev/null 2>&1; then
  echo -e "${RED}✗ watson-admin-api svarer ikke på $API. Start med ./start${NC}" >&2
  exit 1
fi

if [[ -z "$FILER" ]]; then
  FILER="$(mktemp -d)"; trap 'rm -rf "$FILER"' EXIT
  cat > "$FILER/$RESTANSER" <<EOF
SVMOTTAT;KONTROLLPLAN;Ytelse;TYPEMISBRUK;ARSAKSV;Kategori;Misbrukstype;Kilde;NAVIDENT;ENHET;PID;FNR;SAKSBEHANDLER
12.3.2026 00.00.00;AAPINNT;AAP;;;arbeid;Hvit inntekt;;$IDENT;su685d;90001;$FNR;
28.5.2026 00.00.00;DPINNT;Dagpenger;;;arbeid;Hvit inntekt;;;su685d;90002;$FNR;
1.6.2026 00.00.00;DPINNT;Dagpenger;;;arbeid;Hvit inntekt;;;su685d;90003;123;
EOF
  cat > "$FILER/$POLITI" <<EOF
PID;FNR;PROSJEKTIDENT;SVMOTTATT;SVRES;SVDATO;SAK;POLITIDISTRIKT;STONADTYPE;STRBELOP;ARSAKSV;NAVIDENT;POLSAKNR;POLITIDISTRIKT2;ENHET
90011;$FNR;Vest-2;7.11.2019 00.00.00;Anmeldt;12.2.2020 00.00.00;Dagpenger;VEST PD;Dagpenger;250000,00;4.8 Listekontroll;$IDENT;15573230;Vest politidistrikt;su685d
90012;$FNR;Vest-2;25.11.2019 00.00.00;Anmeldt;2.3.2020 00.00.00;Dagpenger;?st PD;Dagpenger;;4.8 Listekontroll;;;?st politidistrikt;su685d
90013;$FNR;Vest-2;25.11.2019 00.00.00;Anmeldt;2.3.2020 00.00.00;AAP;VEST PD;AAP;85000;4.8 Listekontroll;;15175222;;su685d
EOF
  echo -e "${GREEN}✓ OK${NC} genererte testfiler"
fi

# login_hint velger profil i mock-oauth2-server, se k8s/watson-admin-api/mock-oauth2-server.yaml
TOKEN=$(curl -sf -X POST "$AUTH/azuread/token" \
  -d "grant_type=client_credentials" -d "client_id=watson-admin-api" -d "client_secret=mock-secret" \
  --data-urlencode "login_hint=$BRUKERPROFIL" |
  python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
echo -e "${GREEN}✓ OK${NC} token for $BRUKERPROFIL"

kall() { # $1 = fil-enum, $2 = filnavn, $3 = dryRun
  local svar
  svar=$(curl -s -X POST "$API/api/v1/migrering/vest/$1?dryRun=$3&maks=$MAKS" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: text/plain" --data-binary "@$FILER/$2")
  python3 -c "
import sys, json
try:
    d = json.loads(sys.argv[1])
except ValueError:
    print('  ✗ ugyldig svar: ' + sys.argv[1][:200]); sys.exit(1)
if 'opprettet' not in d:
    print('  ✗ ' + json.dumps(d, ensure_ascii=False)[:300]); sys.exit(1)
print('  rader={antallRaderIFil} opprettet={opprettet} alleredeOpprettet={alleredeOpprettet} gjenstaar={gjenstaar} tomtBelop={tomtBelop}'.format(**d))
for a in d['avvik']: print('  avvik linje {linjenummer}: {arsak}'.format(**a))
for a in d['feil']: print('  feil  linje {linjenummer}: {arsak}'.format(**a))
" "$svar"
}

for par in "SV_RESTANSER:$RESTANSER" "SV_VENTER_POL_DOM:$POLITI"; do
  fil="${par%%:*}"; navn="${par#*:}"
  echo "→ $fil (tørrkjøring)"
  kall "$fil" "$navn" true
  if [[ "$OPPRETT" == "true" ]]; then
    echo "→ $fil (oppretter)"
    kall "$fil" "$navn" false
    echo "→ $fil (på nytt, skal ikke opprette noe)"
    kall "$fil" "$navn" false
  else
    echo -e "${YELLOW}⟳ hopper over opprettelse (OPPRETT=false)${NC}"
  fi
done
