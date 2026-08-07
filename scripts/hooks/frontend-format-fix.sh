#!/bin/bash
# Kjøres på agentStop for GitHub Copilot CLI når agenten kjøres fra
# watson-developer (repo-roten for denne hooken).
#
# Siden agenten alltid startes i watson-developer, men faktiske kodeendringer
# ofte skjer i søsken-repoer klonet til ../ (f.eks. watson-sak-frontend,
# watson-sok), kan vi ikke stole på sesjonens cwd for å vite hvilket repo som
# ble endret. I stedet skanner vi alle søsken-kataloger i ../, finner de som
# har et "format:fix"-script i package.json OG uncommitted git-endringer, og
# kjører "pnpm format:fix" i hver av dem.
#
# Hvis formateringen feiler, tvinges agenten til å ta enda en tur (decision:
# "block") med feilmeldingen som prompt, slik at den kan rette opp feilene.
set -euo pipefail

input=$(cat)

stop_hook_active=$(echo "$input" | jq -r '.stop_hook_active // false')

# Ikke prøv å blokkere på nytt hvis denne turen allerede ble tvunget videre av
# denne hooken forrige runde (unngå uendelig løkke ved vedvarende feil).
if [ "$stop_hook_active" = "true" ]; then
  exit 0
fi

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || echo "")
parent_dir=$(dirname "${repo_root:-$script_dir}")

errors=""

for dir in "$parent_dir"/*/; do
  dir="${dir%/}"

  [ -f "$dir/package.json" ] || continue
  jq -e '.scripts["format:fix"]' "$dir/package.json" >/dev/null 2>&1 || continue

  # Bare kjør formatering i repoer som faktisk har uncommitted endringer.
  git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || continue
  [ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ] || continue

  output=$(cd "$dir" && pnpm format:fix 2>&1) && exit_code=0 || exit_code=$?

  if [ "$exit_code" -ne 0 ]; then
    trimmed=$(printf '%s' "$output" | tail -c 2000)
    errors="${errors}\`pnpm format:fix\` feilet i \`$dir\`:\n\n${trimmed}\n\n"
  fi
done

if [ -n "$errors" ]; then
  jq -n --arg reason "$(printf '%b' "${errors}Rett opp formateringsfeilene og kjør \`pnpm format:fix\` på nytt i de aktuelle repoene.")" \
    '{decision: "block", reason: $reason}'
fi

exit 0
