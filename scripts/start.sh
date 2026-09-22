#!/usr/bin/env bash
# Starter det lokale Watson-utviklingsmiljøet via Tilt. Profil kan velges
# interaktivt eller med tall, rolle og/eller enhet som argumenter.
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

print_usage() {
    echo "Bruk: ./start [nummer|rolle|enhet]..."
    echo
    echo "Eksempler:"
    echo "  ./start 1"
    echo "  ./start leder"
    echo "  ./start øst leder"
    echo "  ./start saksbehandler vest"
}

select_profile_from_arguments() {
    local argument
    local role_filter=""
    local unit_filter=""
    local profile_index
    local profile_id
    local matches=()

    for argument in "$@"; do
        case "$argument" in
            [1-9]|[1-9][0-9])
                if [ "$#" -ne 1 ] || [ -n "$role_filter" ] || [ -n "$unit_filter" ]; then
                    echo "FEIL: Et profilnummer kan ikke kombineres med andre filtre." >&2
                    print_usage >&2
                    return 1
                fi
                profile_index=$((argument - 1))
                if [ "$profile_index" -ge "${#PROFILE_IDS[@]}" ]; then
                    echo "FEIL: Profilnummer $argument finnes ikke." >&2
                    return 1
                fi
                BRUKERPROFIL="${PROFILE_IDS[$profile_index]}"
                label="${PROFILE_LABELS[$profile_index]}"
                return 0
                ;;
            leder)
                role_filter="leder"
                ;;
            saksbehandler|utreder|vanlig)
                role_filter="saksbehandler"
                ;;
            analyse|øst|vest)
                unit_filter="$argument"
                ;;
            *)
                echo "FEIL: Ukjent profilfilter: $argument" >&2
                print_usage >&2
                return 1
                ;;
        esac
    done

    for profile_index in "${!PROFILE_IDS[@]}"; do
        profile_id="${PROFILE_IDS[$profile_index]}"
        if [ -n "$role_filter" ] && [[ "$profile_id" != "$role_filter"-* ]]; then
            continue
        fi
        if [ -n "$unit_filter" ] && [[ "$profile_id" != *-"$unit_filter"* ]]; then
            continue
        fi
        matches+=("$profile_index")
    done

    if [ "${#matches[@]}" -eq 0 ]; then
        echo "FEIL: Fant ingen profil som matcher filtrene." >&2
        return 1
    fi

    profile_index="${matches[0]}"
    BRUKERPROFIL="${PROFILE_IDS[$profile_index]}"
    label="${PROFILE_LABELS[$profile_index]}"
}

if [ "$#" -gt 0 ]; then
    select_profile_from_arguments "$@"
else
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
fi

if [[ -z "${BRUKERPROFIL:-}" ]]; then
    echo "Ingen brukerprofil valgt (avbrutt). Avslutter."
    exit 1
fi

echo -e "${GREEN}✓${NC}  Starter Tilt som ${BOLD}${label}${NC} (BRUKERPROFIL=${BRUKERPROFIL})"
echo

export BRUKERPROFIL
exec tilt up
