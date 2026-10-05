#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS_DIR="$SCRIPT_DIR/../repos"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ ! -d "$REPOS_DIR" ]; then
  printf "${RED}✗${NC} Finner ikke repos-mappen: %s\n" "$REPOS_DIR" >&2
  exit 1
fi

to_https() {
  local url="$1"
  if [[ "$url" == https://* ]]; then
    printf '%s\n' "$url"
  elif [[ "$url" =~ ^(http|git)://([^/]+)/(.+)$ ]]; then
    printf 'https://%s/%s\n' "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
  elif [[ "$url" =~ ^ssh://([^/@]+@)?([^/:]+)/(.+)$ ]]; then
    printf 'https://%s/%s\n' "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
  elif [[ "$url" =~ ^([^/@:]+@)?([^/:]+):([^/].*)$ ]]; then
    printf 'https://%s/%s\n' "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
  else
    return 1
  fi
}

failed=0
found=0
for repo_path in "$REPOS_DIR"/*/; do
  [ -e "$repo_path/.git" ] || continue
  found=$((found + 1))
  repo_name="$(basename "$repo_path")"
  remotes="$(git -C "$repo_path" remote)"
  if [ -z "$remotes" ]; then
    printf "${YELLOW}⟳${NC} %s har ingen remotes\n" "$repo_name"
    continue
  fi

  while IFS= read -r remote; do
    for field in url pushurl; do
      key="remote.$remote.$field"
      if urls="$(git -C "$repo_path" config --local --get-all "$key")"; then
        :
      else
        status=$?
        if [ "$status" -eq 1 ]; then
          continue
        fi
        printf "${RED}✗${NC} Kunne ikke lese %s i %s\n" "$key" "$repo_name" >&2
        exit "$status"
      fi

      while IFS= read -r url; do
        if ! https_url="$(to_https "$url")"; then
          printf "${RED}✗${NC} %s (%s %s): URL-formatet støttes ikke; uendret\n" \
            "$repo_name" "$remote" "$field" >&2
          failed=$((failed + 1))
          continue
        fi
        if [ "$url" = "$https_url" ]; then
          printf "${YELLOW}⟳${NC} %s (%s %s) bruker allerede HTTPS\n" \
            "$repo_name" "$remote" "$field"
          continue
        fi
        if git -C "$repo_path" config --local --fixed-value --replace-all "$key" "$https_url" "$url"; then
          printf "${GREEN}✓${NC} %s (%s %s) endret til HTTPS\n" \
            "$repo_name" "$remote" "$field"
        else
          printf "${RED}✗${NC} Kunne ikke endre %s i %s\n" "$key" "$repo_name" >&2
          failed=$((failed + 1))
        fi
      done <<< "$urls"
    done
  done <<< "$remotes"
done

if [ "$found" -eq 0 ]; then
  printf "${YELLOW}⟳${NC} Fant ingen git-repoer i repos-mappen\n"
fi
if [ "$failed" -gt 0 ]; then
  printf "${RED}✗${NC} Ferdig med %s feil\n" "$failed" >&2
  exit 1
fi
