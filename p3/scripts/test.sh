#!/bin/bash
# ==============================================================================
# P3 - TEST SCRIPT
# Vérifie les exigences du sujet Inception of Things - Part 3
#
# Exigences :
#   - Outils : docker, k3d, kubectl, argocd CLI
#   - Cluster K3d operationnel
#   - Namespaces : argocd + dev
#   - Argo CD deploye et UI accessible (localhost:31080)
#   - Application GitOps synchronisee et saine
#   - Pod running dans dev + http://localhost:8888 repond
# ==============================================================================

set -u

CLUSTER_NAME="${CLUSTER_NAME:-mycluster}"
ARGOCD_NS="${ARGOCD_NS:-argocd}"
DEV_NS="${DEV_NS:-dev}"
APP_NAME="${APP_NAME:-wil-app}"
APP_URL="${APP_URL:-http://localhost:8888}"
ARGOCD_URL="${ARGOCD_URL:-http://localhost:31080}"
TIMEOUT=300

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
RESET="\033[0m"

PASS=0
FAIL=0

pass() { echo -e "${GREEN}[OK]${RESET} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}[KO]${RESET} $1"; FAIL=$((FAIL + 1)); }
warn() { echo -e "${YELLOW}[..]${RESET} $1"; }

wait_for() {
    local desc="$1" cmd="$2"
    local elapsed=0
    while [ "$elapsed" -lt "$TIMEOUT" ]; do
        if eval "$cmd" >/dev/null 2>&1; then return 0; fi
        warn "$desc... (${elapsed}s)"
        sleep 5; elapsed=$((elapsed + 5))
    done
    return 1
}

echo "========================================="
echo "  P3 - Tests Inception of Things"
echo "========================================="
echo ""

# --- Outils prerequis ---
echo "[ Prerequis ]"
for bin in docker k3d kubectl argocd curl; do
    if command -v "$bin" >/dev/null 2>&1; then
        pass "$bin installe"
    else
        fail "$bin manquant — lance 'make setup'"; exit 1
    fi
done
echo ""

# --- Cluster K3d ---
echo "[ Cluster K3d ]"
if k3d cluster list "$CLUSTER_NAME" >/dev/null 2>&1; then
    pass "Cluster '$CLUSTER_NAME' existe"
else
    fail "Cluster '$CLUSTER_NAME' introuvable — lance 'make up'"; exit 1
fi
if wait_for "Node Ready" "kubectl get nodes --no-headers | grep -q ' Ready '"; then
    pass "Au moins un node Ready"
else
    fail "Aucun node Ready"
fi
echo ""

# --- Namespaces (exigence sujet : argocd + dev) ---
echo "[ Namespaces ]"
if wait_for "Namespace $ARGOCD_NS" "kubectl get ns $ARGOCD_NS --no-headers | grep -q Active"; then
    pass "Namespace '$ARGOCD_NS' actif"
else
    fail "Namespace '$ARGOCD_NS' manquant"
fi
if wait_for "Namespace $DEV_NS" "kubectl get ns $DEV_NS --no-headers | grep -q Active"; then
    pass "Namespace '$DEV_NS' actif"
else
    fail "Namespace '$DEV_NS' manquant"
fi
echo ""

# --- Argo CD ---
echo "[ Argo CD ]"
if wait_for "argocd-server available" \
    "kubectl wait --for=condition=available deployment/argocd-server -n $ARGOCD_NS --timeout=10s"; then
    pass "Deployment argocd-server disponible"
else
    fail "Deployment argocd-server indisponible"
fi
# -L suit la redirection HTTP→HTTPS, -k ignore le cert auto-signé
if wait_for "UI Argo CD accessible" \
    "curl -skL --max-time 5 $ARGOCD_URL | grep -qi 'argo'"; then
    pass "Interface web Argo CD accessible sur $ARGOCD_URL"
else
    fail "Interface web Argo CD inaccessible sur $ARGOCD_URL"
fi
echo ""

# --- Application GitOps ---
echo "[ Application GitOps ]"
if wait_for "Application $APP_NAME existe" \
    "kubectl get application $APP_NAME -n $ARGOCD_NS"; then
    pass "Application '$APP_NAME' existe"
else
    fail "Application '$APP_NAME' introuvable"
fi
if wait_for "Application Synced" \
    "kubectl get application $APP_NAME -n $ARGOCD_NS -o jsonpath='{.status.sync.status}' | grep -q Synced"; then
    pass "Application synchronisee (Synced)"
else
    fail "Application non synchronisee"
fi
if wait_for "Application Healthy" \
    "kubectl get application $APP_NAME -n $ARGOCD_NS -o jsonpath='{.status.health.status}' | grep -q Healthy"; then
    pass "Application saine (Healthy)"
else
    fail "Application non saine"
fi
echo ""

# --- Application dans le namespace dev ---
echo "[ Application dans '$DEV_NS' ]"
if wait_for "Pod Running dans dev" \
    "kubectl get pods -n $DEV_NS --no-headers | grep -q Running"; then
    pass "Pod Running dans '$DEV_NS'"
    kubectl get pods -n "$DEV_NS" --no-headers 2>/dev/null
else
    fail "Aucun pod Running dans '$DEV_NS'"
fi
if wait_for "Reponse HTTP $APP_URL" \
    "curl -s --max-time 3 $APP_URL | grep -Eq 'status|v[12]'"; then
    response=$(curl -s --max-time 3 "$APP_URL")
    pass "Application repond sur $APP_URL : $response"
else
    fail "Application inaccessible sur $APP_URL"
fi
echo ""

echo "========================================="
echo "  kubectl get ns"
echo "========================================="
kubectl get ns 2>/dev/null
echo ""
echo "========================================="
echo "  kubectl get pods -n $DEV_NS"
echo "========================================="
kubectl get pods -n "$DEV_NS" 2>/dev/null
echo ""
echo "========================================="
echo "  Resultats : $PASS OK / $((PASS + FAIL)) tests"
echo "========================================="
[ "$FAIL" -eq 0 ]
