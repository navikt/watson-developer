#!/usr/bin/env bash
# Åpner en proxy mot Cloud SQL for en Nais-app, slik at du kan koble til fra IntelliJ/psql.
# Kjøres i en vanlig terminal utenfor cplt-sandboxen (trenger ~/.kube, gcloud og naisdevice).
#
# Bruk: ./scripts/db-proxy.sh [app] [miljø] [port] [begrunnelse]
#   Standard: watson-admin-api dev-gcp 5433 "Testdata UAT"
# Sett PREPARE=1 for å kjøre prepare (skrivetilgang) og grant (oppretter databasebrukeren din).
# Trengs første gang, eller for INSERT/UPDATE.
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

APP="${1:-watson-admin-api}"
ENVIRONMENT="${2:-dev-gcp}"
PORT="${3:-5433}"
REASON="${4:-Testdata UAT}"
TEAM="holmes"
DATABASE="watson-admin-db"

if ! command -v nais > /dev/null 2>&1; then
  echo -e "${RED}✗ nais-CLI mangler${NC} (brew install nais)"
  exit 1
fi

if ! kubectl config get-contexts -o name | grep -qx "$ENVIRONMENT"; then
  echo -e "${RED}✗ Fant ikke kubectl-kontekst '$ENVIRONMENT'${NC}"
  echo "  Tilgjengelige: $(kubectl config get-contexts -o name | tr '\n' ' ')"
  exit 1
fi

if [ "${PREPARE:-0}" = "1" ]; then
  echo -e "${YELLOW}⟳ Gir tilgang (prepare, --all-privileges)${NC}"
  nais postgres prepare -t "$TEAM" -e "$ENVIRONMENT" --all-privileges -r "$REASON" "$APP"
  echo -e "${YELLOW}⟳ Oppretter databasebruker (grant)${NC}"
  nais postgres grant -t "$TEAM" -e "$ENVIRONMENT" -r "$REASON" "$APP"
  echo -e "${GREEN}✓ Prepare og grant ferdig${NC}"
fi

cat <<INFO
${GREEN}✓ Starter proxy${NC} (Ctrl+C for å stoppe)

IntelliJ → Database → New → Data Source → PostgreSQL:
  Host:     localhost
  Port:     $PORT
  Database: $DATABASE
  User:     din @nav.no-adresse (små bokstaver)
  Password: tomt
INFO

exec nais postgres proxy -t "$TEAM" -e "$ENVIRONMENT" -r "$REASON" -p "$PORT" "$APP"
