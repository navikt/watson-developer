#!/usr/bin/env bash
# Kjører importen av migreringskandidater lokalt, med en katalog i stedet for GCS-bucket.
#
# Kildefilene hentes fra, i denne rekkefølgen:
#   1. --katalog <sti>
#   2. migrering-importfiler/ i watson-developer, hvis den har filer. Legg egne testfiler her.
#   3. Syntetiske filer fra genererTestfiler i repos/watson-admin-api/build/import-lokal/.
#
# Skriptet skriver import-variablene til .tilt/migrering-import.env og starter watson-admin-api på nytt i Tilt.
# Tiltfile leser fila og sletter den, så importen kjører bare ved neste oppstart. Resultatet står i loggen til
# watson-admin-api i Tilt.
#
# Bruk:
#   ./scripts/migrering-import-lokalt.sh                     # dry-run, lagrer ingenting
#   ./scripts/migrering-import-lokalt.sh --ekte              # lagrer kandidater i den lokale databasen
#   ./scripts/migrering-import-lokalt.sh --katalog <sti>     # leser kildefilene fra <sti>
#
# Variabler (gjelder bare genererte filer, unntatt STANDARDIDENT):
#   IDENTER        ansvarlige i testfilene (standard L999999,L900006,L900000,L900001)
#   ANTALL         rader per fil (standard 10, seks filer)
#   STANDARDIDENT  ansvarlig for rader uten ident (standard L999999)
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="$ROOT/repos/watson-admin-api"
EGNE_FILER="$ROOT/migrering-importfiler"
GENERERT="$BACKEND/build/import-lokal"
FNR_FIL="$BACKEND/build/import-lokal-fnr.txt"
ENV_FIL="$ROOT/.tilt/migrering-import.env"

IDENTER="${IDENTER:-L999999,L900006,L900000,L900001}"
ANTALL="${ANTALL:-10}"
STANDARDIDENT="${STANDARDIDENT:-L999999}"

DRYRUN=true
KATALOG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ekte) DRYRUN=false; shift ;;
    --katalog)
      [[ -n "${2:-}" ]] || { echo -e "${RED}✗ --katalog trenger en sti${NC}" >&2; exit 1; }
      KATALOG="$2"; shift 2 ;;
    *) echo -e "${RED}✗ Ukjent argument: $1 (bruk --ekte og/eller --katalog <sti>)${NC}" >&2; exit 1 ;;
  esac
done

har_filer() {
  [[ -d "$1" ]] && [[ -n "$(find "$1" -maxdepth 1 -type f ! -name '.*' -print -quit)" ]]
}

if [[ ! -d "$BACKEND" ]]; then
  echo -e "${RED}✗ Fant ikke $BACKEND. Kjør ./scripts/clone-repos.sh først.${NC}" >&2
  exit 1
fi

mkdir -p "$EGNE_FILER"

if [[ -n "$KATALOG" ]]; then
  if ! har_filer "$KATALOG"; then
    echo -e "${RED}✗ Fant ingen filer i $KATALOG${NC}" >&2
    exit 1
  fi
  KATALOG="$(cd "$KATALOG" && pwd)"
  echo -e "${GREEN}✓ OK${NC} leser kildefilene fra $KATALOG"
elif har_filer "$EGNE_FILER"; then
  KATALOG="$EGNE_FILER"
  echo -e "${GREEN}✓ OK${NC} leser kildefilene fra $KATALOG"
else
  echo -e "${YELLOW}⟳ Ingen filer i $EGNE_FILER. Lager syntetiske testfiler i stedet.${NC}"
  KATALOG="$GENERERT"

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
fi

mkdir -p "$(dirname "$ENV_FIL")"
cat > "$ENV_FIL" <<EOF
MIGRERING_IMPORT_AKTIV=true
MIGRERING_IMPORT_DRYRUN=$DRYRUN
MIGRERING_IMPORT_KATALOG='$KATALOG'
MIGRERING_IMPORT_KJORINGID=lokal-$(date +%Y%m%d%H%M%S)
MIGRERING_IMPORT_STANDARDIDENT=$STANDARDIDENT
EOF
echo -e "${GREEN}✓ OK${NC} skrev $ENV_FIL (dry-run=$DRYRUN)"

if command -v tilt >/dev/null && tilt trigger watson-admin-api >/dev/null 2>&1; then
  echo -e "${GREEN}✓ OK${NC} watson-admin-api starter på nytt. Følg «Importen starter» og «Sum:» i loggen i Tilt."
else
  echo -e "${YELLOW}⟳ Fikk ikke startet watson-admin-api på nytt. Kjør: tilt trigger watson-admin-api${NC}"
fi
