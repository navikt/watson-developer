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

ok()   { echo -e "  ${GREEN}✓${NC}  $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $1"; }
fail() { echo -e "  ${RED}✗${NC}  $1"; ERRORS=$((ERRORS + 1)); }

check_cmd() {
    local cmd="$1"
    local install_hint="$2"
    if command -v "$cmd" &>/dev/null; then
        ok "$cmd ($(command -v "$cmd"))"
    else
        fail "$cmd er ikke installert — $install_hint"
    fi
}

check_java_version() {
    if ! command -v java &>/dev/null; then
        fail "java er ikke installert — brew install --cask temurin@21"
        return
    fi
    local version_line version
    version_line=$(java -version 2>&1 | grep -v "^Picked up" | head -1)
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
        fail "node er ikke installert — brew install node"
        return
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

echo ""
echo -e "${BOLD}Lokal Kubernetes:${NC}"
check_cmd "kind"    "brew install kind   (https://kind.sigs.k8s.io)"
check_cmd "tilt"    "brew install tilt   (https://docs.tilt.dev/install.html)"
check_cmd "kubectl" "brew install kubectl"

echo ""
echo -e "${BOLD}GCP og Kubernetes-administrasjon:${NC}"
check_cmd "gcloud" "se https://cloud.google.com/sdk/docs/install"
if command -v k9s &>/dev/null; then
    ok "k9s (valgfritt — installert)"
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
else
    fail "pnpm er ikke installert — corepack enable  (krever Node)"
fi

echo ""
echo "────────────────────────────────────────"

if [ "$ERRORS" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}✅ Alt er på plass — kjør ./scripts/setup-kind.sh for å starte${NC}"
else
    echo -e "${RED}${BOLD}❌ $ERRORS verktøy mangler — installer dem og kjør doctor.sh på nytt${NC}"
    exit 1
fi
echo ""
