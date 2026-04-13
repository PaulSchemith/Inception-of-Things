#!/bin/bash
# =============================================================================
# P3 Deploy Script - Cree le cluster K3d et deploie Argo CD + l'application
# =============================================================================
#
# CONTEXTE DU SUJET :
#   Ce script met en place l'infrastructure de continuous deployment :
#
#   1. Cluster K3d  : un cluster Kubernetes local (K3s dans Docker)
#   2. Namespace "argocd" : contient le serveur Argo CD
#   3. Namespace "dev"    : contient l'application deployee automatiquement
#
#   ARGO CD = outil GitOps pour Kubernetes
#   - Il surveille un repo GitHub contenant des manifests Kubernetes
#   - Quand le repo change (ex: on passe de v1 a v2), Argo CD detecte
#     la difference et synchronise automatiquement le cluster
#   - C'est du "continuous deployment" : push sur GitHub → deploiement auto
#
#   FLOW COMPLET :
#   GitHub repo (manifests YAML) → Argo CD detecte le changement
#   → Argo CD applique les manifests dans le namespace "dev"
#   → L'application est mise a jour automatiquement
#
# UTILISATION :
#   make up   (ou bash scripts/deploy.sh)
#   make re   (detruit puis recree tout)
#
# =============================================================================
set -e

# === CONFIGURATION ===
# Ces variables sont surchargeables via l'environnement si besoin.

CLUSTER_NAME="${CLUSTER_NAME:-mycluster}"   # Nom du cluster K3d
ARGOCD_NS="${ARGOCD_NS:-argocd}"            # Namespace pour Argo CD
DEV_NS="${DEV_NS:-dev}"                     # Namespace pour l'application
APP_NAME="${APP_NAME:-wil-app}"             # Nom de l'Application Argo CD

# Port d'acces a l'interface web Argo CD depuis le host
# NodePort doit etre dans la range Kubernetes : 30000-32767
ARGOCD_NODEPORT="${ARGOCD_NODEPORT:-31080}"

# === RESOLUTION DES CHEMINS ===
# On utilise des chemins absolus pour que le script marche
# qu'il soit lance depuis le Makefile ou directement.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFS_DIR="$PROJECT_DIR/confs"

echo "Script directory: $SCRIPT_DIR"
echo "Project directory: $PROJECT_DIR"
echo "Configs directory: $CONFS_DIR"

# =============================================================================
# PREFLIGHT : Verification de la delegation cgroup
# =============================================================================
# K3s (dans K3d) a besoin du controleur cgroup "cpu" pour fonctionner.
# Sur certains environnements (VM imbriquees, LXC, WSL...), Docker ne
# delegue pas ce controleur aux conteneurs → K3s crash au demarrage.
#
# Ce check lance un conteneur Alpine ephemere et lit les controleurs
# disponibles dans /sys/fs/cgroup/cgroup.controllers.
# Si "cpu" est absent, on tente de corriger automatiquement.
check_cgroup_support() {
    local controllers

    # Lance un conteneur ephemere pour voir les controleurs disponibles
    controllers=$(docker run --rm alpine:3.20 \
        sh -c "cat /sys/fs/cgroup/cgroup.controllers 2>/dev/null || true" 2>/dev/null || true)

    if echo "$controllers" | grep -qw cpu; then
        echo "   Delegation cgroup OK (cpu disponible dans les conteneurs)"
        return 0
    fi

    echo "   cpu non disponible dans les conteneurs (detecte: ${controllers:-<aucun>})"
    echo "   Tentative de correction automatique..."

    # Tente d'activer la delegation cpu dans le sous-arbre cgroup Docker
    local subtree="/sys/fs/cgroup/system.slice/docker.service/cgroup.subtree_control"
    if [ -f "$subtree" ]; then
        sudo sh -c "echo '+cpu +cpuset +io +memory +pids' > $subtree" 2>/dev/null || true
        sudo systemctl restart docker 2>/dev/null || true
        sleep 3
    fi

    # Re-verification apres correction
    controllers=$(docker run --rm alpine:3.20 \
        sh -c "cat /sys/fs/cgroup/cgroup.controllers 2>/dev/null || true" 2>/dev/null || true)

    if echo "$controllers" | grep -qw cpu; then
        echo "   Correction reussie ! cpu maintenant disponible."
        return 0
    fi

    # Echec : on informe l'utilisateur des etapes manuelles
    echo ""
    echo "ERREUR : Impossible d'activer la delegation cgroup cpu automatiquement."
    echo "   Detecte dans les conteneurs : ${controllers:-<aucun>}"
    echo ""
    echo "   Essaye manuellement :"
    echo "   sudo sh -c \"echo '+cpu +cpuset +io +memory +pids' > /sys/fs/cgroup/system.slice/docker.service/cgroup.subtree_control\""
    echo "   sudo systemctl restart docker"
    echo ""
    echo "   Puis verifie avec :"
    echo "   docker run --rm alpine:3.20 sh -c 'cat /sys/fs/cgroup/cgroup.controllers'"
    echo ""
    echo "   Si ca ne fonctionne pas, cet environnement ne supporte peut-etre pas"
    echo "   K3d (VM imbriquee, LXC sans delegation). Lance P3 sur un autre host."
    exit 1
}

echo "[*] Verification de l'environnement..."
check_cgroup_support

# =============================================================================
# VERIFICATION DE L'ETAT DU CLUSTER
# =============================================================================
# Si un cluster existe deja et fonctionne, on le reutilise.
# Sinon, on le recree proprement.
cluster_is_healthy() {
    # Verifie que le cluster existe dans k3d
    k3d cluster list "$CLUSTER_NAME" >/dev/null 2>&1 || return 1
    # Fusionne le kubeconfig pour pouvoir utiliser kubectl
    k3d kubeconfig merge "$CLUSTER_NAME" --kubeconfig-switch-context >/dev/null 2>&1 || return 1
    # Verifie que kubectl peut joindre l'API server
    kubectl get nodes --request-timeout=10s >/dev/null 2>&1 || return 1
    return 0
}

# === VERIFICATION DES FICHIERS DE CONFIGURATION ===
if [ ! -f "$CONFS_DIR/argocd-server.yaml" ]; then
    echo "Erreur : argocd-server.yaml introuvable dans $CONFS_DIR"
    exit 1
fi
if [ ! -f "$CONFS_DIR/wil-app.yaml" ]; then
    echo "Erreur : wil-app.yaml introuvable dans $CONFS_DIR"
    exit 1
fi

# =============================================================================
# ETAPE 1 : Creation du cluster K3d
# =============================================================================
# K3d cree un cluster K3s dans des conteneurs Docker.
#
# Mappings de ports :
#   -p "8888:8888@loadbalancer"
#     → Le port 8888 du host est redirige vers le port 8888 du load balancer K3d
#     → C'est sur ce port que l'application wil42/playground repond
#
#   -p "$ARGOCD_NODEPORT:31080@loadbalancer"
#     → Le port 31080 du host est redirige vers le nodePort 31080
#     → C'est sur ce port qu'on accede a l'interface web d'Argo CD
echo "[1/6] Creation du cluster K3d..."

if ! cluster_is_healthy; then
    # Si un cluster existe mais est casse, on le supprime d'abord
    if k3d cluster list "$CLUSTER_NAME" >/dev/null 2>&1; then
        echo "[*] Cluster '$CLUSTER_NAME' existant mais defaillant. Suppression..."
        k3d cluster delete "$CLUSTER_NAME" || true
    fi

    k3d cluster create "$CLUSTER_NAME" \
        --wait \
        -p "8888:8888@loadbalancer" \
        -p "$ARGOCD_NODEPORT:31080@loadbalancer"
else
    echo "Cluster '$CLUSTER_NAME' existe deja et fonctionne."
fi

# =============================================================================
# ETAPE 1.5 : Export du kubeconfig
# =============================================================================
# kubectl a besoin d'un fichier kubeconfig pour savoir a quel cluster se
# connecter. K3d genere ce fichier et le merge dans ~/.kube/config.
echo "[*] Export du kubeconfig..."
k3d kubeconfig merge "$CLUSTER_NAME" --kubeconfig-switch-context

# =============================================================================
# ETAPE 2 : Creation des namespaces Kubernetes
# =============================================================================
# Le sujet exige 2 namespaces :
#   - "argocd" : contient tous les composants d'Argo CD (server, repo-server, etc.)
#   - "dev"    : contient l'application deployee par Argo CD
# Les namespaces isolent les ressources les unes des autres.
echo "[2/6] Creation des namespaces Kubernetes..."
kubectl create namespace "$ARGOCD_NS" 2>/dev/null || true
kubectl create namespace "$DEV_NS" 2>/dev/null || true

# =============================================================================
# ETAPE 3 : Installation d'Argo CD
# =============================================================================
# On installe Argo CD via ses manifests officiels.
# Cela cree plusieurs composants dans le namespace "argocd" :
#   - argocd-server          : l'API + interface web
#   - argocd-repo-server     : clone et analyse les repos Git
#   - argocd-application-controller : synchronise l'etat desire vs reel
#   - argocd-dex-server      : authentification (SSO)
#   - argocd-redis            : cache interne
echo "[3/6] Installation d'Argo CD..."
kubectl apply -n "$ARGOCD_NS" -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# =============================================================================
# ETAPE 4 : Attente du demarrage d'Argo CD
# =============================================================================
# Le deploiement d'Argo CD peut prendre 1-3 minutes (telechargement images Docker).
# On attend que le deployment "argocd-server" soit marque "available" par Kubernetes.
echo "[4/6] Attente du demarrage d'Argo CD (peut prendre quelques minutes)..."
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n "$ARGOCD_NS"

# =============================================================================
# ETAPE 4.1 : Exposition d'Argo CD via NodePort
# =============================================================================
# Par defaut, Argo CD cree un Service de type ClusterIP (accessible uniquement
# depuis l'interieur du cluster). On le remplace par un Service LoadBalancer
# avec un nodePort fixe (31080) pour y acceder depuis le host via le navigateur.
echo "[4.1/6] Exposition d'Argo CD sur le port $ARGOCD_NODEPORT..."
kubectl delete svc argocd-server -n "$ARGOCD_NS" 2>/dev/null || true
kubectl apply -f "$CONFS_DIR/argocd-server.yaml"

# =============================================================================
# ETAPE 5 : Creation de l'Application Argo CD
# =============================================================================
# On cree une ressource "Application" (CRD d'Argo CD) qui pointe vers le
# repo GitHub. Argo CD va :
#   1. Cloner le repo
#   2. Lire les manifests Kubernetes dedans
#   3. Les appliquer dans le namespace "dev"
#   4. Surveiller le repo en continu → si on push un changement, il re-sync
#
# C'est le coeur du sujet : le continuous deployment via GitOps.
echo "[5/6] Creation de l'Application Argo CD..."
kubectl apply -f "$CONFS_DIR/wil-app.yaml"

# =============================================================================
# ETAPE 5.1 : Attente de la synchronisation
# =============================================================================
# On attend que l'Application soit synchronisee (manifests du repo appliques)
# et que les pods dans "dev" soient prets.
echo "[*] Attente de la synchronisation de l'application..."
kubectl wait --for=jsonpath='{.status.health.status}'=Healthy \
    --timeout=600s "application/$APP_NAME" -n "$ARGOCD_NS" 2>/dev/null || true

echo "[*] Attente que les pods soient prets dans '$DEV_NS'..."
kubectl wait --for=condition=Ready pod --all -n "$DEV_NS" --timeout=600s 2>/dev/null || true

# =============================================================================
# RESULTAT
# =============================================================================
echo ""
echo "[6/6] Deploiement termine !"
echo "========================================="
echo ""
echo "Argo CD Web UI :"
echo "   http://localhost:$ARGOCD_NODEPORT"
echo "   Login : admin"
echo "   Password : make password"
echo ""
echo "Application deployee :"
echo "   http://localhost:8888"
echo "   curl http://localhost:8888"
echo ""
echo "Pour obtenir le mot de passe admin Argo CD :"
echo "   kubectl get secret argocd-initial-admin-secret -n $ARGOCD_NS -o jsonpath=\"{.data.password}\" | base64 -d && echo"
echo ""
echo "Pour changer de version (v1 → v2) :"
echo "   1. Modifier le tag dans le repo GitHub (deployment.yaml)"
echo "   2. git add + commit + push"
echo "   3. Argo CD detecte le changement et synchronise automatiquement"
echo "   4. curl http://localhost:8888 → affiche la nouvelle version"
echo "========================================="
