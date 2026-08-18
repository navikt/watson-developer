#!/usr/bin/env bash
set -euo pipefail

# Snarvei til scripts/sync-repos.sh — sjekker ut standardbranch og henter nyeste i alle repoer.
# Bevisst unntak fra konvensjonen om at skript bor i scripts/: dette er kun en tynn
# wrapper som gir en kort kommando (./sync.sh) for en operasjon man kjører ofte.
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts/sync-repos.sh" "$@"
