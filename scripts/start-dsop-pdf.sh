#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../repos/dsop-kontroll-pdf-generator"

export DSOP_SERVER_HOST=127.0.0.1
export NODE_ENV=development

npm run build:dev
exec node development/main.js
