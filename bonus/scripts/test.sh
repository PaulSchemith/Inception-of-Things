#!/bin/bash
# ==============================================================================
# BONUS - TEST SCRIPT
# ==============================================================================
#
# BUT : Valider que P3 fonctionne avec GitLab LOCAL au lieu de GitHub.
#
# CONTEXTE : 
#   • Cluster K3d local (comme P3)
#   • GitLab helm chart déployé dans namespace 'gitlab'
#   • Argo CD pointant vers un repo GitLab LOCAL (pas GitHub)
#   • App wil-playground toujours dans 'dev', mais source = GitLab local
#
# EXIGENCES BONUS VÉRIFIÉES :
#   ✓ GitLab tourne localement (namespace gitlab, accessible localhost:8929)
#   ✓ GitLab est configuré avec un repo 'root/iot-wil-app' contenant deployment.yaml
#   ✓ Namespace 'gitlab' créé explicitement (requirement sujet)
#   ✓ Argo CD source = GitLab local (pas GitHub)
#   ✓ Application wil-playground deployée et accessible (comme P3)
#
# CHECKS (dans l'ordre) :
#   1. Prerequis       : helm, docker, k3d, kubectl, curl, jq
#   2. Cluster K3d     : existence + nodes Ready
#   3. Namespaces      : argocd + dev + gitlab (TOUS TROIS explicitement requis)
#   4. GitLab          : pods Ready, UI/API accessible, repo exists
#   5. Argo CD         : pods Ready, UI accessible
#   6. GitOps          : Application source=GitLab (PAS GitHub!), Synced, Healthy
#   7. Application dev : pod Running + curl localhost:8888 répond
#
# UTILISATION :
#   make test   (ou bash scripts/test.sh)
#
# ==============================================================================

# Pas de set -e : on veut que fail() continue le script pour voir TOUS les echecs
CLUSTER_NAME="${CLUSTER_NAME:-mycluster}"
ARGOCD_NS="argocd"
DEV_NS="dev"
GITLAB_NS="gitlab"
APP_NAME="wil-app"
APP_URL="http://localhost:8888"
ARGOCD_URL="http://localhost:31080"
GITLAB_URL="http://localhost:8929"
TIMEOUT=300   # secondes max par check

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
RESET="\033[0m"

PASS=0; FAIL=0

pass()     { echo -e "${GREEN}[✓]${RESET} $1"; PASS=$((PASS+1)); }
fail()     { echo -e "${RED}[✗]${RESET} $1"; FAIL=$((FAIL+1)); }
wait_msg() { echo -e "${YELLOW}[…]${RESET} $1"; }

# Retrie une commande toutes les 5s jusqu'a TIMEOUT secondes.
# $1 = description affichez pendant l'attente
# $2 = commande a evaluer (retour 0 = succes)
wait_for() {
    local desc="$1" cmd="$2" elapsed=0
    while [ "$elapsed" -lt "$TIMEOUT" ]; do
        if eval "$cmd" >/dev/null 2>&1; then
            return 0
        fi
        wait_msg "$desc (${elapsed}s/${TIMEOUT}s)..."
        sleep 5; elapsed=$((elapsed+5))
    done
    return 1
}

echo "========================================="
echo "  Bonus - Tests GitLab + Argo CD"
echo "========================================="
echo ""

# =============================================================================
# CHECK 1 : Prerequis
# =============================================================================
# Le bonus necessite Helm en plus des outils de P3.
# Helm est le gestionnaire de packages Kubernetes utilise pour deployer GitLab.
echo "[ 1. Prerequis - outils installes ]"
MISSING=0
for bin in helm docker k3d kubectl curl jq; do
    if command -v "$bin" >/dev/null 2>&1; then
        pass "$bin installe"
    else
        fail "$bin manquant → lance 'make setup'"
        MISSING=1
    fi
done
[ "$MISSING" -eq 1 ] && echo "Installe les outils manquants avant de continuer." && exit 1
echo ""

# =============================================================================
# CHECK 2 : Cluster K3d
# =============================================================================
echo "[ 2. Cluster K3d ]"
if k3d cluster list "$CLUSTER_NAME" >/dev/null 2>&1; then
    pass "Cluster '$CLUSTER_NAME' existe"
else
    fail "Cluster '$CLUSTER_NAME' introuvable → lance 'make up'"
    exit 1
fi
if wait_for "Node Kubernetes Ready" \
    "kubectl get nodes --no-headers | grep -q ' Ready '"; then
    NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    pass "Cluster operationnel ($NODE_COUNT node(s) Ready)"
else
    fail "Aucun node Ready"
fi
echo ""

# =============================================================================
# CHECK 3 : Namespaces (CRITIQUE : sujet exige argocd + dev + gitlab)
# =============================================================================
# C'est un critere explicite du sujet bonus :
#   "Create a dedicated namespace named gitlab."
echo "[ 3. Namespaces requis par le sujet ]"
for ns in "$ARGOCD_NS" "$DEV_NS" "$GITLAB_NS"; do
    if wait_for "Namespace $ns Active" \
        "kubectl get ns $ns --no-headers 2>/dev/null | grep -q Active"; then
        pass "Namespace '$ns' est Active"
    else
        fail "Namespace '$ns' manquant ou inactif"
    fi
done
echo ""

# =============================================================================
# CHECK 4 : GitLab
# =============================================================================
# Exigence sujet : "Your Gitlab instance must run locally."
echo "[ 4. GitLab (namespace ${GITLAB_NS}) ]"

# 4a : Pods en etat Running
GITLAB_RUNNING=$(kubectl get pods -n "$GITLAB_NS" --no-headers 2>/dev/null \
    | grep -c "Running" || true)
if [ "$GITLAB_RUNNING" -gt 0 ]; then
    pass "$GITLAB_RUNNING pod(s) GitLab Running dans '$GITLAB_NS'"
else
    fail "Aucun pod GitLab Running dans '$GITLAB_NS'"
fi

# 4b : Webservice Deployment Available
if wait_for "GitLab webservice available" \
    "kubectl wait --for=condition=available deployment/gitlab-webservice-default \
     -n $GITLAB_NS --timeout=10s 2>/dev/null"; then
    pass "Deployment gitlab-webservice-default est Available"
else
    fail "Deployment gitlab-webservice-default non disponible"
fi

# 4c : Interface web accessible depuis le host
# On suit les redirections (-L) car GitLab peut rediriger vers /users/sign_in
if wait_for "GitLab UI accessible" \
    "curl -sL --max-time 8 ${GITLAB_URL} | grep -qi 'gitlab'"; then
    pass "GitLab UI accessible sur ${GITLAB_URL}"
else
    fail "GitLab UI non accessible sur ${GITLAB_URL}"
fi

# 4d : API GitLab repond
# On utilise un endpoint public ne necessitant pas d'auth : /-/health
if wait_for "API GitLab repond" \
    "curl -sf --max-time 5 ${GITLAB_URL}/-/health | grep -qi 'GitLab'"; then
    pass "API GitLab accessible (/-/health)"
else
    # Fallback sur /api/v4/projects (public si repo public)
    if curl -sf --max-time 5 "${GITLAB_URL}/api/v4/projects" >/dev/null 2>&1; then
        pass "API GitLab v4 accessible"
    else
        fail "API GitLab non accessible"
    fi
fi

# 4e : Le repo iot-wil-app existe dans GitLab (configure pour le cluster)
# Exigence sujet : "Configure Gitlab to make it work with your cluster."
if wait_for "Repo iot-wil-app existe dans GitLab" \
    "curl -sf --max-time 5 ${GITLAB_URL}/root/iot-wil-app | grep -qi 'iot-wil-app'"; then
    pass "Repo GitLab 'root/iot-wil-app' existe et accessible"
else
    fail "Repo GitLab 'root/iot-wil-app' introuvable"
fi

# 4f : deployment.yaml est present dans le repo
# Recupere le token depuis le Secret K8s pour authentifier l'appel API
GL_TOKEN=$(kubectl get secret gitlab-iot-token \
    -n "$GITLAB_NS" \
    -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null || true)

if [ -n "$GL_TOKEN" ]; then
    FILE_CHECK=$(curl -sf \
        "${GITLAB_URL}/api/v4/projects/root%2Fiot-wil-app/repository/files/deployment.yaml?ref=main" \
        -H "PRIVATE-TOKEN: $GL_TOKEN" 2>/dev/null | jq -r '.file_name // empty' 2>/dev/null || true)
    if [ "$FILE_CHECK" = "deployment.yaml" ]; then
        pass "deployment.yaml present dans le repo GitLab"
    else
        fail "deployment.yaml absent du repo GitLab"
    fi
else
    wait_msg "Token GitLab non trouve, skip verif deployment.yaml"
fi
echo ""

# =============================================================================
# CHECK 5 : Argo CD
# =============================================================================
# Exigence : "Everything you did in Part 3 must work with your local Gitlab."
# En P3, Argo CD etait installe → il doit l'etre ici aussi.
echo "[ 5. Argo CD (namespace ${ARGOCD_NS}) ]"
if wait_for "ArgoCD server Available" \
    "kubectl wait --for=condition=available deployment/argocd-server \
     -n $ARGOCD_NS --timeout=10s 2>/dev/null"; then
    pass "Argo CD server deployment Available"
else
    fail "Argo CD server deployment non disponible"
fi

# Argo CD redirige HTTP → HTTPS (cert auto-signe) : -k skip TLS, -L suit redirect
if wait_for "ArgoCD UI accessible" \
    "curl -skL --max-time 5 ${ARGOCD_URL} | grep -qi 'argo'"; then
    pass "Argo CD UI accessible sur ${ARGOCD_URL}"
else
    fail "Argo CD UI non accessible sur ${ARGOCD_URL}"
fi
echo ""

# =============================================================================
# CHECK 6 : GitOps - Argo CD surveille GitLab local (PAS GitHub)
# =============================================================================
# C'est la verification CENTRALE du bonus :
# La source de l'Application Argo CD doit etre GitLab LOCAL, pas GitHub.
echo "[ 6. GitOps : Argo CD ← GitLab local ]"

if wait_for "Application $APP_NAME existe" \
    "kubectl get application $APP_NAME -n $ARGOCD_NS >/dev/null 2>&1"; then
    pass "Application '$APP_NAME' existe dans '$ARGOCD_NS'"
else
    fail "Application '$APP_NAME' introuvable dans '$ARGOCD_NS'"
    echo ""
    echo "  Lance 'make up' pour creer l'application."
    FAIL=$((FAIL+3)); echo ""; echo "$(echo -e "${RED}[✗]${RESET}") Application Synced (skip)"; echo "$(echo -e "${RED}[✗]${RESET}") Application Healthy (skip)"
else
    # Verifie que la source pointe vers GitLab local et non GitHub
    REPO_URL=$(kubectl get application "$APP_NAME" -n "$ARGOCD_NS" \
        -o jsonpath='{.spec.source.repoURL}' 2>/dev/null || true)

    if echo "$REPO_URL" | grep -qiE "gitlab.*svc|localhost:${GITLAB_HOST_PORT:-8929}"; then
        pass "Source = GitLab local ($REPO_URL)"
    else
        fail "Source NE POINTE PAS vers GitLab local (url: $REPO_URL)"
    fi

    if wait_for "Application Synced" \
        "kubectl get application $APP_NAME -n $ARGOCD_NS \
         -o jsonpath='{.status.sync.status}' 2>/dev/null | grep -q Synced"; then
        pass "Application Synced (repo GitLab → cluster)"
    else
        SYNC=$(kubectl get application "$APP_NAME" -n "$ARGOCD_NS" \
            -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "?")
        fail "Application non Synced (status: $SYNC)"
    fi

    if wait_for "Application Healthy" \
        "kubectl get application $APP_NAME -n $ARGOCD_NS \
         -o jsonpath='{.status.health.status}' 2>/dev/null | grep -q Healthy"; then
        pass "Application Healthy"
    else
        HEALTH=$(kubectl get application "$APP_NAME" -n "$ARGOCD_NS" \
            -o jsonpath='{.status.health.status}' 2>/dev/null || echo "?")
        fail "Application non Healthy (status: $HEALTH)"
    fi
fi
echo ""

# =============================================================================
# CHECK 7 : Application dans le namespace dev
# =============================================================================
echo "[ 7. Application dans le namespace dev ]"
if wait_for "Pod Running dans dev" \
    "kubectl get pods -n $DEV_NS --no-headers 2>/dev/null | grep -q Running"; then
    pass "Pod Running dans '$DEV_NS'"
    kubectl get pods -n "$DEV_NS" --no-headers 2>/dev/null \
        | while read -r line; do echo "   $line"; done
else
    fail "Aucun pod Running dans '$DEV_NS'"
fi

if wait_for "curl localhost:8888 repond" \
    "curl -s --max-time 5 ${APP_URL} 2>/dev/null | grep -Eq 'status|v[12]'"; then
    RESP=$(curl -s --max-time 5 "$APP_URL" 2>/dev/null)
    pass "Application accessible sur ${APP_URL}"
    echo "   Reponse : $RESP"
else
    fail "Application non accessible sur ${APP_URL}"
fi
echo ""

# =============================================================================
# RESUME + DIAGNOSTIC
# =============================================================================
echo "========================================="
echo "  Resume : ${PASS} passes, ${FAIL} echecs"
echo "========================================="
echo ""
echo "--- Namespaces ---"
kubectl get ns 2>/dev/null
echo ""
echo "--- Pods GitLab (${GITLAB_NS}) ---"
kubectl get pods -n "$GITLAB_NS" 2>/dev/null \
    | awk 'NR==1{print "  "$0} NR>1{print "  "$0}'
echo ""
echo "--- Application Argo CD ---"
kubectl get application "$APP_NAME" -n "$ARGOCD_NS" 2>/dev/null \
    -o custom-columns="NAME:.metadata.name,REPO:.spec.source.repoURL,SYNC:.status.sync.status,HEALTH:.status.health.status" \
    || true
echo ""
echo "--- Pods dev ---"
kubectl get pods -n "$DEV_NS" 2>/dev/null
echo ""

if [ "$FAIL" -gt 0 ]; then
    echo "Certains tests ont echoue. Consulte les messages ci-dessus."
    exit 1
fi
echo "Tous les tests sont passes !"
