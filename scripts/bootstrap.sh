#!/usr/bin/env bash
# Bootstrap for en helt ny Mac. Kjøres fra en vanlig terminal.
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

case "$(uname -m)" in
    arm64) BREW_PREFIX="/opt/homebrew" ;;
    *) BREW_PREFIX="/usr/local" ;;
esac

echo ""
echo -e "${BOLD}Watson Developer: første oppsett på Mac${NC}"
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

SHELLENV_LINE="eval \"\$($BREW_PREFIX/bin/brew shellenv)\""
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

WATSON_DIR="${WATSON_DIR:-$HOME/code/nav/holmes/watson/watson-developer}"
if [[ -d "$WATSON_DIR" ]]; then
    skip "Katalogen finnes allerede, hopper over kloning: $WATSON_DIR"
else
    mkdir -p "$(dirname "$WATSON_DIR")"
    info "Kloner watson-developer til $WATSON_DIR"
    git clone https://github.com/navikt/watson-developer.git "$WATSON_DIR"
    ok "watson-developer er klonet"
fi

cd "$WATSON_DIR"
info "Sjekker og installerer resterende avhengigheter."
if ! ./scripts/doctor.sh; then
    fail "Doctor fant feil. Se meldingene over, rett problemene og kjør bootstrap-skriptet på nytt."
fi

info "Setter opp Copilot, cplt og nav-pilot."
./scripts/setup-copilot.sh

echo ""
echo "────────────────────────────────────────"
echo -e "${GREEN}${BOLD}✅ Første oppsett er ferdig${NC}"
echo ""
echo "Neste steg:"
echo "  1. Åpne Docker Desktop én gang og godta lisensen."
echo "  2. Åpne en ny terminal, eller kjør: source ~/.zprofile"
echo "  3. Gå til katalogen: cd \"$WATSON_DIR\""
echo "  4. Start copilot og be den kjøre skillen watson-setup."
echo ""
