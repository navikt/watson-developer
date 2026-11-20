#!/usr/bin/env bash
# Setter opp grunnverktøy og starter valgt agent fra watson-developer.
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC}  $1"; }
skip() { echo -e "  ${YELLOW}⟳${NC}  $1"; }
fail() { echo -e "  ${RED}✗${NC}  $1" >&2; exit 1; }
info() { echo -e "  ${BOLD}ℹ${NC}  $1"; }

if [[ -n "${__CPLT_WRAPPED:-}" ]]; then
    fail "Kjør bootstrap.sh i en vanlig terminal, ikke inne i cplt-sandboxen."
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
    fail "Dette skriptet støtter kun macOS."
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

case "$(uname -m)" in
    arm64) BREW_PREFIX="/opt/homebrew" ;;
    *) BREW_PREFIX="/usr/local" ;;
esac

START_AGENT=true
AGENT_ARG=""
AGENT_FLAG_SET=false
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --no-start) START_AGENT=false ;;
        --agent)
            [[ "$#" -ge 2 ]] || fail "Mangler verdi etter --agent. Gyldige verdier: opencode, copilot, pi."
            AGENT_ARG="$2"
            AGENT_FLAG_SET=true
            shift
            ;;
        *) fail "Ukjent argument: $1. Bruk --agent <navn> eller --no-start." ;;
    esac
    shift
done

resolve_agent() {
    local agent_file
    agent_file="$HOME/.config/watson-developer/agent"
    if [[ "$AGENT_FLAG_SET" == true ]]; then
        AGENT="$AGENT_ARG"
        AGENT_SOURCE="flag"
    elif [[ -n "${WATSON_AGENT:-}" ]]; then
        AGENT="$WATSON_AGENT"
        AGENT_SOURCE="env"
    elif [[ -f "$agent_file" ]]; then
        IFS= read -r AGENT < "$agent_file" || AGENT=""
        AGENT_SOURCE="file"
    else
        AGENT="opencode"
        AGENT_SOURCE="default"
    fi

    case "$AGENT" in
        opencode|copilot|pi) ;;
        *) fail "Ugyldig agent '$AGENT'. Gyldige verdier: opencode, copilot, pi." ;;
    esac
}

resolve_agent
if [[ "$AGENT_SOURCE" == "default" && -t 0 ]]; then
    read -r -p "Hvilken agent vil du bruke? [1] opencode (standard) [2] copilot [3] pi: " AGENT_CHOICE
    case "$AGENT_CHOICE" in
        ""|1|opencode) AGENT="opencode" ;;
        2|copilot) AGENT="copilot" ;;
        3|pi) AGENT="pi" ;;
        *) fail "Ugyldig valg '$AGENT_CHOICE'. Gyldige verdier: opencode, copilot, pi." ;;
    esac
fi

AGENT_CONFIG_DIR="$HOME/.config/watson-developer"
mkdir -p "$AGENT_CONFIG_DIR"
printf '%s\n' "$AGENT" > "$AGENT_CONFIG_DIR/agent"

echo ""
echo -e "${BOLD}Watson Developer: oppsett av $AGENT${NC}"
echo "────────────────────────────────────────"

if xcode-select -p &>/dev/null; then
    skip "Xcode Command Line Tools er allerede installert"
else
    info "Ber macOS installere Xcode Command Line Tools. Fullfør dialogen som åpnes."
    xcode-select --install || true
    info "Venter på at installasjonen av Xcode Command Line Tools blir ferdig..."
    until xcode-select -p &>/dev/null; do sleep 5; done
    ok "Xcode Command Line Tools er installert"
fi

if command -v brew &>/dev/null; then
    BREW_BIN="$(command -v brew)"
    skip "Homebrew er allerede installert ($BREW_BIN)"
elif [[ -x "$BREW_PREFIX/bin/brew" ]]; then
    BREW_BIN="$BREW_PREFIX/bin/brew"
    skip "Homebrew er allerede installert ($BREW_BIN)"
else
    info "Installerer Homebrew. Installereren kan be om sudo-passordet ditt."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    BREW_BIN="$BREW_PREFIX/bin/brew"
    [[ -x "$BREW_BIN" ]] || fail "Homebrew-installasjonen ble ikke funnet på $BREW_BIN."
fi

SHELLENV_LINE="eval \"\$($BREW_BIN shellenv)\""
eval "$("$BREW_BIN" shellenv)"
ZPROFILE="$HOME/.zprofile"
touch "$ZPROFILE"
if grep -Fq "$SHELLENV_LINE" "$ZPROFILE"; then
    skip "Homebrew shellenv finnes allerede i $ZPROFILE"
else
    printf '\n%s\n' "$SHELLENV_LINE" >> "$ZPROFILE"
    ok "La Homebrew shellenv til i $ZPROFILE"
fi

MISSING_TOOLS=()
if ! command -v git &>/dev/null; then MISSING_TOOLS+=(git); fi
if ! command -v gh &>/dev/null; then MISSING_TOOLS+=(gh); fi
if [[ "${#MISSING_TOOLS[@]}" -gt 0 ]]; then
    info "Installerer manglende grunnverktøy med Homebrew: ${MISSING_TOOLS[*]}"
    brew install "${MISSING_TOOLS[@]}"
    ok "Grunnverktøy er installert"
else
    skip "git og gh er allerede installert"
fi

if gh auth status --active --hostname github.com &>/dev/null; then
    skip "GitHub CLI er allerede innlogget"
else
    info "Logg inn på GitHub i nettleseren som åpnes."
    gh auth login --hostname github.com --git-protocol https --web
fi
gh auth setup-git
ok "GitHub CLI er konfigurert for Git"

if command -v nav-pilot &>/dev/null; then
    skip "nav-pilot er allerede installert"
else
    info "Installerer nav-pilot med Homebrew."
    brew install navikt/tap/nav-pilot
    ok "nav-pilot er installert"
fi

resolve_opencode() {
    if command -v opencode &>/dev/null; then
        command -v opencode
    elif [[ -x "$HOME/.opencode/bin/opencode" ]]; then
        echo "$HOME/.opencode/bin/opencode"
    else
        return 1
    fi
}

get_opencode_major() {
    local version_output version major
    version_output="$("$OPENCODE_BIN" --version 2>/dev/null)" || return 1
    case "$version_output" in
        "opencode v"*) version="${version_output#opencode v}" ;;
        *) version="$version_output" ;;
    esac
    major="${version%%.*}"
    case "$major" in
        ''|*[!0-9]*) return 1 ;;
    esac
    printf '%s\n' "$major"
}

case "$AGENT" in
    opencode)
        OPENCODE_BIN="$(resolve_opencode || true)"
        if [[ -z "$OPENCODE_BIN" ]]; then
            info "Installerer opencode v2."
            curl -fsSL https://opencode.ai/v2/install | bash
            OPENCODE_BIN="$(resolve_opencode || true)"
            [[ -n "$OPENCODE_BIN" ]] || fail "Fant ikke opencode etter installasjonen. Åpne en ny terminal og kjør skriptet på nytt."
        else
            skip "Fant opencode: $OPENCODE_BIN"
            OPENCODE_MAJOR="$(get_opencode_major || true)"
            [[ -n "$OPENCODE_MAJOR" ]] || fail "Klarte ikke å lese opencode-versjonen fra $OPENCODE_BIN."
            if [[ "$OPENCODE_MAJOR" -lt 2 ]]; then
                info "Oppgraderer opencode til v2."
                "$OPENCODE_BIN" upgrade --major
            else
                skip "opencode v$OPENCODE_MAJOR eller nyere er allerede installert"
            fi
        fi
        OPENCODE_BIN="$(resolve_opencode || true)"
        [[ -n "$OPENCODE_BIN" ]] || fail "Fant ikke opencode etter installasjon eller oppgradering."
        OPENCODE_MAJOR="$(get_opencode_major || true)"
        [[ -n "$OPENCODE_MAJOR" ]] || fail "Klarte ikke å lese opencode-versjonen fra $OPENCODE_BIN."
        [[ "$OPENCODE_MAJOR" -ge 2 ]] || fail "Opencode v2 eller nyere er ikke installert. Kjør bootstrap-skriptet på nytt."
        AGENT_BIN="$OPENCODE_BIN"
        ok "opencode v$OPENCODE_MAJOR er klart ($AGENT_BIN)"
        ;;
    copilot)
        if command -v copilot &>/dev/null; then
            skip "copilot er allerede installert"
        else
            info "Installerer GitHub Copilot CLI."
            brew install copilot-cli
        fi
        AGENT_BIN="$(command -v copilot || true)"
        [[ -n "$AGENT_BIN" ]] || fail "Fant ikke copilot etter installasjonen. Kjør bootstrap-skriptet på nytt."
        ;;
    pi)
        if command -v pi &>/dev/null; then
            skip "pi er allerede installert"
        else
            if ! command -v node &>/dev/null; then
                info "Installerer Node.js for pi."
                brew install node
            fi
            command -v node &>/dev/null || fail "Node.js mangler. Kjør: brew install node"
            info "Installerer pi coding agent."
            npm install -g @earendil-works/pi-coding-agent
        fi
        AGENT_BIN="$(command -v pi || true)"
        [[ -n "$AGENT_BIN" ]] || fail "Fant ikke pi etter installasjonen. Kjør bootstrap-skriptet på nytt."
        ;;
esac

export PATH="$(dirname "$AGENT_BIN"):$PATH"

if ! ./scripts/setup-mcp.sh --missing-only --agent "$AGENT"; then
    echo -e "  ${YELLOW}⚠${NC}  Kunne ikke sette opp alle MCP-serverne for $AGENT. Kjør ./scripts/setup-mcp.sh i en vanlig terminal."
fi

echo ""
echo "┌────────────────────────────────────────────────────────────┐"
echo "│ Når $AGENT starter, skriv: Kjør skillen watson-setup         │"
echo "│ Nye terminaler får valgt agent på PATH.                      │"
echo "└────────────────────────────────────────────────────────────┘"
echo ""

if [[ "$START_AGENT" == true ]]; then
    exec nav-pilot --client "$AGENT"
fi

info "Hoppet over oppstart med --no-start."
