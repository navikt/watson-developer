#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "${NAIS_CLUSTER_NAME:-}" ]]; then
  printf '✗ Statusskriptet kan bare brukes lokalt\n' >&2
  exit 1
fi
if [[ ! -r "$SCRIPT_DIR/../.local/dsop-db-port" ]]; then
  printf '✗ Ingen lokal databaseport. Start dsop-kontroll først.\n' >&2
  exit 1
fi
port="$(cat "$SCRIPT_DIR/../.local/dsop-db-port")"
if [[ ! "$port" =~ ^[0-9]{4,5}$ ]] || (( port < 1024 || port > 65535 )); then
  printf '✗ Ugyldig lokal databaseport. Start dsop-kontroll på nytt.\n' >&2
  exit 1
fi
# Always use the local, ephemeral DSOP database. Never accept a connection URL.
unset PGHOSTADDR PGSERVICE PGSERVICEFILE PGOPTIONS
export PGCONNECT_TIMEOUT=3
psql -X --no-password -h 127.0.0.1 -p "$port" -U postgres -d postgres \
  -v ON_ERROR_STOP=1 -c "SELECT id, status, archive_reference,
    'http://127.0.0.1:3000/samarbeidspartner/kontoopplysninger/skjema?skjemaid=' || id AS banklenke
    FROM altinnskjema ORDER BY tidspunkt_sendt DESC;"
