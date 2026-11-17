#!/usr/bin/env bash
# Lagrer Aha!-nøkkelen i sesjonsmappen til Copilot og tester at den virker.
# Kjør i en vanlig terminal utenfor cplt-sandboxen. Nøkkelen vises aldri.
set -euo pipefail

GRONN=$'\033[0;32m'
GUL=$'\033[0;33m'
ROD=$'\033[0;31m'
NULL=$'\033[0m'

SESJON_ID="${COPILOT_SESJON_ID:-8d02ed3a-38c6-4051-9935-9eaca0f85916}"
MAPPE="$HOME/.copilot/session-state/$SESJON_ID/files"
FIL="$MAPPE/aha.env"
DOMENE="${AHA_DOMAIN:-nav1}"

if [[ ! -d "$MAPPE" ]]; then
  echo "${ROD}✗ Fant ikke $MAPPE. Sett COPILOT_SESJON_ID til gjeldende sesjon.${NULL}" >&2
  exit 1
fi

if [[ -s "$FIL" ]] && grep -q '^AHA_API_KEY=.' "$FIL"; then
  echo "${GUL}⟳ $FIL har allerede en nøkkel. Slett filen for å bytte.${NULL}"
else
  read -r -s -p "Aha API-nøkkel (vises ikke): " nokkel
  echo
  if [[ -z "$nokkel" ]]; then
    echo "${ROD}✗ Tom nøkkel${NULL}" >&2
    exit 1
  fi
  umask 077
  printf 'AHA_DOMAIN=%s\nAHA_API_KEY=%s\n' "$DOMENE" "$nokkel" > "$FIL"
  chmod 600 "$FIL"
  unset nokkel
  echo "${GRONN}✓ Lagret $FIL (rettigheter 600)${NULL}"
fi

set -a
# shellcheck disable=SC1090
source "$FIL"
set +a

status=$(curl -s -o /dev/null -w '%{http_code}' \
  -H "Authorization: Bearer ${AHA_API_KEY}" \
  "https://${AHA_DOMAIN}.aha.io/api/v1/me")

if [[ "$status" == "200" ]]; then
  echo "${GRONN}✓ Aha! godtok nøkkelen (HTTP 200)${NULL}"
else
  echo "${ROD}✗ Aha! svarte HTTP $status. Sjekk nøkkelen og domenet '$DOMENE'.${NULL}" >&2
  exit 1
fi

echo "Si fra i Copilot-sesjonen at filen er klar."
