#!/usr/bin/env bash
# Laster WireMock-stubs og tilhørende responsefiler fra nav-persondata-api
# inn i WireMock via Admin API. Kjøres som one-shot local_resource i Tilt.
set -euo pipefail
shopt -s nullglob

WIREMOCK_URL="${WIREMOCK_URL:-http://localhost:7164}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAPPINGS_DIR="$SCRIPT_DIR/../../nav-persondata-api/src/test/resources/mappings"
FILES_DIR="$SCRIPT_DIR/../../nav-persondata-api/src/test/resources/__files"

echo "→ Venter på WireMock på $WIREMOCK_URL ..."
ready=0
for i in $(seq 1 30); do
    if curl -sf "$WIREMOCK_URL/__admin/health" >/dev/null 2>&1; then
        ready=1
        break
    fi
    echo "  ($i/30) ikke klar ennå, venter 2s ..."
    sleep 2
done
if [ "$ready" -eq 0 ]; then
  echo -e "\033[0;31m✗ WireMock svarte ikke etter 60s — avbryter\033[0m" >&2
  exit 1
fi

echo "→ Sjekker kildemapper..."
if [ ! -d "$MAPPINGS_DIR" ]; then
  echo -e "\033[0;31m✗ Finner ikke $MAPPINGS_DIR — er nav-persondata-api klonet?\033[0m" >&2
  exit 1
fi
if [ ! -d "$FILES_DIR" ]; then
  echo -e "\033[0;31m✗ Finner ikke $FILES_DIR — er nav-persondata-api klonet?\033[0m" >&2
  exit 1
fi

echo "→ Sletter eksisterende stubs og filer ..."
curl -sf -X DELETE "$WIREMOCK_URL/__admin/mappings" >/dev/null
curl -sf -X DELETE "$WIREMOCK_URL/__admin/files" >/dev/null 2>&1 || true

echo "→ Laster responsfiler fra $FILES_DIR ..."
for file in "$FILES_DIR"/*.json; do
    name=$(basename "$file")
    curl -sf -X PUT "$WIREMOCK_URL/__admin/files/$name" \
        -H "Content-Type: application/json" \
        --data-binary "@$file" >/dev/null
    echo "  ✓ $name"
done

echo "→ Laster stubs fra $MAPPINGS_DIR ..."
count=0
for file in "$MAPPINGS_DIR"/*.json; do
    name=$(basename "$file")
    curl -sf -X POST "$WIREMOCK_URL/__admin/mappings" \
        -H "Content-Type: application/json" \
        -d "@$file" >/dev/null
    echo "  ✓ $name"
    count=$((count + 1))
done

echo "→ $count stubs lastet inn"
curl -sf "$WIREMOCK_URL/__admin/mappings" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'→ WireMock har {d[\"meta\"][\"total\"]} mappings klar')"
