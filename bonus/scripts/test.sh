#!/bin/bash
# ==============================================================================
# BONUS - TEST SCRIPT
# Vérifie les exigences du sujet Inception of Things - Bonus
#
# Exigences :
#   - Outils : helm, docker, k3d, kubectl, curl, jq
#   - Cluster K3d operationnel
#   - Namespaces : argocd + dev + gitlab
#   - GitLab deploye et UI accessible (localhost:8929)
#   - Repo GitLab iot-wil-app configure avec deployment.yaml
#   - Argo CD source = GitLab local (pas GitHub)
#   - Application GitOps synchronisee et saine
#   - Pod running dans dev + http://localhost:8888 repond
# ==============================================================================

set -u

CLUSTER_NAME="${CLUSTER_NAME:-mycluster}"
ARGOCD_NS="argocd"
DEV_NS="dev"
GITLAB_NS="gitlab"
APP_NAME="wil-app"
APP_URL="http://localhost:8888"
ARGOCD_URL="http://localhost:31080"
GITLAB_URL="http://localhost:8929"
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
echo "  Bonus - Tests GitLab + Argo CD"
echo "========================================="
echo ""

# --- Prerequis ---
echo "[ Prerequis ]"
MISSING=0
for bin in helm docker k3d kubectl curl jq; do
    if command -v "$bin" >/dev/null 2>&1; then
        pass "$bin installe"
    else
        fail "$bin manquant — lance 'make setup'"
        MISSING=1
    fi
done
[ "$MISSING" -eq 1 ] && exit 1
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

# --- Namespaces (sujet : argocd + dev + gitlab) ---
echo "[ Namespaces ]"
for ns in "$ARGOCD_NS" "$DEV_NS" "$GITLAB_NS"; do
    if wait_for "Namespace $ns" "kubectl get ns $ns --no-headers | grep -q Active"; then
        pass "Namespace '$ns' actif"
    else
        fail "Namespace '$ns' manquant"
    fi
done
echo ""

# --- GitLab ---
echo "[ GitLab (namespace ${GITLAB_NS}) ]"
if wait_for "gitlab-webservice-default available" \
    "kubectl wait --for=condition=available deployment/gitlab-webservice-default \
     -n $GITLAB_NS --timeout=10s"; then
    pass "Deployment gitlab-webservice-default disponible"
else
    fail "Deployment gitlab-webservice-default indisponible"
fi
if wait_for "UI GitLab accessible" \
    "curl -sL --max-time 8 ${GITLAB_URL} | grep -qi 'gitlab'"; then
    pass "Interface web GitLab accessible sur ${GITLAB_URL}"
else
    fail "Interface web GitLab inaccessible sur ${GITLAB_URL}"
fi
if wait_for "API GitLab repond" \
    "curl -sf --max-time 5 ${GITLAB_URL}/-/health | grep -qi 'GitLab'"; then
    pass "API GitLab accessible (/-/health)"
else
    fail "API GitLab inaccessible"
fi
if wait_for "Repo iot-wil-app accessible" \
    "curl -sf --max-time 5 ${GITLAB_URL}/root/iot-wil-app | grep -qi 'iot-wil-app'"; then
    pass "Repo GitLab 'root/iot-wil-app' existe"
else
    fail "Repo GitLab 'root/iot-wil-app' introuvable"
fi

GL_TOKEN=$(kubectl get secret gitlab-iot-token \
    -n "$GITLAB_NS" \
    -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null || true)
if [ -n "$GL_TOKEN" ]; then
    FILE_CHECK=$(curl -sf \
        "${GITLAB_URL}/api/v4/projects/root%2Fiot-wil-app/repository/files/deployment.yaml?ref=main" \
        -H "PRIVATE-TOKEN: $GL_TOKEN" 2>/dev/null \
        | jq -r '.file_name // empty' 2>/dev/null || true)
    if [ "$FILE_CHECK" = "deployment.yaml" ]; then
        pass "deployment.yaml present dans le repo GitLab"
    else
        fail "deployment.yaml absent du repo GitLab"
    fi
else
    warn "Token GitLab non trouve, verif deployment.yaml ignoree"
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
# -L suit la redirection HTTP→HTTPS, -k ignore le cert auto-signe
if wait_for "UI Argo CD accessible" \
    "curl -skL --max-time 5 $ARGOCD_URL | grep -qi 'argo'"; then
    pass "Interface web Argo CD accessible sur $ARGOCD_URL"
else
    fail "Interface web Argo CD inaccessible sur $ARGOCD_URL"
fi
echo ""

# --- Application GitOps (source = GitLab local) ---
echo "[ Application GitOps ]"
if wait_for "Application $APP_NAME existe" \
    "kubectl get application $APP_NAME -n $ARGOCD_NS"; then
    pass "Application '$APP_NAME' existe"

    REPO_URL=$(kubectl get application "$APP_NAME" -n "$ARGOCD_NS" \
        -o jsonpath='{.spec.source.repoURL}' 2>/dev/null || true)
    if echo "$REPO_URL" | grep -qiE "gitlab.*svc|localhost:8929"; then
        pass "Source pointe vers GitLab local ($REPO_URL)"
    else
        fail "Source ne pointe pas vers GitLab local (url: $REPO_URL)"
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
else
    fail "Application '$APP_NAME' introuvable"
    fail "Source GitLab (skip)"
    fail "Application Synced (skip)"
    fail "Application Healthy (skip)"
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
    "curl -s --max-time 5 $APP_URL | grep -Eq 'status|v[12]'"; then
    response=$(curl -s --max-time 5 "$APP_URL")
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
echo "  kubectl get pods -n $GITLAB_NS"
echo "========================================="
kubectl get pods -n "$GITLAB_NS" 2>/dev/null
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
