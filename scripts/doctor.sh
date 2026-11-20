#!/usr/bin/env bash
# Pre-flight sjekk for watson-developer lokalmiljø.
# Verifiserer at alle nødvendige verktøy er installert og minsteversjonskrav er oppfylt.
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

ERRORS=0
INSTALLED=0

ok()   { echo -e "  ${GREEN}✓${NC}  $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $1"; }
fail() { echo -e "  ${RED}✗${NC}  $1"; ERRORS=$((ERRORS + 1)); }
info() { echo -e "  ${YELLOW}⚙${NC}  $1"; }

AGENT_ARG=""
AGENT_FLAG_SET=false
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --agent)
            if [[ "$#" -lt 2 ]]; then
                fail "Mangler verdi etter --agent. Gyldige verdier: opencode, copilot, pi."
                break
            fi
            AGENT_ARG="$2"
            AGENT_FLAG_SET=true
            shift
            ;;
        *)
            fail "Ukjent argument: $1. Bruk --agent <navn>."
            break
            ;;
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
        *)
            fail "Ugyldig agent '$AGENT'. Gyldige verdier: opencode, copilot, pi."
            AGENT="opencode"
            ;;
    esac
}

resolve_agent

# Installerer en manglende avhengighet automatisk via Homebrew, hvis mulig.
# Brukes kun når kommandoen mangler helt — feil/gammel versjon av et verktøy
# som allerede er installert rører vi ikke ved (kan være styrt av jenv/nvm
# eller bevisst valgt av utvikleren).
#
# Kjører IKKE inni cplt-sandboxen: den gir kun skrivetilgang til
# prosjektroten, mens Homebrew skriver til
# /opt/homebrew eller /usr/local. Et forsøk der ville bare feile med en
# forvirrende "Operation not permitted" — vi sjekker derfor $__CPLT_WRAPPED
# og hopper rett til å be brukeren installere manuelt i en vanlig terminal.
brew_install() {
    local formula="$1"
    local cask="${2:-false}"
    if [[ -n "${__CPLT_WRAPPED:-}" ]]; then
        return 2
    fi
    if ! command -v brew &>/dev/null; then
        return 1
    fi
    info "Installerer $formula automatisk med Homebrew..."
    local log_file status
    log_file="$(mktemp -t watson-doctor-brew.XXXXXX.log)"
    if [[ "$cask" == "true" ]]; then
        if brew install --cask "$formula" &>"$log_file"; then status=0; else status=$?; fi
    else
        if brew install "$formula" &>"$log_file"; then status=0; else status=$?; fi
    fi
    if [[ "$status" -ne 0 ]]; then
        echo -e "  ${RED}Siste linjer fra Homebrew:${NC}"
        tail -n 20 "$log_file"
    fi
    rm -f "$log_file"
    return $status
}

check_cmd() {
    local cmd="$1"
    local install_hint="$2"
    local formula="${3:-}"
    local cask="${4:-false}"
    if command -v "$cmd" &>/dev/null; then
        ok "$cmd ($(command -v "$cmd"))"
        return
    fi
    if [[ -n "$formula" ]] && brew_install "$formula" "$cask" && command -v "$cmd" &>/dev/null; then
        ok "$cmd ($(command -v "$cmd")) — auto-installert"
        INSTALLED=$((INSTALLED + 1))
        return
    fi
    fail "$cmd er ikke installert — $install_hint"
}

java_runnable() {
    command -v java &>/dev/null && java -version &>/dev/null
}

# Har maskinen en ekte JDK installert i det hele tatt (uavhengig av om PATH
# peker til en ødelagt jenv-shim)? macOS sin egen /usr/bin/java er kun en
# stub som ber om installasjon når ingen ekte JDK finnes — /usr/libexec/
# java_home er den pålitelige måten å sjekke dette på.
has_real_jdk() {
    /usr/libexec/java_home &>/dev/null
}

check_java_version() {
    if ! command -v java &>/dev/null || { ! has_real_jdk && [[ "$(command -v java)" == "/usr/bin/java" ]]; }; then
        # Ingen ekte JDK finnes — kun evt. macOS' egen java-stub, som ikke kan
        # kjøre. Prøv auto-installasjon i stedet for å anta java er
        # installert bare fordi kommandoen finnes på PATH.
        if brew_install "temurin@21" "true" && java_runnable; then
            ok "java auto-installert — verifiserer versjon"
            INSTALLED=$((INSTALLED + 1))
        else
            fail "java er ikke installert (fant kun macOS' java-stub) — brew install --cask temurin@21"
            return
        fi
    fi

    local java_output
    java_output=$(java -version 2>&1) || {
        # `java` finnes på PATH og en ekte JDK finnes et sted på maskinen, men
        # java-kommandoen klarer likevel ikke å kjøre — vanligvis en ødelagt
        # jenv-shim (peker på en avinstallert jenv-versjon) eller sandbox som
        # blokkerer lesing av libjli.dylib i JDK-installasjonen.
        if echo "$java_output" | grep -q "jenv"; then
            fail "java-kommandoen feiler — ødelagt jenv-shim. Kjør: jenv rehash --force"
        elif echo "$java_output" | grep -q "libjli.dylib\|Operation not permitted"; then
            fail "java-kommandoen feiler — kan ikke lese JDK-filer (sandbox/rettigheter). Se docs/SETUP.md#feilsøking-gradlew-feiler-i-cplt-sandboxen for tiltak"
        else
            fail "java-kommandoen feiler: $(echo "$java_output" | head -1)"
        fi
        return
    }

    local version_line version
    version_line=$(echo "$java_output" | grep -v "^Picked up" | head -1)
    # Extract major version — handles both "21.0.2" and legacy "1.8.0_321"
    version=$(echo "$version_line" | awk -F'"' '{print $2}' | cut -d. -f1)
    if [ "$version" = "1" ]; then
        version=$(echo "$version_line" | awk -F'"' '{print $2}' | cut -d. -f2)
    fi
    if [ "${version:-0}" -ge 21 ] 2>/dev/null; then
        ok "java $version (≥21 ✓)"
    else
        fail "java ${version:-ukjent} er for gammel — krever Java 21+. brew install --cask temurin@21"
    fi
}

check_node_lts() {
    if ! command -v node &>/dev/null; then
        if brew_install "node" && command -v node &>/dev/null; then
            ok "node auto-installert — verifiserer versjon"
            INSTALLED=$((INSTALLED + 1))
        else
            fail "node er ikke installert — brew install node"
            return
        fi
    fi
    local version
    version=$(node --version | grep -oE '[0-9]+' | head -1)
    if [ "$version" -ge 20 ] 2>/dev/null; then
        ok "node v$version (LTS ✓)"
    else
        warn "node v$version — anbefaler LTS (v20+). n lts for å oppgradere"
    fi
}

check_python_version() {
    if ! command -v python3 &>/dev/null; then
        if brew_install "python@3.12"; then
            # python@3.12 er keg-only i Homebrew og legger ikke nødvendigvis en
            # uversjonert `python3` på PATH. Let eksplisitt etter formelens binærkatalog.
            local brew_py_prefix
            brew_py_prefix="$(brew --prefix python@3.12 2>/dev/null || true)"
            if [[ -n "$brew_py_prefix" && -d "$brew_py_prefix/libexec/bin" ]]; then
                export PATH="$brew_py_prefix/libexec/bin:$PATH"
            elif [[ -n "$brew_py_prefix" && -d "$brew_py_prefix/bin" ]]; then
                export PATH="$brew_py_prefix/bin:$PATH"
            fi
        fi
        if command -v python3 &>/dev/null; then
            ok "python3 auto-installert — verifiserer versjon"
            INSTALLED=$((INSTALLED + 1))
        else
            fail "python3 er ikke installert (eller ikke på PATH etter installasjon) — brew install python@3.12, og sørg for at \$(brew --prefix python@3.12)/libexec/bin er på PATH"
            return
        fi
    fi
    local version
    version=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    if python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)'; then
        ok "python3 $version (≥3.11 ✓, kreves for tomllib i setup-harness.sh)"
    else
        fail "python3 $version er for gammel — krever 3.11+ (for tomllib). brew install python@3.12"
    fi
}

check_opencode() {
    local opencode_bin version_output version major
    if command -v opencode &>/dev/null; then
        opencode_bin="$(command -v opencode)"
    elif [[ -x "$HOME/.opencode/bin/opencode" ]]; then
        opencode_bin="$HOME/.opencode/bin/opencode"
    else
        fail "opencode v2 mangler. Kjør: ./scripts/bootstrap.sh --agent opencode"
        return
    fi

    if ! version_output="$("$opencode_bin" --version 2>/dev/null)"; then
        fail "Kunne ikke lese opencode-versjonen. Kjør: ./scripts/bootstrap.sh --agent opencode"
        return
    fi
    case "$version_output" in
        "opencode v"*) version="${version_output#opencode v}" ;;
        *) version="$version_output" ;;
    esac
    major="${version%%.*}"
    case "$major" in
        ''|*[!0-9]*)
            fail "Kunne ikke lese opencode-versjonen. Kjør: ./scripts/bootstrap.sh --agent opencode"
            return
            ;;
    esac

    if [[ "$major" -ge 2 ]]; then
        ok "opencode $version (v2 eller nyere)"
    else
        fail "opencode $version er for gammel. Kjør: ./scripts/bootstrap.sh --agent opencode"
    fi
}

check_agent() {
    case "$AGENT" in
        opencode) check_opencode ;;
        copilot)
            if command -v copilot &>/dev/null; then
                ok "copilot ($(command -v copilot))"
            else
                fail "copilot mangler. Kjør: ./scripts/bootstrap.sh --agent copilot"
            fi
            ;;
        pi)
            if command -v pi &>/dev/null; then
                ok "pi ($(command -v pi))"
            else
                fail "pi mangler. Kjør: ./scripts/bootstrap.sh --agent pi"
            fi
            ;;
    esac
}

echo ""
echo -e "${BOLD}🔍 Watson Developer — pre-flight sjekk${NC}"
echo "────────────────────────────────────────"
if [[ -n "${__CPLT_WRAPPED:-}" ]]; then
    warn "Kjører inni cplt-sandboxen — auto-installasjon av manglende verktøy er slått av her (Homebrew skriver utenfor sandboxens tillatte områder). Manglende verktøy må installeres i en vanlig terminal utenfor sandboxen."
fi

echo ""
echo -e "${BOLD}Grunnleggende:${NC}"
if [[ "$(uname -s)" == "Darwin" ]]; then
    ok "macOS"
else
    fail "Dette skriptet støtter kun macOS"
fi

if xcode-select -p &>/dev/null; then
    ok "Xcode Command Line Tools er installert"
else
    fail "Xcode Command Line Tools mangler. Kjør: xcode-select --install"
fi

if command -v brew &>/dev/null; then
    ok "Homebrew ($(command -v brew))"
elif [[ -x "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    warn "Homebrew er installert, men manglet på PATH. Legg til eval \"\$(/opt/homebrew/bin/brew shellenv)\" i ~/.zprofile"
elif [[ -x "/usr/local/bin/brew" ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
    warn "Homebrew er installert, men manglet på PATH. Legg til eval \"\$(/usr/local/bin/brew shellenv)\" i ~/.zprofile"
else
    fail "Homebrew mangler. Kjør: ./scripts/bootstrap.sh"
fi
check_cmd "git"  "brew install git" "git"
check_cmd "curl" "installer curl fra macOS, eller kjør: brew install curl" "curl"

echo ""
echo -e "${BOLD}GitHub:${NC}"
check_cmd "gh" "brew install gh" "gh"
if command -v gh &>/dev/null; then
    if gh auth status --active --hostname github.com &>/dev/null; then
        ok "gh er innlogget"
    else
        fail "gh er ikke innlogget: gh auth login"
    fi
fi

echo ""
echo -e "${BOLD}Docker:${NC}"
check_cmd "docker" "brew install --cask docker" "docker" "true"
if command -v docker &>/dev/null; then
    if docker info &>/dev/null; then
        ok "Docker kjører"
    else
        fail "Docker kjører ikke: start Docker Desktop"
    fi
fi

echo ""
echo -e "${BOLD}Lokal Kubernetes:${NC}"
check_cmd "kind"    "brew install kind   (https://kind.sigs.k8s.io)" "kind"
check_cmd "tilt"    "brew install tilt   (https://docs.tilt.dev/install.html)" "tilt-dev/tap/tilt"
check_cmd "kubectl" "brew install kubectl" "kubectl"

echo ""
echo -e "${BOLD}AI-verktøy:${NC}"
check_python_version
check_cmd "cplt" "brew install navikt/tap/cplt" "navikt/tap/cplt"
check_cmd "nav-pilot" "brew install navikt/tap/nav-pilot" "navikt/tap/nav-pilot"

echo ""
echo -e "${BOLD}Agent ($AGENT):${NC}"
check_agent

echo ""
echo -e "${BOLD}GCP og Kubernetes-administrasjon:${NC}"
check_cmd "gcloud" "se https://cloud.google.com/sdk/docs/install" "google-cloud-sdk" "true"
if command -v k9s &>/dev/null; then
    ok "k9s (valgfritt — installert)"
elif brew_install "k9s" && command -v k9s &>/dev/null; then
    ok "k9s (valgfritt) — auto-installert"
    INSTALLED=$((INSTALLED + 1))
else
    warn "k9s er ikke installert (valgfritt) — brew install k9s"
fi

echo ""
echo -e "${BOLD}Backend (Java/Kotlin):${NC}"
check_java_version

echo ""
echo -e "${BOLD}Frontend (Node/pnpm):${NC}"
check_node_lts
if command -v pnpm &>/dev/null; then
    ok "pnpm $(pnpm --version)"
elif command -v corepack &>/dev/null && corepack enable &>/dev/null && command -v pnpm &>/dev/null; then
    ok "pnpm $(pnpm --version) — auto-installert (corepack enable)"
    INSTALLED=$((INSTALLED + 1))
else
    fail "pnpm er ikke installert — corepack enable  (krever Node)"
fi

echo ""
echo -e "${BOLD}MCP-servere:${NC}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if mcp_missing="$("$SCRIPT_DIR/setup-mcp.sh" --check --agent "$AGENT" 2>/dev/null)"; then
    if [[ -n "$mcp_missing" ]]; then echo "$mcp_missing"; else ok "Alle MCP-servere i mcp-servere.txt er satt opp"; fi
else
    mcp_status=$?
    if [[ "$mcp_status" -eq 1 && -n "$mcp_missing" ]]; then
        while IFS= read -r mcp_name; do
            [[ -z "$mcp_name" ]] || warn "$mcp_name mangler. Kjør: ./scripts/setup-mcp.sh --agent $AGENT"
        done <<< "$mcp_missing"
    else
        fail "MCP-sjekken feilet. Kjør ./scripts/setup-mcp.sh --check --agent $AGENT for detaljer"
    fi
fi

echo ""
echo -e "${BOLD}fnr-guard (pre-commit mot fødselsnumre):${NC}"
if [[ -x "$SCRIPT_DIR/../node_modules/.bin/fnr-guard" ]]; then
    if ! "$SCRIPT_DIR/install-git-hooks.sh" --status; then
        ERRORS=$((ERRORS + 1))
    fi
else
    warn "fnr-guard er ikke installert ennå. Kjør ./scripts/install-git-hooks.sh (eller ./sync.sh) utenfor sandboxen"
fi

echo ""
echo "────────────────────────────────────────"

if [ "$ERRORS" -eq 0 ]; then
    if [ "$INSTALLED" -gt 0 ]; then
        echo -e "${GREEN}${BOLD}✅ Alt er på plass ($INSTALLED verktøy auto-installert)${NC}"
    else
        echo -e "${GREEN}${BOLD}✅ Alt er på plass${NC}"
    fi
else
    echo -e "${RED}${BOLD}❌ $ERRORS verktøy mangler — installer dem og kjør doctor.sh på nytt${NC}"
    exit 1
fi
echo ""
