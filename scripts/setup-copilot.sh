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

# ─── Detekter JDK (for watson-admin-api / gradle) ────────────────────────────

detect_java_home() {
    # Foretrekk en Homebrew-installert JDK — disse ligger under /opt/homebrew/
    # og unngår cplt-sandboxens read-blokkering av ~/Library/Java/JavaVirtualMachines.
    local brew_jdk
    for formula in openjdk@21 openjdk; do
        if brew_jdk="$(brew --prefix "$formula" 2>/dev/null)" && [[ -d "$brew_jdk" ]]; then
            echo "$brew_jdk"
            return
        fi
    done

    # Fallback: jenv-styrt JDK. Disse ligger under ~/Library/Java/JavaVirtualMachines
    # og krever at stien legges til allow.read eksplisitt (håndteres under).
    if command -v jenv &>/dev/null; then
        local jenv_home
        if jenv_home="$(jenv prefix 2>/dev/null)" && [[ -d "$jenv_home" ]]; then
            # Følg symlink til den faktiske JDK-installasjonen
            echo "$(cd "$jenv_home" && pwd -P)"
            return
        fi
    fi

    return 1
}

echo ""
echo -e "${BOLD}Java/JDK (for watson-admin-api):${NC}"

JAVA_HOME_PATH=""
JDK_IS_JENV_MANAGED=false
if JAVA_HOME_PATH=$(detect_java_home); then
    if [[ "$JAVA_HOME_PATH" == "$HOME/Library/Java/JavaVirtualMachines/"* ]]; then
        JDK_IS_JENV_MANAGED=true
        ok "Detektert (jenv-styrt): $JAVA_HOME_PATH"
        info "Denne stien legges til allow.read — anbefaler ellers en Homebrew-JDK (brew install openjdk@21)"
    else
        ok "Detektert (Homebrew): $JAVA_HOME_PATH"
    fi
else
    skip "Fant ingen JDK automatisk — installer med: brew install openjdk@21"
fi

# ─── Generer cplt-config ─────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}cplt-konfigurasjon:${NC}"

CONFIG_DIR="$HOME/.config/cplt"
CONFIG_FILE="$CONFIG_DIR/config.toml"

# Resolve watson-developer sin rotkatalog (repos/ med alle sibling-repoer ligger under denne)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WATSON_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Bygg read-array
# - Xcode CLI tools (git, clang etc.)
# - prosjektets kubeconfig for kubectl/kind og Tilt
# - node version manager (hvis detektert)
# - ~/.gradle/gradle.properties: watson-admin-api sitt gradlew leser denne for
#   GitHub Packages-credentials (gpr.user/gpr.key) allerede før build starter
# - detektert JDK (Homebrew eller jenv-styrt) — se detect_java_home over.
#   Gradle kan trenge å lese JDK-filer direkte (f.eks. under toolchain-oppdagelse),
#   så vi legger til stien uansett hvilken JDK som ble funnet.
KUBECONFIG_PATH="$WATSON_ROOT/.kube/config"
READ_PATHS='["/Applications/Xcode.app", "'"$HOME"'/.gradle/gradle.properties", "'"$KUBECONFIG_PATH"'"'
if [[ -n "$NODE_PATH" ]]; then
    READ_PATHS="$READ_PATHS, \"$NODE_PATH\""
fi
if [[ -n "$JAVA_HOME_PATH" ]]; then
    READ_PATHS="$READ_PATHS, \"$JAVA_HOME_PATH\""
fi
READ_PATHS="$READ_PATHS]"

# Sjekk om en eksisterende config allerede har tilgangene denne versjonen av
# scriptet krever. Hvis ja, lar vi den være i fred — brukeren kan ha gjort
# egne tilpasninger.
CONFIG_NEEDS_UPDATE=true
if [[ -f "$CONFIG_FILE" ]]; then
    if grep -qF "$KUBECONFIG_PATH" "$CONFIG_FILE" &&
        grep -qF "write = " "$CONFIG_FILE" &&
        grep -qF "\"$WATSON_ROOT\"" "$CONFIG_FILE" &&
        grep -qE 'allow_cache_exec[^]]*"gradle"' "$CONFIG_FILE"; then
        CONFIG_NEEDS_UPDATE=false
    fi
fi

CONFIG_CHANGED=false

if [[ -f "$CONFIG_FILE" && "$CONFIG_NEEDS_UPDATE" == true ]]; then
    BACKUP_FILE="$CONFIG_FILE.bak.$(date +%Y%m%d-%H%M%S)"
    cp "$CONFIG_FILE" "$BACKUP_FILE"
    info "Tok backup av eksisterende config: $BACKUP_FILE"
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" <<EOF
[allow]
# Xcode CLI tools (git, clang etc.) + prosjektets kubeconfig + node version manager +
# gradle.properties (GitHub Packages-credentials for watson-admin-api) +
# detektert JDK
read = $READ_PATHS
# watson-developer (inkl. repos/ med alle klonede sibling-repoer) + rtk (token-optimalisert CLI-proxy)
write = ["$WATSON_ROOT", "$HOME/Library/Application Support/rtk"]
# Vite dev server (watson-sak-frontend)
ports = [5174]

[sandbox]
allow_gpg_signing = true
allow_env_files = true
allow_localhost_any = true
allow_cache_exec = ["ms-playwright", "gradle"]
quiet = false
EOF
    ok "Opprettet $CONFIG_FILE"
    CONFIG_CHANGED=true
elif [[ "$CONFIG_NEEDS_UPDATE" == true ]]; then
    python3 - "$CONFIG_FILE" "$KUBECONFIG_PATH" "$WATSON_ROOT" <<'PY'
import json
import re
import sys

config_file, kubeconfig_path, watson_root = sys.argv[1:]
text = open(config_file, encoding="utf-8").read()


def update_array(text, section_name, key, required, remove=()):
    section_pattern = re.compile(
        rf"(?ms)(^\[{re.escape(section_name)}\]\s*$.*?)(?=^\[|\Z)"
    )
    section_match = section_pattern.search(text)
    if not section_match:
        text += f"\n[{section_name}]\n{key} = [{json.dumps(required)}]\n"
        return text

    section = section_match.group(1)
    key_pattern = re.compile(rf"(?m)^{re.escape(key)}\s*=\s*\[(.*?)\]\s*$")
    key_match = key_pattern.search(section)
    if key_match:
        values = re.findall(r'"([^"]*)"', key_match.group(1))
        values = [value for value in values if value not in remove]
        for value in required:
            if value not in values:
                values.append(value)
        replacement = f"{key} = [{', '.join(json.dumps(value) for value in values)}]"
        section = section[:key_match.start()] + replacement + section[key_match.end():]
    else:
        section = section.rstrip() + f"\n{key} = [{', '.join(json.dumps(value) for value in required)}]\n"
    return text[:section_match.start(1)] + section + text[section_match.end(1):]


text = update_array(
    text,
    "allow",
    "read",
    [kubeconfig_path],
    remove=(f"{__import__('os').path.expanduser('~/.kube')}",),
)
text = update_array(text, "allow", "write", [watson_root])
text = update_array(text, "sandbox", "allow_cache_exec", ["gradle"])
open(config_file, "w", encoding="utf-8").write(text)
PY
    ok "Oppdaterte $CONFIG_FILE med nødvendige tilganger uten å overskrive øvrige innstillinger"
    CONFIG_CHANGED=true
else
    skip "Config finnes allerede med nødvendige tilganger: $CONFIG_FILE"
fi

# ─── Restart-sjekk ────────────────────────────────────────────────────────────
# cplt-sandboxen leser config ved oppstart av den sandboxede prosessen.
# Hvis vi nettopp endret configen mens en agent/økt allerede kjører inne i
# sandboxen (dvs. $__CPLT_WRAPPED er satt), vil den økten fortsette å bruke de
# gamle tilgangene — og kommandoer som tilt/kubectl/gradle vil da feile med
# "Operation not permitted" helt til økten restartes.
if [[ "$CONFIG_CHANGED" == true ]]; then
    echo ""
    if [[ -n "${__CPLT_WRAPPED:-}" ]]; then
        echo -e "${YELLOW}⚠${NC}  Denne økten kjører allerede inne i cplt-sandboxen med den forrige konfigurasjonen."
        echo "   De nye tilgangene trer først i kraft i en ny økt."
        echo "   Avslutt denne Copilot-økten og start den på nytt før du fortsetter,"
        echo "   ellers vil kommandoer som tilt/kubectl/gradle sannsynligvis feile."
    else
        info "Restart 'copilot' (eller åpne en ny terminal) for at de nye cplt-tilgangene skal tre i kraft."
    fi
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
