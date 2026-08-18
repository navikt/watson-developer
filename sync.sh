#!/usr/bin/env bash
set -euo pipefail

# Snarvei til scripts/sync-repos.sh — sjekker ut main og henter nyeste i alle repoer.
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts/sync-repos.sh" "$@"
