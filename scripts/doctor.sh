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

# Installerer en manglende avhengighet automatisk via Homebrew, hvis mulig.
# Brukes kun når kommandoen mangler helt — feil/gammel versjon av et verktøy
# som allerede er installert rører vi ikke ved (kan være styrt av jenv/nvm
# eller bevisst valgt av utvikleren).
brew_install() {
    local formula="$1"
    local cask="${2:-false}"
    if ! command -v brew &>/dev/null; then
        return 1
    fi
    info "Installerer $formula automatisk med Homebrew..."
    if [[ "$cask" == "true" ]]; then
        brew install --cask "$formula" &>/tmp/watson-doctor-brew.log
    else
        brew install "$formula" &>/tmp/watson-doctor-brew.log
    fi
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

echo ""
echo -e "${BOLD}🔍 Watson Developer — pre-flight sjekk${NC}"
echo "────────────────────────────────────────"

check_python_version() {
    if ! command -v python3 &>/dev/null; then
        if brew_install "python@3.12"; then
            # python@3.12 er keg-only i Homebrew og legger ikke nødvendigvis en
            # uversjonert `python3` på PATH — let derfor eksplisitt etter
            # formelens egen binærkatalog og legg den til PATH om nødvendig.
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
        ok "python3 $version (≥3.11 ✓, kreves for tomllib i setup-copilot.sh)"
    else
        fail "python3 $version er for gammel — krever 3.11+ (for tomllib). brew install python@3.12"
    fi
}

echo ""
echo -e "${BOLD}Lokal Kubernetes:${NC}"
check_cmd "kind"    "brew install kind   (https://kind.sigs.k8s.io)" "kind"
check_cmd "tilt"    "brew install tilt   (https://docs.tilt.dev/install.html)" "tilt-dev/tap/tilt"
check_cmd "kubectl" "brew install kubectl" "kubectl"

echo ""
echo -e "${BOLD}AI-verktøy (cplt-konfigurasjon):${NC}"
check_python_version

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
echo "────────────────────────────────────────"

if [ "$ERRORS" -eq 0 ]; then
    if [ "$INSTALLED" -gt 0 ]; then
        echo -e "${GREEN}${BOLD}✅ Alt er på plass ($INSTALLED verktøy auto-installert) — kjør ./scripts/setup-kind.sh for å starte${NC}"
    else
        echo -e "${GREEN}${BOLD}✅ Alt er på plass — kjør ./scripts/setup-kind.sh for å starte${NC}"
    fi
else
    echo -e "${RED}${BOLD}❌ $ERRORS verktøy mangler — installer dem og kjør doctor.sh på nytt${NC}"
    exit 1
fi
echo ""
