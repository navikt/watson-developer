#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../repos/dsop-kontroll-frontend"

export DSOP_LOCAL_MODE=true
export BACKEND_URL=http://127.0.0.1:8100
export DSOP_PDF_URL=http://127.0.0.1:9000
export DSOP_BRREG_URL=http://127.0.0.1:7165/brreg
export DSOP_LOCAL_TOKEN_URL=http://127.0.0.1:8090/dsop-azure/token

NODE_ENV=development npm run build:dev
exec node src/local-server.js
