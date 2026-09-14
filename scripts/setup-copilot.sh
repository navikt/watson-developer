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
# - kubeconfig for kubectl/kind og Tilt. Det lokale kind-klusteret har ingen
#   hemmeligheter av verdi (kun testdata), så vi bruker standardplasseringen
#   ~/.kube/config i stedet for en egen prosjekt-lokal kopi — det unngår at
#   direkte `kubectl`/`tilt`-kommandoer (f.eks. README sitt
#   `BRUKERPROFIL=... tilt up ...`-eksempel) feiler fordi KUBECONFIG ikke er
#   satt i akkurat det skallet. Vi gir uansett kun lesetilgang til selve
#   config-filen, ikke hele ~/.kube-katalogen.
# - node version manager (hvis detektert)
# - ~/.gradle/gradle.properties: watson-admin-api sitt gradlew leser denne for
#   GitHub Packages-credentials (gpr.user/gpr.key) allerede før build starter
# - detektert JDK (Homebrew eller jenv-styrt) — se detect_java_home over.
#   Gradle kan trenge å lese JDK-filer direkte (f.eks. under toolchain-oppdagelse),
#   så vi legger til stien uansett hvilken JDK som ble funnet.
KUBECONFIG_PATH="$HOME/.kube/config"
READ_PATHS='["/Applications/Xcode.app", "'"$HOME"'/.gradle/gradle.properties", "'"$KUBECONFIG_PATH"'"'
if [[ -n "$NODE_PATH" ]]; then
    READ_PATHS="$READ_PATHS, \"$NODE_PATH\""
fi
if [[ -n "$JAVA_HOME_PATH" ]]; then
    READ_PATHS="$READ_PATHS, \"$JAVA_HOME_PATH\""
fi
READ_PATHS="$READ_PATHS]"

# Config genereres/oppdateres av et Python-hjelpescript i stedet for shell
# heredocs. tomllib (krever Python 3.11+) brukes til å *lese* og verifisere
# eksisterende config robust (håndterer enkelt-/dobbeltfnutter, multiline-
# arrays og kommentarer riktig), men selve skrivingen skjer som en presis
# tekst-patch av kun de konkrete `read`/`write`/`allow_cache_exec`-arrayene —
# resten av filen (kommentarer, andre nøkler, nestede tabeller, ukjente
# seksjoner) skrives aldri om og forblir byte-for-byte uendret.
#
# - Ved oppretting: fylles read/write/ports/sandbox med alle stiene scriptet
#   har detektert (Xcode, gradle.properties, kubeconfig, evt. node/JDK).
# - Ved oppdatering av en eksisterende config: kun det som er strengt
#   nødvendig legges til (kubeconfig i read, watson-root i write, "gradle" i
#   allow_cache_exec). En eventuell gammel foreldrekatalog-tilgang i write
#   fjernes samtidig (fra før repoer ble klonet til `repos/` under
#   prosjektroten).
RTK_PATH="$HOME/Library/Application Support/rtk"
FRESH_WRITE_PATHS='["'"$WATSON_ROOT"'", "'"$RTK_PATH"'"]'
FRESH_CACHE_EXEC='["ms-playwright", "gradle"]'
PORTS_JSON='[5174]'
REQUIRED_READ='["'"$KUBECONFIG_PATH"'"]'
REQUIRED_WRITE='["'"$WATSON_ROOT"'"]'
REQUIRED_CACHE_EXEC='["gradle"]'

if ! command -v python3 &>/dev/null; then
    fail "python3 er ikke installert — nødvendig for å generere/oppdatere cplt-config (brew install python@3.12)"
fi
if ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' 2>/dev/null; then
    PY_VERSION="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "ukjent")"
    fail "python3 $PY_VERSION er for gammel — trenger 3.11+ for tomllib (brukes til å lese/skrive cplt-config). Kjør: brew install python@3.12"
fi

mkdir -p "$CONFIG_DIR"
MERGE_SCRIPT_FILE="$(mktemp -t watson-cplt-config-merge.XXXXXX.py)"
trap 'rm -f "$MERGE_SCRIPT_FILE"' EXIT

cat > "$MERGE_SCRIPT_FILE" <<'PY'
import datetime
import json
import re
import sys
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:
    print("NO_TOMLLIB")
    sys.exit(3)

(config_file, fresh_read_raw, fresh_write_raw, fresh_cache_exec_raw,
 ports_raw, required_read_raw, required_write_raw,
 required_cache_exec_raw) = sys.argv[1:9]

config_file = Path(config_file)
fresh_read = json.loads(fresh_read_raw)
fresh_write = json.loads(fresh_write_raw)
fresh_cache_exec = json.loads(fresh_cache_exec_raw)
ports = json.loads(ports_raw)
required_read = json.loads(required_read_raw)
required_write = json.loads(required_write_raw)
required_cache_exec = json.loads(required_cache_exec_raw)

# Stier fra en eventuell tidligere versjon av dette scriptet som skal fjernes
# på migrering, siden de representerer bredere tilgang enn det som nå kreves:
# - ~/.kube (hele katalogen) — erstattet av en avgrenset prosjekt-kubeconfig.
# - foreldrekatalogen til watson-root — brukt av en eldre generasjon av dette
#   scriptet (før repoer ble klonet til `repos/` under prosjektroten), og gir
#   fortsatt skrivetilgang til alle søsken-kataloger hvis den blir stående.
LEGACY_READ_REMOVE = {str(Path.home() / ".kube")}
watson_root = required_write[0] if required_write else None
LEGACY_WRITE_REMOVE = {str(Path(watson_root).parent)} if watson_root else set()


def serialize_string(value):
    return json.dumps(value)


def serialize_array(values):
    return "[" + ", ".join(serialize_string(v) for v in values) + "]"


def find_toplevel_section_span(text, section_name):
    """Find the (start, end) char span of a top-level `[section]` table's
    body, i.e. everything between its header line and the next line that
    starts a new table (`[...]`), or EOF. Returns None if not found."""
    header_pattern = re.compile(rf"(?m)^\[{re.escape(section_name)}\][ \t]*(#.*)?$")
    header_match = header_pattern.search(text)
    if not header_match:
        return None
    body_start = header_match.end()
    next_header = re.search(r"(?m)^\[", text[body_start:])
    body_end = body_start + next_header.start() if next_header else len(text)
    return body_start, body_end


def find_array_span(text, start, end, key):
    """Within text[start:end], find the char span of `key = [ ... ]`,
    respecting quoted strings so brackets inside path strings don't confuse
    the scan. Returns (key_start, array_end) or None if key not present as
    an array assignment."""
    key_pattern = re.compile(rf"(?m)^[ \t]*{re.escape(key)}[ \t]*=[ \t]*\[")
    match = key_pattern.search(text, start, end)
    if not match:
        return None
    depth = 0
    in_string = None
    i = match.end() - 1  # position of the opening '['
    while i < end:
        ch = text[i]
        if in_string:
            if ch == "\\" and in_string == '"':
                i += 2
                continue
            if ch == in_string:
                in_string = None
        elif ch in ("'", '"'):
            in_string = ch
        elif ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
            if depth == 0:
                return match.start(), i + 1
        i += 1
    return None


def upsert_array(text, section_name, key, values):
    """Return text with `key = [...]` set to `values` inside `[section_name]`.
    Only the targeted key's array span is replaced; everything else in the
    file (comments, other keys, nested tables, unrelated sections) is left
    byte-for-byte untouched. Creates the section/key if missing."""
    span = find_toplevel_section_span(text, section_name)
    if span is None:
        addition = f"\n[{section_name}]\n{key} = {serialize_array(values)}\n"
        return text.rstrip("\n") + "\n" + addition

    body_start, body_end = span
    array_span = find_array_span(text, body_start, body_end, key)
    replacement = f"{key} = {serialize_array(values)}"
    if array_span is None:
        insertion_point = body_end
        # Insert right before the section's trailing blank line(s)/next header.
        prefix = text[:insertion_point]
        if not prefix.endswith("\n"):
            replacement = "\n" + replacement
        return text[:insertion_point] + replacement + "\n" + text[insertion_point:]

    key_start, array_end = array_span
    return text[:key_start] + replacement + text[array_end:]


if not config_file.exists():
    lines = [
        "[allow]",
        f"read = {serialize_array(fresh_read)}",
        f"write = {serialize_array(fresh_write)}",
        f"ports = {serialize_array(ports)}",
        "",
        "[sandbox]",
        "allow_gpg_signing = true",
        "allow_env_files = true",
        "allow_localhost_any = true",
        f"allow_cache_exec = {serialize_array(fresh_cache_exec)}",
        "quiet = false",
        "",
    ]
    config_file.parent.mkdir(parents=True, exist_ok=True)
    config_file.write_text("\n".join(lines), encoding="utf-8")
    print("CREATED")
    sys.exit(0)

raw = config_file.read_text(encoding="utf-8")
try:
    data = tomllib.loads(raw)
except tomllib.TOMLDecodeError as exc:
    print(f"PARSE_ERROR {exc}")
    sys.exit(4)

allow = data.get("allow", {})
sandbox = data.get("sandbox", {})

existing_read = list(allow.get("read", []))
existing_write = list(allow.get("write", []))
existing_cache_exec = list(sandbox.get("allow_cache_exec", []))

new_read = [p for p in existing_read if p not in LEGACY_READ_REMOVE]
new_write = [p for p in existing_write if p not in LEGACY_WRITE_REMOVE]
new_cache_exec = list(existing_cache_exec)

for value in required_read:
    if value not in new_read:
        new_read.append(value)
for value in required_write:
    if value not in new_write:
        new_write.append(value)
for value in required_cache_exec:
    if value not in new_cache_exec:
        new_cache_exec.append(value)

needs_update = (
    new_read != existing_read
    or new_write != existing_write
    or new_cache_exec != existing_cache_exec
)

if not needs_update:
    print("ALREADY_OK")
    sys.exit(0)

updated_text = raw
if new_read != existing_read:
    updated_text = upsert_array(updated_text, "allow", "read", new_read)
if new_write != existing_write:
    updated_text = upsert_array(updated_text, "allow", "write", new_write)
if new_cache_exec != existing_cache_exec:
    updated_text = upsert_array(updated_text, "sandbox", "allow_cache_exec", new_cache_exec)

# Sikkerhetssjekk: den patchede teksten skal fortsatt være gyldig TOML med
# nøyaktig de verdiene vi tilsiktet, før vi skriver den til disk.
try:
    verify_data = tomllib.loads(updated_text)
except tomllib.TOMLDecodeError as exc:
    print(f"PATCH_VERIFICATION_FAILED {exc}")
    sys.exit(6)

verify_read = verify_data.get("allow", {}).get("read", [])
verify_write = verify_data.get("allow", {}).get("write", [])
verify_cache_exec = verify_data.get("sandbox", {}).get("allow_cache_exec", [])
if (verify_read != new_read or verify_write != new_write
        or verify_cache_exec != new_cache_exec):
    print("PATCH_VERIFICATION_FAILED unexpected array contents after patch")
    sys.exit(6)

timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
backup_file = config_file.with_name(f"{config_file.name}.bak.{timestamp}")
backup_file.write_text(raw, encoding="utf-8")
config_file.write_text(updated_text, encoding="utf-8")
print(f"UPDATED {backup_file}")
PY

set +e
MERGE_RESULT="$(python3 "$MERGE_SCRIPT_FILE" \
    "$CONFIG_FILE" "$READ_PATHS" "$FRESH_WRITE_PATHS" "$FRESH_CACHE_EXEC" "$PORTS_JSON" \
    "$REQUIRED_READ" "$REQUIRED_WRITE" "$REQUIRED_CACHE_EXEC")"
set -e
rm -f "$MERGE_SCRIPT_FILE"
trap - EXIT

CONFIG_CHANGED=false
case "$MERGE_RESULT" in
    CREATED)
        ok "Opprettet $CONFIG_FILE"
        CONFIG_CHANGED=true
        ;;
    UPDATED*)
        BACKUP_FILE="${MERGE_RESULT#UPDATED }"
        info "Tok backup av eksisterende config: $BACKUP_FILE"
        ok "Oppdaterte $CONFIG_FILE med nødvendige tilganger uten å overskrive øvrige innstillinger"
        CONFIG_CHANGED=true
        ;;
    ALREADY_OK)
        skip "Config finnes allerede med nødvendige tilganger: $CONFIG_FILE"
        ;;
    NO_TOMLLIB)
        fail "python3 mangler tomllib (krever Python 3.11+) — kan ikke sjekke/oppdatere $CONFIG_FILE trygt"
        ;;
    PARSE_ERROR*)
        fail "Kunne ikke lese $CONFIG_FILE som TOML: ${MERGE_RESULT#PARSE_ERROR }"
        ;;
    PATCH_VERIFICATION_FAILED*)
        fail "Automatisk oppdatering av $CONFIG_FILE besto ikke verifisering (${MERGE_RESULT#PATCH_VERIFICATION_FAILED }) — ingen endringer ble skrevet. Rediger filen manuelt."
        ;;
    *)
        fail "Uventet resultat fra cplt-config-oppdatering: $MERGE_RESULT"
        ;;
esac

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
