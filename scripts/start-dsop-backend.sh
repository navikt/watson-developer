#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../repos/dsop-kontroll"

if [[ -n "${NAIS_CLUSTER_NAME:-}" ]]; then
  printf '✗ DSOP-lokalmiljøet kan ikke kjøres på Nais\n' >&2
  exit 1
fi

if /usr/libexec/java_home -v 17 >/dev/null 2>&1; then
  export JAVA_HOME="$(/usr/libexec/java_home -v 17)"
else
  export JAVA_HOME="$(/usr/libexec/java_home -v 21)"
fi
export PATH="$JAVA_HOME/bin:$PATH"
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy
export NO_PROXY='localhost,127.0.0.1'
export APPLICATION_PROFILE=LOCAL DSOP_LOCAL_MODE=true APPLICATION_HOST=127.0.0.1 APPLICATION_PORT=8100
export DB_URL='' JWT_ENABLED=true
export AAD_CLIENTID=dsop-local AAD_GROUP_KONTROLL=dsop-local
export AAD_SECRET=local-only
export AAD_USERPRINCIPAL=saksbehandler@example.invalid
export AAD_TOKENURL=http://127.0.0.1:7165/azure/token
export JWT_ISSUER=http://127.0.0.1:8090/dsop-azure
export JWT_JWKS_URI=http://127.0.0.1:8090/dsop-azure/jwks
export TOKEN_X_CLIENT_ID=dsop-local
export TOKEN_X_ISSUER=http://127.0.0.1:8090/dsop-tokenx
export TOKEN_X_JWKS_URI=http://127.0.0.1:8090/dsop-tokenx/jwks
export TOKEN_X_WELL_KNOWN_URL=http://127.0.0.1:8090/dsop-tokenx/.well-known/openid-configuration
export TOKEN_X_TOKEN_ENDPOINT=http://127.0.0.1:8090/dsop-tokenx/token
# Reuse the repository's existing LOCAL-only test key for the unchanged assertion signer.
# No key is created, printed or persisted by this script.
TOKEN_X_PRIVATE_JWK="$(python3 - <<'PY'
from pathlib import Path
for line in Path('src/main/resources/application.properties').read_text(encoding='latin1').splitlines():
    key, separator, value = line.partition('=')
    if separator and key.strip() == 'maskinporten.client.jwk':
        print(value.strip())
        break
else:
    raise SystemExit('Mangler lokal testnøkkel i DSOP-repoet')
PY
)"
export TOKEN_X_PRIVATE_JWK
export ALTINN_RETTIGHETER_ARBEIDSGIVERALTINNTILGANGER_URL=http://127.0.0.1:7165/altinn
export ALTINN_RETTIGHETER_ARBEIDSGIVERALTINNTILGANGER_SCOPE=dsop-local
export ALTINN_CORRESPONDENCE_RESOURCE_ID=dsop-local
export ALTINN_CORRESPONDENCE_BASE_URL=http://127.0.0.1:7165/altinn/correspondence
export BANK_FRONTEND_URL=http://127.0.0.1:3000/samarbeidspartner/kontoopplysninger/skjema
export PDL_GRAPHQL_URL=http://127.0.0.1:7165/pdl/graphql
export SAF_URL=http://127.0.0.1:7165/saf
export DOKARKIV_URL=http://127.0.0.1:7165/dokarkiv
export CLAMAV_URL=http://127.0.0.1:7165/clamav
export BRREG_URL=http://127.0.0.1:7165/brreg
export FELLESDATAKATALOG_URL=http://127.0.0.1:7165/fellesdatakatalog
export KAR_RELATIONSHIPS_URL=http://127.0.0.1:7165/kar
export SKJERMINGSLOSNINGEN_REST_URL=http://127.0.0.1:7165/skjerming
export MASKINPORTEN_TOKEN_ENDPOINT=http://127.0.0.1:7165/maskinporten/token
export PDF_GENERATOR_ORIGIN=http://127.0.0.1:9000
export DSOP_LOCAL_GRAPH_URL=http://127.0.0.1:7165/graph
export DSOP_LOCAL_GRAPH_TOKEN=local-downstream
mkdir -p "$SCRIPT_DIR/../.local"
export DSOP_LOCAL_DB_PORT_FILE="$SCRIPT_DIR/../.local/dsop-db-port"
rm -f "$DSOP_LOCAL_DB_PORT_FILE"

exec ./gradlew run
