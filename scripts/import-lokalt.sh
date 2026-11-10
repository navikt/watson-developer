#!/usr/bin/env bash
# Tester migreringsimporten lokalt mot fake-gcs-server (kind, port 4443).
# 1. Lager bucket og laster opp testfiler (genererte, eller dine egne fra FILER=<katalog>)
# 2. Kjører importjobben mot emulatoren og lokal postgres
# 3. Lister avviksfilene
#
# Krever at Tilt kjører (fake-gcs og postgres) og at watson-admin-api har migrert databasen minst én gang.
# IDENTER=L999999 gir alle rader med ident til Bjarte (saksbehandler-analyse). Se frontend: ./scripts/start-sak-frontend.sh
# Eksempel: DRY_RUN=false ./scripts/import-lokalt.sh
#           FILER=~/mine-filer DRY_RUN=true ./scripts/import-lokalt.sh
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API="$ROOT/repos/watson-admin-api"
EMULATOR="${STORAGE_EMULATOR_HOST:-http://localhost:4443}"
BUCKET="${BUCKET:-watson-migrering-lokal}"
DRY_RUN="${DRY_RUN:-true}"
FILER="${FILER:-}"
ANTALL="${ANTALL:-30}"
IDENTER="${IDENTER:-}"
STANDARDIDENT="${STANDARDIDENT:-T100001}"
ENHET_MAPPING="${ENHET_MAPPING:-su685d=D101803,he965h=B101057,vy687j=V122450,bu700k=S117055}"
# Syntetisk testperson (ikke reell PII, brukes kun lokalt)
FNR_FIL="${FNR_FIL:-}"
DB_URL="${DB_URL:-jdbc:postgresql://localhost:5432/watson_admin?currentSchema=watson_migrering_local}"

export JAVA_HOME="${JAVA_HOME:-$(/usr/libexec/java_home -v 21)}"
export PATH="$JAVA_HOME/bin:$PATH"

if ! curl -sf "$EMULATOR/storage/v1/b" >/dev/null; then
  echo -e "${RED}✗ Fant ikke fake-gcs på $EMULATOR. Start Tilt først.${NC}"; exit 1
fi
echo -e "${GREEN}✓ fake-gcs svarer${NC}"

if curl -sf "$EMULATOR/storage/v1/b/$BUCKET" >/dev/null; then
  echo -e "${YELLOW}⟳ Bucket $BUCKET finnes${NC}"
else
  curl -sf -X POST "$EMULATOR/storage/v1/b?project=lokal" -H 'Content-Type: application/json' \
    -d "{\"name\":\"$BUCKET\"}" >/dev/null
  echo -e "${GREEN}✓ Opprettet bucket $BUCKET${NC}"
fi

# Rydder forrige kjøring slik at filene er de du ser nå
for obj in $(curl -sf "$EMULATOR/storage/v1/b/$BUCKET/o" | python3 -c "import sys,json; [print(o['name'].replace('/','%2F')) for o in json.load(sys.stdin).get('items',[])]"); do
  curl -sf -X DELETE "$EMULATOR/storage/v1/b/$BUCKET/o/$obj" >/dev/null
done

if [[ -z "$FILER" ]]; then
  FILER="$API/build/import-testfiler"
  if [[ -z "$FNR_FIL" ]]; then
    FNR_FIL="$(mktemp)"; trap 'rm -f "$FNR_FIL"' EXIT
    echo "01010050205" > "$FNR_FIL"
  fi
  echo "→ Genererer testfiler i $FILER"
  rm -rf "$FILER"
  (cd "$API" && ./gradlew -q genererTestfiler -PdollyFil="$FNR_FIL" -Put="$FILER" -Pantall="$ANTALL" ${IDENTER:+-Pident="$IDENTER"})
fi

for f in "$FILER"/*; do
  [[ -f "$f" ]] || continue
  navn="$(basename "$f")"
  curl -sf -X POST "$EMULATOR/upload/storage/v1/b/$BUCKET/o?uploadType=media&name=$navn" \
    -H 'Content-Type: text/csv' --data-binary "@$f" >/dev/null
  echo -e "${GREEN}✓ Lastet opp $navn${NC}"
done

echo "→ Bygger jar"
(cd "$API" && ./gradlew -q bootJar)
JAR="$(ls "$API"/build/libs/*.jar | grep -v plain | head -1)"

echo "→ Kjører importjobb (DRY_RUN=$DRY_RUN)"
STORAGE_EMULATOR_HOST="$EMULATOR" IMPORT_BUCKET_NAME="$BUCKET" DRY_RUN="$DRY_RUN" \
  IMPORT_STANDARDIDENT="$STANDARDIDENT" IMPORT_ENHET_MAPPING="$ENHET_MAPPING" \
  IMPORT_DB_URL="$DB_URL" IMPORT_DB_USERNAME=postgres IMPORT_DB_PASSWORD=postgres \
  java -Dloader.main=no.nav.watson.admin.migrering.importjobb.ImportJobbMainKt \
  -cp "$JAR" org.springframework.boot.loader.launch.PropertiesLauncher

echo "→ Avviksfiler i bucketen:"
curl -sf "$EMULATOR/storage/v1/b/$BUCKET/o?prefix=avvik/" \
  | python3 -c "import sys,json; [print('  ', o['name']) for o in json.load(sys.stdin).get('items',[])] or print('  (ingen)')"
