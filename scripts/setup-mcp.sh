#!/usr/bin/env bash
# Setter opp MCP-servere fra mcp-servere.txt.
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC}  $1"; }
skip() { echo -e "  ${YELLOW}⟳${NC}  $1"; }
fail() { echo -e "  ${RED}✗${NC}  $1" >&2; exit 1; }
info() { echo -e "  ${YELLOW}⚙${NC}  $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVER_LIST="$ROOT_DIR/mcp-servere.txt"

MODE="enable"
NAV_PILOT_ARGS=()
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --missing-only)
            [[ "$MODE" == "enable" ]] || fail "Bruk enten --check eller --missing-only, ikke begge."
            MODE="missing-only"
            ;;
        --check)
            [[ "$MODE" == "enable" ]] || fail "Bruk enten --check eller --missing-only, ikke begge."
            MODE="check"
            ;;
        *) NAV_PILOT_ARGS+=("$1") ;;
    esac
    shift
done

if [[ ! -f "$SERVER_LIST" ]]; then
    fail "Fant ikke serverlisten: $SERVER_LIST"
fi

names=()
while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    name="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$name" ]] && continue
    names+=("$name")
done < "$SERVER_LIST"

[[ "${#names[@]}" -gt 0 ]] || fail "Ingen MCP-servere er oppført i $SERVER_LIST"

get_missing_names() {
    local config_file name
    local json_config="$HOME/.config/opencode/opencode.json"
    local jsonc_config="$HOME/.config/opencode/opencode.jsonc"

    if [[ -f "$json_config" ]]; then
        config_file="$json_config"
        command -v python3 &>/dev/null || return 2
        python3 - "$config_file" "${names[@]}" <<'PY'
import json
import sys

config_path = sys.argv[1]
names = sys.argv[2:]
try:
    with open(config_path, encoding="utf-8") as config_file:
        config = json.load(config_file)
except (OSError, ValueError) as error:
    print("Kunne ikke lese opencode-konfigurasjonen: " + str(error), file=sys.stderr)
    sys.exit(2)

mcp = config.get("mcp", {}) if isinstance(config, dict) else {}
if not isinstance(mcp, dict):
    mcp = {}
for name in names:
    if name not in mcp:
        print(name)
PY
    elif [[ -f "$jsonc_config" ]]; then
        config_file="$jsonc_config"
        for name in "${names[@]}"; do
            if ! grep -Fq "\"$name\"" "$config_file" 2>/dev/null; then
                printf '%s\n' "$name"
            fi
        done
    else
        for name in "${names[@]}"; do printf '%s\n' "$name"; done
    fi
}

MISSING_TEXT=""
if [[ "$MODE" == "check" || "$MODE" == "missing-only" ]]; then
    if MISSING_TEXT="$(get_missing_names)"; then
        :
    else
        status=$?
        if [[ "$status" -eq 2 ]]; then
            fail "python3 mangler, og trengs for å lese opencode-konfigurasjonen."
        fi
        fail "Kunne ikke lese opencode-konfigurasjonen."
    fi
fi

missing_names=()
if [[ -n "$MISSING_TEXT" ]]; then
    while IFS= read -r name; do
        [[ -n "$name" ]] && missing_names+=("$name")
    done <<< "$MISSING_TEXT"
fi

if [[ "$MODE" == "check" ]]; then
    if [[ -z "$MISSING_TEXT" ]]; then
        skip "Alle MCP-servere er satt opp" >&2
        exit 0
    fi
    printf '%s\n' "${missing_names[@]}"
    echo -e "  ${RED}✗${NC}  Mangler MCP-servere" >&2
    exit 1
fi

if [[ -n "${__CPLT_WRAPPED:-}" ]]; then
    fail "nav-pilot mcp enable kan ikke kjøres i cplt-sandboxen. Kjør ./scripts/setup-mcp.sh i en vanlig terminal."
fi

if ! command -v nav-pilot &>/dev/null; then
    fail "nav-pilot mangler. Installer med: brew install navikt/tap/nav-pilot"
fi

if [[ "$MODE" == "missing-only" ]]; then
    if [[ -z "$MISSING_TEXT" ]]; then
        skip "Alle MCP-servere er satt opp"
        exit 0
    fi
    names=("${missing_names[@]}")
fi

info "Setter opp MCP-servere: ${names[*]}"
if [[ "${#NAV_PILOT_ARGS[@]}" -gt 0 ]]; then
    nav-pilot mcp enable "${names[@]}" "${NAV_PILOT_ARGS[@]}"
else
    nav-pilot mcp enable "${names[@]}"
fi
ok "MCP-servere er satt opp"
