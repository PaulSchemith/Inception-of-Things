#!/bin/bash
# =============================================================================
# P3 Test Script - Verifie toutes les exigences du sujet
# =============================================================================
#
# CONTEXTE DU SUJET :
#   Ce script valide que l'infrastructure P3 est correctement deployee :
#   - Cluster K3d fonctionnel
#   - Namespace "argocd" avec Argo CD installe et accessible
#   - Namespace "dev" avec l'application deployee via GitOps
#   - Application accessible sur localhost:8888
#
# CE QUE LE SUJET DEMANDE :
#   $> k get ns           → doit montrer argocd + dev
#   $> k get pods -n dev  → au moins un pod running (wil-playground)
#   $> curl localhost:8888 → {"status":"ok", "message": "v1"} (ou v2)
#
# UTILISATION :
#   make test   (ou bash scripts/test.sh)
#
# =============================================================================
set -e

# === CONFIGURATION ===
CLUSTER_NAME="${CLUSTER_NAME:-mycluster}"
ARGOCD_NS="${ARGOCD_NS:-argocd}"
DEV_NS="${DEV_NS:-dev}"
APP_NAME="${APP_NAME:-wil-app}"
APP_URL="${APP_URL:-http://localhost:8888}"
ARGOCD_URL="${ARGOCD_URL:-http://localhost:31080}"

# Timeout en secondes pour les checks qui necessitent de l'attente
# (demarrage de pods, synchronisation Argo CD...)
TIMEOUT=300

# === COULEURS TERMINAL ===
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
RESET="\033[0m"

# Compteurs pour le resume final
TESTS_PASS=0
TESTS_FAIL=0

# Fonctions d'affichage
pass() { echo -e "${GREEN}[PASS]${RESET} $1"; TESTS_PASS=$((TESTS_PASS + 1)); }
fail() { echo -e "${RED}[FAIL]${RESET} $1"; TESTS_FAIL=$((TESTS_FAIL + 1)); }
wait_msg() { echo -e "${YELLOW}[....]${RESET} $1"; }

# =============================================================================
# FONCTION D'ATTENTE GENERIQUE
# =============================================================================
# Certains checks echouent la premiere fois (pod pas encore pret, service
# pas encore accessible...). Cette fonction reessaie toutes les 5 secondes
# jusqu'au timeout.
#
# $1 = description affichee pendant l'attente
# $2 = commande shell a evaluer (passee a eval)
wait_for_cmd() {
    local desc="$1"
    local cmd="$2"
    local elapsed=0
    while [ $elapsed -lt $TIMEOUT ]; do
        if eval "$cmd" >/dev/null 2>&1; then
            return 0
        fi
        wait_msg "$desc (${elapsed}s/${TIMEOUT}s)..."
        sleep 5
        elapsed=$((elapsed + 5))
    done
    return 1
}

echo "========================================="
echo "  P3 - Tests Inception of Things"
echo "========================================="
echo ""

# =============================================================================
# CHECK 1 : OUTILS PREREQUIS
# =============================================================================
# Verifie que tous les outils necessaires sont installes sur la machine.
# Sans ces outils, rien ne peut fonctionner.
echo "[ 1. Prerequis - outils installes ]"
for bin in docker k3d kubectl curl; do
    if command -v "$bin" >/dev/null 2>&1; then
        pass "$bin installe ($(command -v $bin))"
    else
        fail "$bin manquant - lance 'make setup' d'abord"
        exit 1
    fi
done
echo ""

# =============================================================================
# CHECK 2 : CLUSTER K3D
# =============================================================================
# Verifie que le cluster K3d existe et que Kubernetes est operationnel.
# - "k3d cluster list" verifie que K3d connait le cluster
# - "kubectl get nodes" verifie que l'API server repond et qu'un node est Ready
echo "[ 2. Cluster K3d ]"
if k3d cluster list "$CLUSTER_NAME" >/dev/null 2>&1; then
    pass "Cluster K3d '$CLUSTER_NAME' existe"
else
    fail "Cluster K3d '$CLUSTER_NAME' introuvable - lance 'make up' d'abord"
    exit 1
fi

if wait_for_cmd "Node Kubernetes Ready" "kubectl get nodes --no-headers | grep -q ' Ready '"; then
    pass "Au moins un node Kubernetes est Ready"
else
    fail "Aucun node Ready detecte"
fi
echo ""

# =============================================================================
# CHECK 3 : NAMESPACES
# =============================================================================
# Le sujet exige exactement 2 namespaces :
#   - "argocd" : dedie a Argo CD
#   - "dev"    : contient l'application deployee par Argo CD
echo "[ 3. Namespaces (sujet : argocd + dev) ]"
if wait_for_cmd "Namespace argocd Active" "kubectl get ns $ARGOCD_NS --no-headers | grep -q Active"; then
    pass "Namespace '$ARGOCD_NS' est Active"
else
    fail "Namespace '$ARGOCD_NS' manquant ou inactif"
fi

if wait_for_cmd "Namespace dev Active" "kubectl get ns $DEV_NS --no-headers | grep -q Active"; then
    pass "Namespace '$DEV_NS' est Active"
else
    fail "Namespace '$DEV_NS' manquant ou inactif"
fi
echo ""

# =============================================================================
# CHECK 4 : ARGO CD
# =============================================================================
# Verifie que le serveur Argo CD est deploye et accessible.
# - Le deployment doit etre "available" (pods running)
# - L'interface web doit repondre sur le port configure (31080)
echo "[ 4. Argo CD ]"
if wait_for_cmd "Deployment argocd-server available" \
    "kubectl wait --for=condition=available deployment/argocd-server -n $ARGOCD_NS --timeout=10s"; then
    pass "Deployment argocd-server est available"
else
    fail "Deployment argocd-server non disponible"
fi

# Test d'accessibilite de l'interface web Argo CD
# Argo CD redirige HTTP → HTTPS (avec cert auto-signe).
# -L : suit les redirections   -k : ignore les erreurs SSL
if wait_for_cmd "Interface Argo CD accessible" \
    "curl -skL --max-time 5 $ARGOCD_URL | grep -qi 'argo'"; then
    pass "Interface web Argo CD accessible sur $ARGOCD_URL"
else
    fail "Interface web Argo CD non accessible sur $ARGOCD_URL"
fi
echo ""

# =============================================================================
# CHECK 5 : APPLICATION GITOPS
# =============================================================================
# Verifie que l'Application Argo CD est creee, synchronisee et saine.
#
# Argo CD utilise une CRD (Custom Resource Definition) "Application" qui
# represente le lien entre un repo Git et un namespace Kubernetes.
#
# Statuts attendus :
#   - sync.status = "Synced"   → les manifests du repo sont appliques
#   - health.status = "Healthy" → tous les pods/services sont OK
echo "[ 5. Application GitOps (Argo CD → GitHub → dev) ]"
if wait_for_cmd "Application $APP_NAME existe" \
    "kubectl get application $APP_NAME -n $ARGOCD_NS"; then
    pass "Application '$APP_NAME' existe dans '$ARGOCD_NS'"
else
    fail "Application '$APP_NAME' introuvable dans '$ARGOCD_NS'"
fi

# Verification du statut de synchronisation
# "Synced" = Argo CD a bien applique les manifests du repo GitHub
if wait_for_cmd "Application synchronisee" \
    "kubectl get application $APP_NAME -n $ARGOCD_NS -o jsonpath='{.status.sync.status}' | grep -q Synced"; then
    pass "Application synchronisee (Synced)"
else
    fail "Application non synchronisee"
fi

# Verification de la sante de l'application
# "Healthy" = tous les pods/services deployes fonctionnent correctement
if wait_for_cmd "Application saine" \
    "kubectl get application $APP_NAME -n $ARGOCD_NS -o jsonpath='{.status.health.status}' | grep -q Healthy"; then
    pass "Application saine (Healthy)"
else
    fail "Application non saine"
fi
echo ""

# =============================================================================
# CHECK 6 : APPLICATION DANS LE NAMESPACE DEV
# =============================================================================
# Verifie que l'application est effectivement deployee dans "dev" :
# - Au moins un pod doit etre en etat "Running"
# - L'application doit repondre sur localhost:8888
#
# Le sujet montre :
#   $> k get pods -n dev
#   wil-playground-... 1/1 Running 0 8m9s
#   $> curl http://localhost:8888/
#   {"status":"ok", "message": "v1"}
echo "[ 6. Application dans le namespace dev ]"
if wait_for_cmd "Pod running dans dev" \
    "kubectl get pods -n $DEV_NS --no-headers | grep -q 'Running'"; then
    pass "Au moins un pod Running dans '$DEV_NS'"
    # Affiche les pods pour reference
    echo "   Pods actuels :"
    kubectl get pods -n "$DEV_NS" --no-headers 2>/dev/null | while read -r line; do
        echo "     $line"
    done
else
    fail "Aucun pod Running dans '$DEV_NS'"
fi

# Test HTTP : l'application doit repondre avec un JSON contenant la version
# wil42/playground repond : {"status":"ok", "message": "v1"} ou "v2"
if wait_for_cmd "Application repond sur $APP_URL" \
    "curl -s --max-time 3 $APP_URL | grep -Eq 'status|v[12]'"; then
    RESPONSE="$(curl -s --max-time 3 "$APP_URL")"
    pass "Application accessible sur $APP_URL"
    echo "   Reponse : $RESPONSE"
else
    fail "Application non accessible sur $APP_URL"
fi
echo ""

# =============================================================================
# RESUME + DIAGNOSTIC
# =============================================================================
echo "========================================="
echo "  Resume : $TESTS_PASS passes, $TESTS_FAIL echecs"
echo "========================================="
echo ""

# Affichage diagnostique pour la defense
echo "--- Namespaces ---"
kubectl get ns 2>/dev/null
echo ""
echo "--- Pods Argo CD ---"
kubectl get pods -n "$ARGOCD_NS" 2>/dev/null
echo ""
echo "--- Application Argo CD ---"
kubectl get application "$APP_NAME" -n "$ARGOCD_NS" -o wide 2>/dev/null || true
echo ""
echo "--- Pods dev ---"
kubectl get pods -n "$DEV_NS" 2>/dev/null
echo ""

# Code de retour : 0 si tous les tests passent, 1 sinon
if [ "$TESTS_FAIL" -gt 0 ]; then
    echo "Certains tests ont echoue. Verifie les erreurs ci-dessus."
    exit 1
fi
echo "Tous les tests sont passes !"
