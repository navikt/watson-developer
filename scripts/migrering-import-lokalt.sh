#!/usr/bin/env bash
# Kjører importen av migreringskandidater lokalt mot syntetiske kildefiler.
#
# Skriptet lager testfiler i repos/watson-admin-api/build/import-lokal/, skriver import-variablene til
# .tilt/migrering-import.env og starter watson-admin-api på nytt i Tilt. Tiltfile leser fila og sletter den,
# så importen kjører bare ved neste oppstart. Resultatet står i loggen til watson-admin-api i Tilt.
#
# Bruk:
#   ./scripts/migrering-import-lokalt.sh          # dry-run, lagrer ingenting
#   ./scripts/migrering-import-lokalt.sh --ekte   # lagrer kandidater i den lokale databasen
#
# Variabler:
#   IDENTER        ansvarlige i testfilene (standard L999999,L900006,L900000,L900001)
#   ANTALL         rader per fil (standard 10, seks filer)
#   STANDARDIDENT  ansvarlig for rader uten ident (standard L999999)
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="$ROOT/repos/watson-admin-api"
KATALOG="$BACKEND/build/import-lokal"
FNR_FIL="$BACKEND/build/import-lokal-fnr.txt"
ENV_FIL="$ROOT/.tilt/migrering-import.env"

IDENTER="${IDENTER:-L999999,L900006,L900000,L900001}"
ANTALL="${ANTALL:-10}"
STANDARDIDENT="${STANDARDIDENT:-L999999}"

DRYRUN=true
case "${1:-}" in
  --ekte) DRYRUN=false ;;
  "") ;;
  *) echo -e "${RED}✗ Ukjent argument: $1 (bruk --ekte eller ingenting)${NC}" >&2; exit 1 ;;
esac

if [[ ! -d "$BACKEND" ]]; then
  echo -e "${RED}✗ Fant ikke $BACKEND. Kjør ./scripts/clone-repos.sh først.${NC}" >&2
  exit 1
fi

if [[ -x /usr/libexec/java_home ]]; then
  JAVA_HOME="$(/usr/libexec/java_home -v 21)"
  export JAVA_HOME
  export PATH="$JAVA_HOME/bin:$PATH"
fi

# Syntetiske fnr: 11 siffer som starter på 9. Den lokale tilgangsmaskin-mocken godtar alle unntatt 00000999999.
mkdir -p "$(dirname "$FNR_FIL")"
seq -f '9%010g' 1 20 > "$FNR_FIL"

echo "→ Lager testfiler i $KATALOG"
rm -rf "$KATALOG"
(cd "$BACKEND" && ./gradlew -q genererTestfiler \
  -PdollyFil="$FNR_FIL" -Put="$KATALOG" -Pident="$IDENTER" -Pantall="$ANTALL")
echo -e "${GREEN}✓ OK${NC} testfiler laget"

mkdir -p "$(dirname "$ENV_FIL")"
cat > "$ENV_FIL" <<EOF
MIGRERING_IMPORT_AKTIV=true
MIGRERING_IMPORT_DRYRUN=$DRYRUN
MIGRERING_IMPORT_KATALOG=$KATALOG
MIGRERING_IMPORT_KJORINGID=lokal-$(date +%Y%m%d%H%M%S)
MIGRERING_IMPORT_STANDARDIDENT=$STANDARDIDENT
EOF
echo -e "${GREEN}✓ OK${NC} skrev $ENV_FIL (dry-run=$DRYRUN)"

if command -v tilt >/dev/null && tilt trigger watson-admin-api >/dev/null 2>&1; then
  echo -e "${GREEN}✓ OK${NC} watson-admin-api starter på nytt. Følg «Importen starter» og «Sum:» i loggen i Tilt."
else
  echo -e "${YELLOW}⟳ Fikk ikke startet watson-admin-api på nytt. Kjør: tilt trigger watson-admin-api${NC}"
fi
