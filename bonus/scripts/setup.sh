#!/bin/bash
# =============================================================================
# Bonus Setup Script - Prerequis supplementaires pour GitLab + Argo CD
# =============================================================================
#
# CONTEXTE DU SUJET BONUS :
#   Le bonus etend P3 en remplacant GitHub par une instance GitLab locale.
#   L'objectif est d'avoir une chaine CI/CD entierement locale :
#
#   GitLab local (namespace gitlab)
#       ↓ contient les manifests K8s
#   Argo CD (namespace argocd) surveille GitLab en continu
#       ↓ detecte les changements, applique dans le cluster
#   Application wil42/playground (namespace dev)
#       ↓ accessible sur localhost:8888
#
# OUTILS SUPPLEMENTAIRES PAR RAPPORT A P3 :
#   - Helm : gestionnaire de packages Kubernetes
#     Helm utilise des "charts" = archives contenant des templates de manifests K8s
#     On l'utilise pour deployer GitLab (le chart officiel est tres complet)
#   - curl + jq : pour interagir avec l'API GitLab et automatiser la config
#
# POURQUOI HELM POUR GITLAB ?
#   GitLab est compose de nombreux services (webservice, sidekiq, gitaly, redis,
#   postgres, minio...). Tout configurer a la main en YAML serait tres long.
#   Le chart Helm officiel encapsule toute cette complexite et permet de
#   configurer GitLab via un seul fichier de valeurs (gitlab-values.yaml).
#
# UTILISATION :
#   make setup   (ou bash scripts/setup.sh)
#
# =============================================================================
set -e

echo "========================================="
echo "  Bonus Setup - GitLab + K3d + Argo CD"
echo "========================================="

# --- 1. Outils de base (memes que P3) ---
echo "[1/5] Mise a jour apt et dependances..."
sudo apt update -y
sudo apt install -y curl git apt-transport-https ca-certificates gnupg lsb-release jq

# --- 2. Docker (requis par K3d) ---
echo "[2/5] Docker..."
if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker "$USER"
    echo "Docker installe. Reconnecte-toi ou execute: newgrp docker"
else
    echo "Docker deja installe."
fi

# --- 3. K3d ---
echo "[3/5] K3d..."
if ! command -v k3d &>/dev/null; then
    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
else
    echo "K3d deja installe."
fi

# --- 4. kubectl ---
echo "[4/5] kubectl..."
if ! command -v kubectl &>/dev/null; then
    curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl && sudo mv kubectl /usr/local/bin/
else
    echo "kubectl deja installe."
fi

# --- 5. Helm ---
# Helm est le gestionnaire de packages pour Kubernetes.
# Un "chart" Helm = un ensemble de templates YAML parametrables.
# "helm install" instancie ces templates avec tes valeurs et les applique au cluster.
echo "[5/5] Helm..."
if ! command -v helm &>/dev/null; then
    # Script d'installation officiel Helm
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
else
    echo "Helm deja installe."
fi

# Ajoute le repo officiel GitLab pour Helm
# Cela permet de faire "helm install gitlab/gitlab ..."
echo "Ajout du repo Helm GitLab..."
helm repo add gitlab https://charts.gitlab.io/ 2>/dev/null || true
helm repo update

# Correction delegation cgroup (meme probleme que P3)
echo "Verification cgroup..."
SUBTREE="/sys/fs/cgroup/system.slice/docker.service/cgroup.subtree_control"
if [ -f "$SUBTREE" ]; then
    current=$(cat "$SUBTREE" 2>/dev/null || true)
    if ! echo "$current" | grep -qw cpu; then
        sudo sh -c "echo '+cpu +cpuset +io +memory +pids' > $SUBTREE" 2>/dev/null || true
        sudo systemctl restart docker 2>/dev/null || true
        sleep 2
        echo "   Delegation cgroup corrigee."
    else
        echo "   Delegation cgroup OK."
    fi
fi

echo ""
echo "Setup termine ! Prochaine etape : make up"
