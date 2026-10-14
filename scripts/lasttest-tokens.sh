#!/usr/bin/env bash
set -euo pipefail

# Henter og lagrer tokens for testidentene som brukes i lasttesten av watson-admin-api.
# Identene og rollene står i loadtest/testidenter.
# Skriptet ber bare om token for identer som mangler et gyldig token.
# Tokenene hentes manuelt fra azure-token-generator (innlogging som testident i nettleseren)
# og limes inn skjult. Tokenfila er git-ignorert og lesbar bare for eieren.
#
# Bruk:
#   ./scripts/lasttest-tokens.sh            # hent tokens som mangler eller snart utløper
#   ./scripts/lasttest-tokens.sh --alle     # hent nye tokens for alle identene
#   ./scripts/lasttest-tokens.sh --status   # vis identer og utløpstid, uten tokens.
#                                           # Avslutter med kode 1 hvis et token er utløpt eller ugyldig.
#
# Idempotent: identer med token som varer minst MIN_GYLDIG minutter (standard 30), hoppes over.
# Tokens for identer som ikke lenger står i identfila, slettes.
# Sjekker også testidentene mot testbrukerne for enheten Lasttest i watson-admin-api (application-dev.yml).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TOKEN_DIR="$ROOT_DIR/loadtest/.tokens"
TOKEN_FIL="$TOKEN_DIR/tokens.json"
IDENT_FIL="$ROOT_DIR/loadtest/testidenter"
MIN_GYLDIG="${MIN_GYLDIG:-30}"
LASTTEST_ENHET="lasttest"
# Klonen av watson-admin-api. I en git worktree ligger repos/ ved siden av hovedkopien.
GIT_FELLES="$(git -C "$ROOT_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
HOVEDKOPI="$ROOT_DIR"
[ -n "$GIT_FELLES" ] && HOVEDKOPI="$(dirname "$GIT_FELLES")"
ADMIN_API_DIR="${WATSON_ADMIN_API_DIR:-$HOVEDKOPI/repos/watson-admin-api}"
DEV_YML="src/main/resources/application-dev.yml"
AUD="${LASTTEST_AUD:-dev-gcp:holmes:watson-admin-api}"
GENERATOR_URL="https://azure-token-generator.intern.dev.nav.no/api/obo?aud=$AUD"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $1"; }
skip() { echo -e "${YELLOW}⟳${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1" >&2; }

command -v jq >/dev/null || { fail "jq mangler"; exit 1; }

umask 077
mkdir -p "$TOKEN_DIR"
[ -f "$TOKEN_FIL" ] || echo "[]" > "$TOKEN_FIL"
chmod 600 "$TOKEN_FIL"

STTY_FOR=""
gjenopprett_terminal() { if [ -n "$STTY_FOR" ]; then stty "$STTY_FOR" 2>/dev/null || true; fi; }
trap gjenopprett_terminal EXIT

# Leser tokenet uten ekko. macOS-terminalen godtar høyst 1024 tegn per linje i vanlig modus,
# og Azure-tokens er lengre. Vi slår derfor av linjebufferen mens tokenet leses.
# Tom linje henter tokenet fra utklippstavla (pbpaste).
les_token() {
  token=""
  printf "Token (lim inn og trykk Enter, Enter alene for utklippstavla, h for å hoppe over): "
  if [ -t 0 ]; then
    STTY_FOR="$(stty -g)"
    stty -icanon -echo
    IFS= read -r token || { echo ""; fail "Ingen input. Avbryter."; exit 1; }
    gjenopprett_terminal
    STTY_FOR=""
  else
    IFS= read -r token || { echo ""; fail "Ingen input. Avbryter."; exit 1; }
  fi
  echo ""
  if [ -z "$token" ] && command -v pbpaste >/dev/null; then
    token="$(pbpaste)"
  fi
  # Fjern mellomrom, linjeskift og et eventuelt «Bearer»-prefiks.
  token="$(printf '%s' "$token" | tr -d '[:space:]')"
  token="${token#Bearer}"
  # Godta også JSON-svar med access_token.
  if [ "${token:0:1}" = "{" ]; then
    token="$(printf '%s' "$token" | jq -r '.access_token // empty' 2>/dev/null || true)"
  fi
}

# Leser JWT-payload (base64url) uten å skrive tokenet noe sted.
jwt_payload() {
  local del
  del="$(cut -d. -f2 <<< "$1" | tr '_-' '/+')"
  while [ $(( ${#del} % 4 )) -ne 0 ]; do del="${del}="; done
  base64 -d <<< "$del" 2>/dev/null
}

# Returnerer 1 hvis minst ett token er utløpt eller ikke kan leses.
vis_status() {
  local naa ugyldige=0 ident rolle token exp min
  naa="$(date +%s)"
  if [ "$(jq length "$TOKEN_FIL")" -eq 0 ]; then
    skip "Ingen tokens lagret"
    return 0
  fi
  while read -r ident rolle token; do
    exp="$(jwt_payload "$token" | jq -r '.exp // 0' 2>/dev/null || true)"
    [[ "$exp" =~ ^[0-9]+$ ]] || exp=0
    min=$(( (exp - naa) / 60 ))
    if [ "$min" -gt 0 ]; then
      ok "$ident ($rolle): gyldig i $min min"
    else
      fail "$ident ($rolle): utløpt eller ugyldig"
      ugyldige=$((ugyldige + 1))
    fi
  done < <(jq -r '.[] | "\(.navIdent) \(.rolle) \(.token)"' "$TOKEN_FIL")
  [ "$ugyldige" -eq 0 ]
}

# Minutter til tokenet for identen utløper. 0 hvis det mangler eller er ugyldig.
minutter_igjen() {
  local token exp
  token="$(jq -r --arg ident "$1" '.[] | select(.navIdent == $ident) | .token' "$TOKEN_FIL")"
  [ -n "$token" ] || { echo 0; return; }
  exp="$(jwt_payload "$token" | jq -r '.exp // 0' 2>/dev/null || true)"
  [[ "$exp" =~ ^[0-9]+$ ]] || exp=0
  local min=$(( (exp - $(date +%s)) / 60 ))
  [ "$min" -gt 0 ] && echo "$min" || echo 0
}

# Leser identfila. Tomme linjer og alt etter # ignoreres. Skriver «ident rolle» per linje.
les_identer() {
  local linjenr=0 linje ident rolle rest feil=0
  while IFS= read -r linje || [ -n "$linje" ]; do
    linjenr=$((linjenr + 1))
    linje="${linje%%#*}"
    read -r ident rolle rest <<< "$linje" || true
    [ -z "${ident:-}" ] && continue
    if [ "$rolle" != "saksbehandler" ] && [ "$rolle" != "leder" ] || [ -n "$rest" ]; then
      fail "loadtest/testidenter linje $linjenr: forventet «navIdent saksbehandler|leder»" >&2
      feil=1
      continue
    fi
    echo "$ident $rolle"
  done < "$IDENT_FIL"
  return "$feil"
}

ALLE=false
case "${1:-}" in
  --status)
    vis_status
    exit $?
    ;;
  --alle) ALLE=true ;;
  "") ;;
  *)
    fail "Ukjent argument: $1"
    exit 1
    ;;
esac

if [ ! -f "$IDENT_FIL" ]; then
  fail "Fant ikke loadtest/testidenter"
  exit 1
fi

# Skriver navIdent for hver ekstra-saksbehandler med enhetId lasttest i application-dev.yml.
# Leser origin/main, som er det som deployes, og faller tilbake på fila i klonen.
lasttest_identer_i_backend() {
  local yml
  git -C "$ADMIN_API_DIR" fetch -q origin main 2>/dev/null || true
  yml="$(git -C "$ADMIN_API_DIR" show "origin/main:$DEV_YML" 2>/dev/null || cat "$ADMIN_API_DIR/$DEV_YML" 2>/dev/null)" || return 1
  [ -n "$yml" ] || return 1
  awk -v enhet="$LASTTEST_ENHET" -v q="'" '
    function avslutt() { if (ident != "" && lasttest) print ident; ident = ""; lasttest = 0 }
    /^[[:space:]]*#/ { next }
    /^[^[:space:]]/ { avslutt(); i_nom = ($0 ~ /^nom:/); next }
    !i_nom { next }
    /^[[:space:]]*-[[:space:]]/ { avslutt() }
    function verdi(v) { sub(/^[^:]*:/, "", v); gsub(/[[:space:]"]/, "", v); gsub(q, "", v); return v }
    /navident:/ { ident = verdi($0) }
    /enhetId:/ { lasttest = (verdi($0) == enhet) }
    END { avslutt() }
  ' <<< "$yml"
}

# Sammenligner saksbehandlerne i testidenter med testbrukerne for enheten Lasttest i watson-admin-api.
# Testbrukere som mangler i testidenter, kan legges til. Saksbehandlere som mangler i backend,
# gir advarsel, fordi sakene deres havner under en annen enhet.
synk_med_backend() {
  local backend ident rolle svar lagt_til=0
  if ! backend="$(lasttest_identer_i_backend)"; then
    skip "Fant ikke $DEV_YML i $ADMIN_API_DIR. Hopper over sjekken mot watson-admin-api."
    return 0
  fi

  for ident in $backend; do
    grep -q "^$ident " <<< "$IDENTER" && continue
    if [ ! -t 0 ]; then
      skip "$ident har enheten Lasttest i watson-admin-api, men står ikke i loadtest/testidenter"
      continue
    fi
    read -r -p "$ident har enheten Lasttest i watson-admin-api. Legg til som [s]aksbehandler, [l]eder eller [h]opp over? (s): " svar || svar="h"
    case "${svar:-s}" in
      s|S) rolle="saksbehandler" ;;
      l|L) rolle="leder" ;;
      *) skip "Hoppet over $ident"; continue ;;
    esac
    [ -s "$IDENT_FIL" ] && [ -n "$(tail -c1 "$IDENT_FIL")" ] && echo "" >> "$IDENT_FIL"
    echo "$ident $rolle" >> "$IDENT_FIL"
    ok "La til $ident ($rolle) i loadtest/testidenter"
    lagt_til=1
  done

  while read -r ident rolle; do
    [ "$rolle" = "saksbehandler" ] || continue
    if ! grep -qx "$ident" <<< "$backend"; then
      skip "$ident mangler enhetId: $LASTTEST_ENHET i watson-admin-api. Sakene den får tildelt, havner ikke under Lasttest."
    fi
  done <<< "$IDENTER"

  [ "$lagt_til" -eq 0 ] || IDENTER="$(les_identer)"
}

IDENTER="$(les_identer)" || exit 1
synk_med_backend
if [ -z "$IDENTER" ]; then
  fail "loadtest/testidenter har ingen identer"
  exit 1
fi
if [ "$(sort <<< "$(cut -d' ' -f1 <<< "$IDENTER")" | uniq -d)" != "" ]; then
  fail "loadtest/testidenter har samme navIdent flere ganger"
  exit 1
fi

# Fjern tokens for identer som ikke lenger står i fila, og oppdater rollen fra fila.
tmp="$(mktemp "$TOKEN_DIR/tokens.XXXXXX")"
jq -R -s 'split("\n") | map(select(length > 0) | split(" ") | {key: .[0], value: .[1]}) | from_entries' <<< "$IDENTER" \
  | jq --slurpfile fil "$TOKEN_FIL" '. as $roller | $fil[0] | map(select($roller[.navIdent]) | .rolle = $roller[.navIdent])' > "$tmp"
mv "$tmp" "$TOKEN_FIL"

TRENGER=()
while read -r ident rolle; do
  min="$(minutter_igjen "$ident")"
  if [ "$ALLE" = false ] && [ "$min" -ge "$MIN_GYLDIG" ]; then
    skip "$ident ($rolle): gyldig i $min min, hopper over"
  else
    TRENGER+=("$ident $rolle")
  fi
done <<< "$IDENTER"

if [ "${#TRENGER[@]}" -eq 0 ]; then
  echo ""
  ok "Alle tokens er gyldige i minst $MIN_GYLDIG min. Bruk --alle for å hente nye likevel."
  exit 0
fi

echo ""
echo "Trenger token for ${#TRENGER[@]} av $(wc -l <<< "$IDENTER" | tr -d ' ') identer. For hver ident:"
echo "  1. Logg inn som identen i et privat nettleservindu og åpne"
echo "     $GENERATOR_URL"
echo "  2. Kopier tokenet og trykk Enter her for å bruke utklippstavla, eller lim det inn."
echo "     Skriv h og trykk Enter for å hoppe over identen. Tokenet vises ikke på skjermen."

for linje in "${TRENGER[@]}"; do
  read -r ident rolle <<< "$linje"
  echo ""
  echo "── $ident ($rolle)"
  while true; do
    les_token
    if [ "$token" = "h" ]; then
      skip "Hoppet over $ident"
      break
    fi
    if [ -z "$token" ]; then
      fail "Fant ikke noe token. Prøv igjen, eller skriv h for å hoppe over."
      continue
    fi
    payload="$(jwt_payload "$token" || true)"
    if ! jq -e . >/dev/null 2>&1 <<< "$payload"; then
      fail "Kunne ikke lese tokenet. Prøv igjen, eller skriv h for å hoppe over."
      continue
    fi
    token_ident="$(jq -r '.NAVident // empty' <<< "$payload")"
    if [ -n "$token_ident" ] && [ "$token_ident" != "$ident" ]; then
      fail "Tokenet tilhører $token_ident, ikke $ident. Er du logget inn som riktig ident?"
      continue
    fi

    tmp="$(mktemp "$TOKEN_DIR/tokens.XXXXXX")"
    # Tokenet går inn på stdin, ikke som argument, så det ikke synes i prosesslista.
    printf '%s' "$token" | jq -R --arg ident "$ident" --arg rolle "$rolle" --slurpfile fil "$TOKEN_FIL" \
      '. as $token | $fil[0] | map(select(.navIdent != $ident)) + [{navIdent: $ident, rolle: $rolle, token: $token}]' \
      > "$tmp"
    mv "$tmp" "$TOKEN_FIL"
    unset token
    ok "Lagret token for $ident"
    break
  done
done

echo ""
vis_status
