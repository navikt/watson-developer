#!/usr/bin/env bash
# Installerer fnr-guard (@navikt/fnr-guard) som pre-commit-hook i watson-developer
# og alle repoer i repos/. Hvilke repoer som omfattes, står i .fnr-guard.json.
#
#   ./scripts/install-git-hooks.sh           installer, hopper over repoer med egen core.hooksPath
#   ./scripts/install-git-hooks.sh --force   overstyr eksisterende core.hooksPath
#   ./scripts/install-git-hooks.sh --status  vis status uten å endre noe (exit 1 hvis noe mangler)
#
# Kjøres av clone-repos.sh og sync-repos.sh. Se https://github.com/navikt/fnr-guard
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FNR_GUARD="$ROOT_REPO_DIR/node_modules/.bin/fnr-guard"
# Tidligere versjon la hookene her. Repoer som fortsatt peker hit, flyttes over.
GAMMEL_HOOKS_PATH="$SCRIPT_DIR/git-hooks"

YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

modus=install
force=()
for arg in "$@"; do
  case "$arg" in
    --force) force=(--force) ;;
    --status) modus=status ;;
    *) echo "Bruk: $0 [--force | --status]" >&2; exit 2 ;;
  esac
done

if ! command -v node >/dev/null 2>&1; then
  echo -e "  ${RED}✗${NC} node mangler, og hooken stopper alle commits. Installer Node 20+."
  exit 1
fi

NPMRC_HJELP="Krever tilgang til GitHub Packages, se https://github.com/navikt/fnr-guard#før-du-starter-tilgang-til-github-packages"

cd "$ROOT_REPO_DIR"

# --status skriver ingenting, så den installerer heller ikke pakken.
if [ "$modus" = status ]; then
  if [ ! -x "$FNR_GUARD" ]; then
    echo -e "  ${RED}✗${NC} fnr-guard er ikke installert. Kjør ${YELLOW}$SCRIPT_DIR/install-git-hooks.sh${NC}."
    exit 1
  fi
  exec "$FNR_GUARD" status
fi

# Hent eller oppdater pakken. Dette ligger her og ikke bare i sync-repos.sh,
# slik at første ./sync.sh etter at hookene ble flyttet fullfører migreringen
# selv om den kjører en eldre sync-repos.sh.
echo "📦 Installerer fnr-guard"
if ! pnpm install --frozen-lockfile --silent; then
  echo -e "  ${RED}✗${NC} pnpm install feilet. $NPMRC_HJELP" >&2
  exit 1
fi
if [ ! -x "$FNR_GUARD" ]; then
  echo -e "  ${RED}✗${NC} fant ikke $FNR_GUARD etter pnpm install." >&2
  exit 1
fi

# Fjern core.hooksPath som peker til de gamle hookene i scripts/git-hooks,
# ellers hopper fnr-guard install over repoet.
for repo_path in "$ROOT_REPO_DIR" "$ROOT_REPO_DIR"/repos/*/; do
  git -C "$repo_path" rev-parse --git-dir >/dev/null 2>&1 || continue
  naa="$(git -C "$repo_path" config --get core.hooksPath || true)"
  if [ "$naa" = "$GAMMEL_HOOKS_PATH" ]; then
    if ! git -C "$repo_path" config --unset core.hooksPath; then
      echo -e "  ${RED}✗${NC} $(basename "$repo_path"): kunne ikke fjerne gammel hook. Kjør skriptet utenfor sandboxen." >&2
      exit 1
    fi
  fi
done

if ! "$FNR_GUARD" install ${force[@]+"${force[@]}"}; then
  echo -e "  ${YELLOW}⚠${NC} Ikke alle repoer fikk hooken. Bruk --force for å overstyre, eller kjør utenfor sandboxen."
  exit 1
fi
