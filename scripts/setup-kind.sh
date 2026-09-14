#!/usr/bin/env bash
# Oppretter kind-kluster for watson-developer lokalmiljø.
# Idempotent — trygt å kjøre flere ganger.
set -euo pipefail

CLUSTER_NAME="watson"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/../kind/cluster.yaml"
WATSON_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export KUBECONFIG="$WATSON_ROOT/.kube/config"
mkdir -p "$(dirname "$KUBECONFIG")"

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

# Sikrer at konteksten finnes i prosjektets $KUBECONFIG uansett om klusteret
# ble opprettet nå eller fantes fra før (f.eks. opprettet før denne prosjekt-
# lokale kubeconfigen ble innført, med kontekst kun i ~/.kube/config).
echo -e "⚙  Henter kubeconfig for '${CLUSTER_NAME}' til $KUBECONFIG..."
kind export kubeconfig --name "${CLUSTER_NAME}"

echo -e "⚙  Setter kubectl context til kind-${CLUSTER_NAME}..."
kubectl config use-context "kind-${CLUSTER_NAME}"
echo -e "${GREEN}✓${NC}  Klar — kjør './start' for å starte lokalmiljøet"
echo "   (bruk ./start eller eksporter KUBECONFIG=$KUBECONFIG selv før du kjører 'tilt up' direkte)"
