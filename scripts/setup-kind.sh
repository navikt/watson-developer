#!/usr/bin/env bash
# Oppretter kind-kluster for watson-developer lokalmiljø.
# Idempotent — trygt å kjøre flere ganger.
set -euo pipefail

CLUSTER_NAME="watson"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/../kind/cluster.yaml"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

if ! command -v kind &>/dev/null; then
    echo "❌ kind er ikke installert. Se: https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
    exit 1
fi

if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo -e "${YELLOW}⟳${NC}  Kind-kluster '${CLUSTER_NAME}' finnes allerede"
else
    echo -e "⚙  Oppretter kind-kluster '${CLUSTER_NAME}'..."
    kind create cluster --name "${CLUSTER_NAME}" --config "${CONFIG}"
    echo -e "${GREEN}✓${NC}  Kluster opprettet"
fi

echo -e "⚙  Setter kubectl context til kind-${CLUSTER_NAME}..."
kubectl config use-context "kind-${CLUSTER_NAME}"
echo -e "${GREEN}✓${NC}  Klar — kjør 'tilt up' for å starte lokalmiljøet"
