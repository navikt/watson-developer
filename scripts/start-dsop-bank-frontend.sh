#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../repos/dsop-kontroll-bank-frontend"

export DSOP_LOCAL_MODE=true
export NODE_ENV=development
export NEXT_TELEMETRY_DISABLED=1
export BACKEND_URL=http://127.0.0.1:8100
export DSOP_LOCAL_TOKEN_URL=http://127.0.0.1:8090/dsop-tokenx/token
export NEXT_PUBLIC_TELEMETRY_URL=''
while IFS= read -r variable; do
  unset "$variable"
done < <(compgen -e | grep '^OTEL_' || true)

exec node node_modules/next/dist/bin/next dev --hostname 127.0.0.1
