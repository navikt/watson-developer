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
# - node version manager (hvis detektert)
# - ~/.gradle/gradle.properties: watson-admin-api sitt gradlew leser denne for
#   GitHub Packages-credentials (gpr.user/gpr.key) allerede før build starter
# - detektert JDK (Homebrew eller jenv-styrt) — se detect_java_home over.
#   Gradle kan trenge å lese JDK-filer direkte (f.eks. under toolchain-oppdagelse),
#   så vi legger til stien uansett hvilken JDK som ble funnet.
#
# NB: ~/.kube/config gis bevisst IKKE lesetilgang her. Filen inneholder som
# regel et klientsertifikat/-nøkkel eller token med cluster-admin-tilgang til
# klusteret (kind lagrer ikke bare metadata der), og det er ikke ønskelig at
# sandbox-agenten skal ha slik tilgang som standard — selv om det lokale
# kind-klusteret ikke inneholder ekte hemmeligheter. Kjør kubectl/Tilt direkte
# i terminalen (utenfor sandboxen), eller legg til tilgangen selv i
# ~/.config/cplt/config.toml hvis du bevisst ønsker at agenten skal kunne
# bruke kubectl/Tilt.
READ_PATHS='["/Applications/Xcode.app", "'"$HOME"'/.gradle/gradle.properties"'
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
# arrays og kommentarer riktig), men selve skrivingen skjer som presise
# tekst-patcher av de konkrete standardverdiene — resten av filen (kommentarer,
# andre nøkler, nestede tabeller, ukjente seksjoner) skrives aldri om og
# forblir byte-for-byte uendret.
#
# - Ved oppretting: fylles read/write/ports/sandbox med alle stiene scriptet
#   har detektert (Xcode, gradle.properties, evt. node/JDK), og standardene
#   under `[allow]`, `[sandbox]`, `[proxy]`, `[gh_guard]` og `[git_guard]`
#   settes.
# - Ved oppdatering av en eksisterende config: kun det som er strengt
#   nødvendig legges til (standardverdiene under, watson-root i write og
#   port 5174 i ports). En eventuell gammel
#   foreldrekatalog-tilgang i write
#   fjernes samtidig (fra før repoer ble klonet til `repos/` under
#   prosjektroten), og en eventuell tidligere kubeconfig-lesetilgang (fra en
#   tidligere versjon av dette scriptet) fjernes siden den ikke lenger gis
#   automatisk — se begrunnelse ovenfor.
RTK_PATH="$HOME/Library/Application Support/rtk"
FRESH_WRITE_PATHS='["'"$WATSON_ROOT"'", "'"$RTK_PATH"'"]'
FRESH_CACHE_EXEC='["ms-playwright"]'
PORTS_JSON='[5174]'
REQUIRED_WRITE='["'"$WATSON_ROOT"'"]'
REQUIRED_PORTS='[5174]'
LEGACY_KUBECONFIG_PATH="$HOME/.kube/config"

# Finn en brukbar python3.11+ (kreves for tomllib, som brukes til å lese/
# skrive cplt-config trygt). Dette scriptet kjøres som steg 1 i oppsettet —
# før doctor.sh (steg 2), som ellers ville auto-installert Python — så vi
# bootstrapper Python selv her i stedet for å bare feile på en ren maskin.
resolve_python() {
    local candidate
    for candidate in python3 python3.13 python3.12 python3.11; do
        if command -v "$candidate" &>/dev/null \
            && "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' 2>/dev/null; then
            command -v "$candidate"
            return 0
        fi
    done
    return 1
}

PYTHON_BIN="$(resolve_python || true)"
if [[ -z "$PYTHON_BIN" ]]; then
    info "Fant ingen python3.11+ — installerer python@3.12 automatisk med Homebrew..."
    brew install python@3.12 &>/dev/null || true
    # python@3.12 er keg-only i Homebrew og legger ikke nødvendigvis en
    # uversjonert `python3` på PATH — let derfor eksplisitt etter formelens
    # egen binærkatalog og legg den til PATH før vi prøver på nytt.
    BREW_PY_PREFIX="$(brew --prefix python@3.12 2>/dev/null || true)"
    if [[ -n "$BREW_PY_PREFIX" && -d "$BREW_PY_PREFIX/libexec/bin" ]]; then
        export PATH="$BREW_PY_PREFIX/libexec/bin:$PATH"
    elif [[ -n "$BREW_PY_PREFIX" && -d "$BREW_PY_PREFIX/bin" ]]; then
        export PATH="$BREW_PY_PREFIX/bin:$PATH"
    fi
    PYTHON_BIN="$(resolve_python || true)"
fi
if [[ -z "$PYTHON_BIN" ]]; then
    fail "Fant ikke python3.11+ (kreves for tomllib, brukt til å lese/skrive cplt-config), og automatisk installasjon feilet. Kjør: brew install python@3.12, og sørg for at \$(brew --prefix python@3.12)/libexec/bin er på PATH"
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
 ports_raw, required_write_raw, required_ports_raw,
 legacy_kubeconfig_path) = sys.argv[1:9]

config_file = Path(config_file)
fresh_read = json.loads(fresh_read_raw)
fresh_write = json.loads(fresh_write_raw)
fresh_cache_exec = json.loads(fresh_cache_exec_raw)
ports = json.loads(ports_raw)
required_write = json.loads(required_write_raw)
required_ports = json.loads(required_ports_raw)

# Stier fra en eventuell tidligere versjon av dette scriptet som skal fjernes
# på migrering, siden de representerer bredere/utdatert tilgang enn det som
# nå kreves:
# - ~/.kube (hele katalogen) og selve kubeconfig-filen — en tidligere versjon
#   av dette scriptet ga lesetilgang til kubeconfig automatisk, men det er
#   ikke lenger tilfelle (se begrunnelse i setup-copilot.sh om cluster-admin-
#   credentials). Fjernes hvis funnet fra en tidligere kjøring.
# - foreldrekatalogen til watson-root — brukt av en eldre generasjon av dette
#   scriptet (før repoer ble klonet til `repos/` under prosjektroten), og gir
#   fortsatt skrivetilgang til alle søsken-kataloger hvis den blir stående.
LEGACY_READ_REMOVE = {str(Path.home() / ".kube"), legacy_kubeconfig_path}
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
        elif ch == "#":
            # TOML-kommentar: resten av linjen skal ignoreres (en `]` i en
            # kommentar inne i en multiline-array skal ikke telle som
            # array-slutt). Hopp til neste linjeskift.
            newline = text.find("\n", i, end)
            i = end if newline == -1 else newline
            continue
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


def upsert_scalar(text, section_name, key, value):
    """Set a scalar key inside a TOML table, creating it if missing."""
    span = find_toplevel_section_span(text, section_name)
    replacement = f"{key} = {json.dumps(value)}"
    if span is None:
        addition = f"\n[{section_name}]\n{replacement}\n"
        return text.rstrip("\n") + "\n" + addition

    body_start, body_end = span
    key_pattern = re.compile(
        rf"(?m)^[ \t]*{re.escape(key)}[ \t]*=[^\n]*$"
    )
    match = key_pattern.search(text, body_start, body_end)
    if match is None:
        insertion_point = body_end
        prefix = text[:insertion_point]
        if not prefix.endswith("\n"):
            replacement = "\n" + replacement
        return text[:insertion_point] + replacement + "\n" + text[insertion_point:]

    return text[:match.start()] + replacement + text[match.end():]


def upsert_value(text, section_name, key, value):
    if isinstance(value, list):
        span = find_toplevel_section_span(text, section_name)
        if span is None:
            addition = f"\n[{section_name}]\n{key} = {serialize_array(value)}\n"
            return text.rstrip("\n") + "\n" + addition

        body_start, body_end = span
        array_span = find_array_span(text, body_start, body_end, key)
        replacement = f"{key} = {serialize_array(value)}"
        if array_span is None:
            insertion_point = body_end
            prefix = text[:insertion_point]
            if not prefix.endswith("\n"):
                replacement = "\n" + replacement
            return text[:insertion_point] + replacement + "\n" + text[insertion_point:]

        key_start, array_end = array_span
        return text[:key_start] + replacement + text[array_end:]

    return upsert_scalar(text, section_name, key, value)


if not config_file.exists():
    lines = [
        "[allow]",
        f"read = {serialize_array(fresh_read)}",
        f"write = {serialize_array(fresh_write)}",
        f"ports = {serialize_array(ports)}",
        f"localhost = {serialize_array([5173, 5174, 8080, 8081])}",
        "",
        "[sandbox]",
        'agent = "copilot"',
        "validate = false",
        "yes = true",
        "allow_gpg_signing = true",
        "allow_env_files = true",
        "allow_localhost_any = true",
        'pass_env = ["BRUKERPROFIL"]',
        "quiet = true",
        "deny_clipboard = false",
        "allow_jvm_attach = true",
        "gradle_init = true",
        "allow_docker = true",
        f"allow_cache_exec = {serialize_array(fresh_cache_exec)}",
        "",
        "[proxy]",
        "enabled = false",
        "",
        "[gh_guard]",
        "enabled = false",
        "",
        "[git_guard]",
        "enabled = false",
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
existing_ports = list(allow.get("ports", []))
# Vi legger ikke lenger noe til i read automatisk (se begrunnelse ovenfor om
# kubeconfig/cluster-admin-credentials), men fjerner fortsatt eventuelle
# gamle, bredere read-tilganger fra tidligere versjoner av dette scriptet.
new_read = [p for p in existing_read if p not in LEGACY_READ_REMOVE]
new_write = [p for p in existing_write if p not in LEGACY_WRITE_REMOVE]
new_ports = list(existing_ports)

for value in required_write:
    if value not in new_write:
        new_write.append(value)
for value in required_ports:
    if value not in new_ports:
        new_ports.append(value)

desired_allow = {
    "localhost": [5173, 5174, 8080, 8081],
}
desired_sandbox = {
    "agent": "copilot",
    "validate": False,
    "allow_env_files": True,
    "allow_localhost_any": True,
    "pass_env": ["BRUKERPROFIL"],
    "allow_gpg_signing": True,
    "quiet": True,
    "yes": True,
    "deny_clipboard": False,
    "allow_jvm_attach": True,
    "gradle_init": True,
    "allow_docker": True,
    "allow_cache_exec": ["ms-playwright"],
}
desired_guards = {
    "gh_guard": {"enabled": False},
    "git_guard": {"enabled": False},
}
desired_proxy = {
    "enabled": False,
}

needs_update = (
    new_read != existing_read
    or new_write != existing_write
    or new_ports != existing_ports
    or any(allow.get(key) != value for key, value in desired_allow.items())
    or any(sandbox.get(key) != value for key, value in desired_sandbox.items())
    or any(data.get("proxy", {}).get(key) != value for key, value in desired_proxy.items())
    or any(
        data.get(section_name, {}).get(key) != value
        for section_name, values in desired_guards.items()
        for key, value in values.items()
    )
)

if not needs_update:
    print("ALREADY_OK")
    sys.exit(0)

updated_text = raw
if new_read != existing_read:
    updated_text = upsert_array(updated_text, "allow", "read", new_read)
if new_write != existing_write:
    updated_text = upsert_array(updated_text, "allow", "write", new_write)
if new_ports != existing_ports:
    updated_text = upsert_array(updated_text, "allow", "ports", new_ports)

for key, value in desired_allow.items():
    updated_text = upsert_value(updated_text, "allow", key, value)
for key, value in desired_sandbox.items():
    updated_text = upsert_value(updated_text, "sandbox", key, value)
for key, value in desired_proxy.items():
    updated_text = upsert_value(updated_text, "proxy", key, value)
for section_name, values in desired_guards.items():
    for key, value in values.items():
        updated_text = upsert_value(updated_text, section_name, key, value)

# Sikkerhetssjekk: den patchede teksten skal fortsatt være gyldig TOML med
# nøyaktig de verdiene vi tilsiktet, før vi skriver den til disk.
try:
    verify_data = tomllib.loads(updated_text)
except tomllib.TOMLDecodeError as exc:
    print(f"PATCH_VERIFICATION_FAILED {exc}")
    sys.exit(6)

verify_read = verify_data.get("allow", {}).get("read", [])
verify_write = verify_data.get("allow", {}).get("write", [])
verify_ports = verify_data.get("allow", {}).get("ports", [])
if verify_read != new_read or verify_write != new_write or verify_ports != new_ports:
    print("PATCH_VERIFICATION_FAILED unexpected allow contents after patch")
    sys.exit(6)
for key, value in desired_allow.items():
    if verify_data.get("allow", {}).get(key) != value:
        print(f"PATCH_VERIFICATION_FAILED unexpected allow.{key} after patch")
        sys.exit(6)
for key, value in desired_sandbox.items():
    if verify_data.get("sandbox", {}).get(key) != value:
        print(f"PATCH_VERIFICATION_FAILED unexpected sandbox.{key} after patch")
        sys.exit(6)
for key, value in desired_proxy.items():
    if verify_data.get("proxy", {}).get(key) != value:
        print(f"PATCH_VERIFICATION_FAILED unexpected proxy.{key} after patch")
        sys.exit(6)
for section_name, values in desired_guards.items():
    for key, value in values.items():
        if verify_data.get(section_name, {}).get(key) != value:
            print(f"PATCH_VERIFICATION_FAILED unexpected {section_name}.{key} after patch")
            sys.exit(6)

timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
backup_file = config_file.with_name(f"{config_file.name}.bak.{timestamp}")
backup_file.write_text(raw, encoding="utf-8")
config_file.write_text(updated_text, encoding="utf-8")
print(f"UPDATED {backup_file}")
PY

set +e
MERGE_RESULT="$("$PYTHON_BIN" "$MERGE_SCRIPT_FILE" \
    "$CONFIG_FILE" "$READ_PATHS" "$FRESH_WRITE_PATHS" "$FRESH_CACHE_EXEC" "$PORTS_JSON" \
    "$REQUIRED_WRITE" "$REQUIRED_PORTS" "$LEGACY_KUBECONFIG_PATH")"
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

# ─── MCP-servere ─────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}MCP-servere:${NC}"

MCP_CHANGED=false

ensure_mcp_server() {
    local name="$1"
    local url="$2"
    local transport="$3"
    local details

    if ! command -v copilot &>/dev/null; then
        info "Fant ikke 'copilot' — hopper over $name. Kjør setup-scriptet på nytt etter at Copilot CLI er installert."
        return
    fi

    if details="$(copilot mcp get "$name" 2>/dev/null)" \
        && grep -Fq "URL: $url" <<<"$details"; then
        skip "$name er allerede konfigurert"
        return
    fi

    if copilot mcp add --transport "$transport" "$name" "$url" >/dev/null; then
        MCP_CHANGED=true
        ok "Konfigurerte $name"
    else
        fail "Kunne ikke konfigurere MCP-serveren $name"
    fi
}

ensure_mcp_server "com.figma/figma-mcp" "https://mcp.figma.com/mcp" "http"
ensure_mcp_server "com.jetbrains/intellij" "http://127.0.0.1:64342/sse" "sse"

if [[ "$MCP_CHANGED" == true ]]; then
    info "Start Copilot CLI på nytt for at de nye MCP-serverne skal bli tilgjengelige."
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
