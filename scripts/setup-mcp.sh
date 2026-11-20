#!/usr/bin/env bash
# Setter opp MCP-servere fra mcp-servere.txt.
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC}  $1"; }
skip() { echo -e "  ${YELLOW}⟳${NC}  $1"; }
fail() { echo -e "  ${RED}✗${NC}  $1" >&2; exit 2; }
info() { echo -e "  ${YELLOW}⚙${NC}  $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVER_LIST="$ROOT_DIR/mcp-servere.txt"

MODE="enable"
NAV_PILOT_ARGS=()
AGENT_ARG=""
AGENT_FLAG_SET=false
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
        --agent)
            [[ "$#" -ge 2 ]] || fail "Mangler verdi etter --agent. Gyldige verdier: opencode, copilot, pi."
            AGENT_ARG="$2"
            AGENT_FLAG_SET=true
            shift
            ;;
        *) NAV_PILOT_ARGS+=("$1") ;;
    esac
    shift
done

resolve_agent() {
    local agent_file
    agent_file="$HOME/.config/watson-developer/agent"
    if [[ "$AGENT_FLAG_SET" == true ]]; then
        AGENT="$AGENT_ARG"
    elif [[ -n "${WATSON_AGENT:-}" ]]; then
        AGENT="$WATSON_AGENT"
    elif [[ -f "$agent_file" ]]; then
        IFS= read -r AGENT < "$agent_file" || AGENT=""
    else
        AGENT="opencode"
    fi

    case "$AGENT" in
        opencode|copilot|pi) ;;
        *) fail "Ugyldig agent '$AGENT'. Gyldige verdier: opencode, copilot, pi." ;;
    esac
}

resolve_agent
if [[ "$AGENT" == "pi" ]]; then
    skip "nav-pilot setter ikke opp MCP for pi, hopper over"
    exit 0
fi

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
    local config_dir is_cplt
    local config_files=()
    is_cplt="${__CPLT_WRAPPED:+1}"
    is_cplt="${is_cplt:-0}"
    if [[ "$AGENT" == "copilot" ]]; then
        config_files=("$HOME/.copilot/mcp-config.json")
    else
        config_dir="${WATSON_OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
        config_files=(
            "$config_dir/config.json"
            "$config_dir/opencode.json"
            "$config_dir/opencode.jsonc"
        )
    fi

    command -v python3 &>/dev/null || return 5
    python3 - "$is_cplt" "$AGENT" "${#names[@]}" "${names[@]}" "${config_files[@]}" <<'PY'
import errno
import json
import sys

is_cplt = sys.argv[1] == "1"
agent = sys.argv[2]
name_count = int(sys.argv[3])
names = sys.argv[4:4 + name_count]
config_paths = sys.argv[4 + name_count:]


def strip_jsonc_comments(text):
    output = []
    in_string = False
    escaped = False
    index = 0
    while index < len(text):
        char = text[index]
        if in_string:
            output.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
        elif char == '"':
            in_string = True
            output.append(char)
            index += 1
        elif text.startswith("//", index):
            while index < len(text) and text[index] not in "\r\n":
                output.append(" ")
                index += 1
        elif text.startswith("/*", index):
            output.extend("  ")
            index += 2
            while index < len(text) and not text.startswith("*/", index):
                output.append(text[index] if text[index] in "\r\n" else " ")
                index += 1
            if index >= len(text):
                raise ValueError("uavsluttet blokkommentar")
            output.extend("  ")
            index += 2
        else:
            output.append(char)
            index += 1
    return "".join(output)


def strip_trailing_commas(text):
    output = []
    in_string = False
    escaped = False
    index = 0
    while index < len(text):
        char = text[index]
        if in_string:
            output.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
        elif char == '"':
            in_string = True
            output.append(char)
            index += 1
        elif char == ",":
            lookahead = index + 1
            while lookahead < len(text) and text[lookahead].isspace():
                lookahead += 1
            output.append(" " if lookahead < len(text) and text[lookahead] in "]}" else char)
            index += 1
        else:
            output.append(char)
            index += 1
    return "".join(output)


configured = set()
loaded_any = False
for config_path in config_paths:
    try:
        with open(config_path, encoding="utf-8") as config_file:
            source = config_file.read()
    except FileNotFoundError:
        continue
    except PermissionError:
        sys.exit(3)
    except OSError as error:
        if error.errno in (errno.EACCES, errno.EPERM):
            sys.exit(3)
        print("Kunne ikke lese MCP-konfigurasjonen: " + str(error), file=sys.stderr)
        sys.exit(2)

    try:
        if agent == "opencode":
            source = strip_trailing_commas(strip_jsonc_comments(source))
        config = json.loads(source)
    except (ValueError, json.JSONDecodeError) as error:
        print("Kunne ikke lese MCP-konfigurasjonen: " + str(error), file=sys.stderr)
        sys.exit(2)

    loaded_any = True
    if agent == "copilot":
        servers = config.get("mcpServers", {}) if isinstance(config, dict) else {}
        if isinstance(servers, dict):
            configured.update(servers.keys())
    else:
        mcp = config.get("mcp", {}) if isinstance(config, dict) else {}
        if isinstance(mcp, dict):
            for name, value in mcp.items():
                if name == "servers":
                    if isinstance(value, dict):
                        configured.update(value.keys())
                else:
                    configured.add(name)

if agent == "copilot" and not loaded_any:
    if is_cplt:
        sys.exit(3)
    for name in names:
        print(name)
    sys.exit(0)

for name in names:
    if name not in configured:
        print(name)
PY
}

MISSING_TEXT=""
if [[ "$MODE" == "check" || "$MODE" == "missing-only" ]]; then
    if MISSING_TEXT="$(get_missing_names)"; then
        :
    else
        status=$?
        if [[ "$status" -eq 5 ]]; then
            fail "python3 mangler, og trengs for å lese MCP-konfigurasjonen."
        fi
        if [[ "$status" -eq 3 ]]; then
            if [[ -n "${__CPLT_WRAPPED:-}" ]]; then
                if [[ "$AGENT" == "copilot" ]]; then
                    skip "kan ikke lese Copilot-config i sandboxen"
                else
                    skip "kan ikke lese opencode-config i sandboxen"
                fi
                exit 0
            fi
            if [[ "$AGENT" == "copilot" ]]; then
                MISSING_TEXT="$(printf '%s\n' "${names[@]}")"
            else
                fail "Kunne ikke lese MCP-konfigurasjonen."
            fi
        fi
        [[ "$status" -eq 3 && "$AGENT" == "copilot" ]] || fail "Kunne ikke lese MCP-konfigurasjonen."
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
    if nav-pilot mcp enable "${names[@]}" "${NAV_PILOT_ARGS[@]}" --client "$AGENT"; then
        ok "MCP-servere er satt opp"
    else
        fail "nav-pilot kunne ikke sette opp MCP-serverne."
    fi
else
    if nav-pilot mcp enable "${names[@]}" --client "$AGENT"; then
        ok "MCP-servere er satt opp"
    else
        fail "nav-pilot kunne ikke sette opp MCP-serverne."
    fi
fi
