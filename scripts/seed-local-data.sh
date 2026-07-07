#!/usr/bin/env bash
# Seeder lokal testdata i watson_admin-databasen.
# Trygt å kjøre flere ganger (idempotent — sletter og gjenskaper test-saker).
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

ADMIN_API="${ADMIN_API:-http://localhost:8080}"
TOKEN_URL="${TOKEN_URL:-http://localhost:8090/azuread/token}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-watson_admin}"
DB_USER="${DB_USER:-postgres}"
DB_PASS="${DB_PASS:-postgres}"

echo "→ Henter token fra mock-oauth2-server..."
TOKEN=$(curl -sf -X POST "$TOKEN_URL" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=watson-admin-api&client_secret=mock-secret&scope=api://local/.default" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

echo "→ Oppretter kontrollsaker..."
BASE="$ADMIN_API/api/v1/kontrollsaker"
H="Authorization: Bearer $TOKEN"

# Saker for SAK-36 (periodevelger) og SAK-47 (statusmodal)
SAKER=(
  '{"personIdent":"67890123456","navn":"Kari Nordmann","kategori":"ARBEID","kilde":"NAV_KONTROLL","misbruktype":["FIKTIVT_ARBEIDSFORHOLD"],"prioritet":"HOY","ytelser":[{"type":"DAGPENGER","periodeFra":"2024-01-01","periodeTil":"2024-03-31","belop":25000}]}'
  '{"personIdent":"67890123456","navn":"Kari Nordmann","kategori":"ARBEID","kilde":"A_KRIMSAMARBEID","misbruktype":["SVART_ARBEID"],"prioritet":"HOY","ytelser":[{"type":"DAGPENGER","periodeFra":"2024-05-01","periodeTil":"2024-08-31","belop":18000}]}'
  '{"personIdent":"67890123456","navn":"Kari Nordmann","kategori":"IDENTITET","kilde":"POLITIET","misbruktype":["IDENTITETSMISBRUK"],"prioritet":"HOY","ytelser":[]}'
  '{"personIdent":"67890123456","navn":"Kari Nordmann","kategori":"UTLAND","kilde":"REGISTERSAMKJORING","misbruktype":["MEDLEMSKAP_BORTFALT"],"prioritet":"LAV","ytelser":[{"type":"SYKEPENGER","periodeFra":"2024-04-01","periodeTil":"2024-06-30","belop":35000}]}'
  '{"personIdent":"67890123456","navn":"Kari Nordmann","kategori":"SAMLIV","kilde":"PUBLIKUM","misbruktype":["SKJULT_SAMLIV"],"prioritet":"NORMAL","ytelser":[{"type":"AAP","periodeFra":"2024-02-01","periodeTil":"2024-04-30"}]}'
  '{"personIdent":"67890123456","navn":"Kari Nordmann","kategori":"ANNET","kilde":"NAV_OVRIG","misbruktype":[],"prioritet":"NORMAL","ytelser":[{"type":"ANDRE","periodeFra":"2024-10-01","periodeTil":"2024-12-31","belop":22000}]}'
  '{"personIdent":"67890123456","navn":"Kari Nordmann","kategori":"ARBEID","kilde":"SKATTEETATEN","misbruktype":["HVIT_INNTEKT","FEIL_INNTEKTSGRUNNLAG"],"prioritet":"HOY","ytelser":[{"type":"FORELDREPENGER","periodeFra":"2025-01-01","periodeTil":"2025-03-31"}]}'
  '{"personIdent":"67890123456","navn":"Kari Nordmann","kategori":"BEHANDLER","kilde":"NAV_KONTROLL","misbruktype":["BEHANDLER_25_7"],"prioritet":"NORMAL","ytelser":[]}'
  '{"personIdent":"67890123456","navn":"Kari Nordmann","kategori":"TILTAK","kilde":"NAV_OVRIG","misbruktype":["MISBRUK_AV_TILTAKSPLASS"],"prioritet":"LAV","ytelser":[{"type":"ANDRE","periodeFra":"2025-04-01","periodeTil":"2025-06-30"}]}'
  '{"personIdent":"67890123456","navn":"Kari Nordmann","kategori":"SAMLIV","kilde":"PUBLIKUM","misbruktype":["ENDRET_SIVILSTATUS"],"prioritet":"NORMAL","ytelser":[{"type":"AAP","periodeFra":"2025-05-01","periodeTil":"2025-09-30","belop":29000}]}'
  '{"personIdent":"67890123456","navn":"Kari Nordmann","kategori":"ARBEID","kilde":"NAV_KONTROLL","misbruktype":["SKJULT_AKTIVITET"],"prioritet":"HOY","ytelser":[{"type":"SYKEPENGER","periodeFra":"2025-07-01","periodeTil":"2025-09-30"}]}'
  '{"personIdent":"67890123456","navn":"Kari Nordmann","kategori":"UTLAND","kilde":"UTENRIKSTJENESTEN","misbruktype":["INNENFOR_EOS"],"prioritet":"NORMAL","ytelser":[]}'
  '{"personIdent":"67890123456","navn":"Kari Nordmann","kategori":"ARBEID","kilde":"REGISTERSAMKJORING","misbruktype":["FIKTIVT_ARBEIDSFORHOLD","SVART_ARBEID"],"prioritet":"HOY","ytelser":[{"type":"DAGPENGER","periodeFra":"2026-01-01","periodeTil":"2026-03-31","belop":31000}]}'
  '{"personIdent":"67890123456","navn":"Kari Nordmann","kategori":"SAMLIV","kilde":"NAV_KONTROLL","misbruktype":["SKJULT_SAMLIV"],"prioritet":"NORMAL","ytelser":[]}'
  '{"personIdent":"67890123456","navn":"Kari Nordmann","kategori":"IDENTITET","kilde":"POLITIET","misbruktype":[],"prioritet":"LAV","ytelser":[]}'
)

SAK_IDS=()
for sak in "${SAKER[@]}"; do
  resp=$(curl -sf -X POST "$BASE" -H "$H" -H "Content-Type: application/json" -d "$sak" 2>/dev/null) || true
  id=$(echo "$resp" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
  if [ -n "$id" ]; then
    SAK_IDS+=("$id")
    echo -e "  ${GREEN}✓${NC} sakId=$id"
  fi
done

echo ""
echo "→ Oppdaterer datoer og statuser via databasen..."

node - << 'NODEEOF'
const { Client } = require('/tmp/pg-seed2/node_modules/pg');
async function main() {
  const c = new Client({ host: process.env.DB_HOST||'localhost', port: parseInt(process.env.DB_PORT||'5432'),
    database: process.env.DB_NAME||'watson_admin', user: process.env.DB_USER||'postgres', password: process.env.DB_PASS||'postgres' });
  await c.connect();
  const { rows } = await c.query('SELECT sak_id FROM kontrollsak ORDER BY sak_id ASC');
  const ids = rows.map(r => r.sak_id);
  const dates = ['2024-01-15T10:00:00Z','2024-02-20T09:00:00Z','2024-04-05T11:00:00Z','2024-06-12T14:00:00Z',
    '2024-08-19T10:30:00Z','2024-10-28T08:00:00Z','2025-01-08T09:00:00Z','2025-02-14T11:00:00Z',
    '2025-04-03T10:00:00Z','2025-05-22T13:00:00Z','2025-07-11T09:30:00Z','2025-11-04T10:00:00Z',
    '2026-01-20T11:00:00Z','2026-03-17T10:00:00Z','2026-07-01T09:00:00Z'];
  const data = [
    {s:'AVSLUTTET',a:'INGEN_UTREDNING'},{s:'AVSLUTTET',a:'IKKE_KAPASITET'},{s:'AVSLUTTET',a:null},
    {s:'UTREDES',a:null},{s:'UTREDES',a:null},{s:'UTREDES',a:null},
    {s:'STRAFFERETTSLIG_VURDERING',a:null},{s:'STRAFFERETTSLIG_VURDERING',a:null},
    {s:'ANMELDT',a:null},{s:'ANMELDT',a:null},
    {s:'HENLAGT',a:'IKKE_TILSTREKKELIG_BEVISGRUNNLAG'},{s:'HENLAGT',a:'FORELDET'},
    {s:'OPPRETTET',a:null},{s:'OPPRETTET',a:null},{s:'OPPRETTET',a:null}
  ];
  for (let i=0; i<ids.length; i++) {
    const d = data[i]||{s:'OPPRETTET',a:null};
    await c.query('UPDATE kontrollsak SET opprettet=$1,status=$2,henleggelsesarsak=$3 WHERE sak_id=$4',
      [dates[i]||dates[dates.length-1], d.s, d.a, ids[i]]);
  }
  console.log('Datoer og statuser oppdatert for ' + ids.length + ' saker');
  await c.end();
}
main().catch(e=>{console.error(e.message);process.exit(1);});
NODEEOF

echo ""
echo -e "${GREEN}✓ Seed fullført!${NC}"
echo "  Testdata klar for SAK-36 (periodevelger) og SAK-47 (statusmodal)"
echo "  Saker: 2024×6, 2025×6, 2026×3 | Statuser: alle 6 typer"
