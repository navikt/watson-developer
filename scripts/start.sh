#!/usr/bin/env bash
# Starter det lokale Watson-utviklingsmiljøet via Tilt, etter å ha spurt hvilken
# BRUKERPROFIL du vil logge inn som i watson-sak-frontend.
set -euo pipefail

GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

if ! command -v tilt &>/dev/null; then
    echo "FEIL: tilt ikke funnet. Se README.md for installasjonsinstruksjoner."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Profil-id, navn og rolle — samme sett som k8s/watson-admin-api/mock-oauth2-server.yaml
# og watson-sak-frontend sin LOKALE_BRUKERPROFILER.
PROFILE_IDS=(
    "saksbehandler-analyse"
    "leder-analyse"
    "leder-øst"
    "leder-vest"
    "saksbehandler-øst-1"
    "saksbehandler-øst-2"
    "saksbehandler-vest-1"
    "saksbehandler-vest-2"
)
PROFILE_LABELS=(
    "Bjarte Byråkratsen — saksbehandler, Analyse (default)"
    "Stian Sjeferud — leder, Analyse"
    "Ove Overordnerud — leder, Øst"
    "Kari Kommandørsen — leder, Vest"
    "Ulrikke Utrederson — saksbehandler, Øst"
    "Trine Trygdesen — saksbehandler, Øst"
    "Kjell Kontrollsen — saksbehandler, Vest"
    "Gunnar Granskeren — saksbehandler, Vest"
)

echo -e "${BOLD}Hvem vil du logge inn som?${NC}"
echo

PS3=$'\n''Velg brukerprofil (tall): '
select label in "${PROFILE_LABELS[@]}"; do
    if [[ -n "${label:-}" ]]; then
        BRUKERPROFIL="${PROFILE_IDS[$((REPLY - 1))]}"
        break
    fi
    echo "Ugyldig valg, prøv igjen."
done

echo -e "${GREEN}✓${NC}  Starter Tilt som ${BOLD}${label}${NC} (BRUKERPROFIL=${BRUKERPROFIL})"
echo

export BRUKERPROFIL
exec tilt up
