#!/usr/bin/env bash
# Setter opp cplt (sandbox) og nav-pilot for watson-utviklere.
# Idempotent — trygt å kjøre flere ganger.
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC}  $1"; }
skip() { echo -e "  ${YELLOW}⟳${NC}  $1"; }
fail() { echo -e "  ${RED}✗${NC}  $1"; exit 1; }
info() { echo -e "  ${BOLD}ℹ${NC}  $1"; }

# ─── Plattformsjekk ──────────────────────────────────────────────────────────

if [[ "$(uname -s)" != "Darwin" ]]; then
    fail "Dette scriptet støtter kun macOS"
fi

if ! command -v brew &>/dev/null; then
    fail "Homebrew er ikke installert — se https://brew.sh"
fi

echo ""
echo -e "${BOLD}🔒 Watson — oppsett av cplt og nav-pilot${NC}"
echo "────────────────────────────────────────"

# ─── Installer cplt ──────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}cplt (sandbox):${NC}"

if command -v cplt &>/dev/null; then
    skip "cplt er allerede installert ($(cplt --version 2>/dev/null || echo 'ukjent versjon'))"
else
    info "Installerer cplt..."
    brew install navikt/tap/cplt
    ok "cplt installert"
fi

# ─── Installer nav-pilot ─────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}nav-pilot:${NC}"

if command -v nav-pilot &>/dev/null; then
    skip "nav-pilot er allerede installert ($(nav-pilot --version 2>/dev/null || echo 'ukjent versjon'))"
else
    info "Installerer nav-pilot..."
    brew install navikt/tap/nav-pilot
    ok "nav-pilot installert"
fi

# ─── Detekter node version manager ──────────────────────────────────────────

detect_node_path() {
    # n (tj/n) — installerer til $N_PREFIX eller ~/n
    if [[ -d "${N_PREFIX:-$HOME/n}" ]]; then
        echo "${N_PREFIX:-$HOME/n}"
        return
    fi

    # fnm
    if [[ -d "$HOME/Library/Application Support/fnm" ]]; then
        echo "$HOME/Library/Application Support/fnm"
        return
    fi
    if [[ -d "$HOME/.local/share/fnm" ]]; then
        echo "$HOME/.local/share/fnm"
        return
    fi

    # nvm
    if [[ -d "${NVM_DIR:-$HOME/.nvm}" ]]; then
        echo "${NVM_DIR:-$HOME/.nvm}"
        return
    fi

    # volta
    if [[ -d "$HOME/.volta" ]]; then
        echo "$HOME/.volta"
        return
    fi

    # mise (kun node-installasjoner)
    if [[ -d "$HOME/.local/share/mise/installs/node" ]]; then
        echo "$HOME/.local/share/mise/installs/node"
        return
    fi

    return 1
}

echo ""
echo -e "${BOLD}Node version manager:${NC}"

NODE_PATH=""
if NODE_PATH=$(detect_node_path); then
    ok "Detektert: $NODE_PATH"
else
    echo ""
    info "Kunne ikke detektere node version manager automatisk."
    info "Vanlige stier: ~/n (n), ~/.nvm (nvm), ~/.volta (volta), ~/.local/share/fnm (fnm)"
    echo ""
    read -rp "  Sti til din node version manager (eller trykk Enter for å hoppe over): " NODE_PATH
    if [[ -z "$NODE_PATH" ]]; then
        echo -e "  ${YELLOW}⟳${NC}  Hopper over — du kan legge til read-path manuelt i ~/.config/cplt/config.toml"
    else
        # Ekspander ~ til $HOME
        NODE_PATH="${NODE_PATH/#\~/$HOME}"
        if [[ ! -d "$NODE_PATH" ]]; then
            fail "Katalogen finnes ikke: $NODE_PATH"
        fi
        ok "Bruker: $NODE_PATH"
    fi
fi

# ─── Generer cplt-config ─────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}cplt-konfigurasjon:${NC}"

CONFIG_DIR="$HOME/.config/cplt"
CONFIG_FILE="$CONFIG_DIR/config.toml"

# Resolve watson parent directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WATSON_PARENT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Bygg read-array
READ_PATHS='["/Applications/Xcode.app"'
if [[ -n "$NODE_PATH" ]]; then
    READ_PATHS="$READ_PATHS, \"$NODE_PATH\""
fi
READ_PATHS="$READ_PATHS]"

if [[ -f "$CONFIG_FILE" ]]; then
    skip "Config finnes allerede: $CONFIG_FILE"
    info "Slett filen og kjør scriptet på nytt for å regenerere"
else
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" <<EOF
[allow]
# Xcode CLI tools (git, clang etc.) + node version manager
read = $READ_PATHS
# Watson-porteføljens forelderkatalog (alle repoer) + rtk (token-optimalisert CLI-proxy)
write = ["$WATSON_PARENT", "$HOME/Library/Application Support/rtk"]
# Vite dev server (watson-sak-frontend)
ports = [5174]

[sandbox]
allow_gpg_signing = true
allow_env_files = true
allow_localhost_any = true
allow_cache_exec = ["ms-playwright"]
quiet = false
EOF
    ok "Opprettet $CONFIG_FILE"
fi

# ─── Shell-install ───────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}Shell-alias:${NC}"

if cplt --shell-install 2>&1 | grep -q "already"; then
    skip "Shell-alias var allerede konfigurert"
else
    ok "'copilot' kjører nå gjennom cplt-sandboxen"
fi

# ─── Oppsummering ────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────"
echo -e "${GREEN}${BOLD}✅ Ferdig!${NC}"
echo ""
echo "  Neste steg:"
echo "    1. Restart shell (eller: source ~/.zshrc)"
echo "    2. Kjør: cplt doctor"
echo "    3. Start Copilot med sandbox: copilot"
echo ""
