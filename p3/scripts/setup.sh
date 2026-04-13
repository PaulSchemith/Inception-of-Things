#!/bin/bash
# =============================================================================
# P3 Setup Script - Installation des prerequis pour K3d + Argo CD
# =============================================================================
#
# CONTEXTE DU SUJET :
#   P3 n'utilise plus Vagrant/VMs comme P1/P2. On travaille directement sur
#   la machine hote avec K3d, qui est un wrapper autour de K3s.
#
#   K3s  = distribution Kubernetes legere, installée nativement sur un OS
#   K3d  = lance K3s a l'interieur de conteneurs Docker (pas de VM)
#          → plus rapide a demarrer, parfait pour du dev/test local
#
#   Ce script installe tous les outils necessaires :
#   - Docker        : moteur de conteneurs, requis par K3d
#   - K3d           : cree des clusters K3s dans Docker
#   - kubectl       : CLI pour interagir avec Kubernetes
#   - argocd CLI    : CLI pour interagir avec Argo CD (utile en demo)
#
# UTILISATION :
#   make setup   (ou bash scripts/setup.sh)
#
# =============================================================================
set -e

echo "========================================="
echo "  P3 Setup - K3d + Argo CD prerequisites"
echo "========================================="

# --- 1. Mise a jour des paquets apt ---
# Necessaire pour avoir les dernieres versions des dependances
echo "[1/7] Mise a jour du cache apt..."
sudo apt update -y

# --- 2. Installation des dependances de base ---
# curl       : telecharger les scripts d'installation
# git        : cloner les repos (utilise par Argo CD)
# ca-certs   : certificats SSL pour les connexions HTTPS
# jq         : parser du JSON en ligne de commande (utile pour debug kubectl)
echo "[2/7] Installation des dependances de base..."
sudo apt install -y curl git apt-transport-https ca-certificates gnupg lsb-release jq

# --- 3. Installation de Docker ---
# K3d lance des conteneurs Docker pour simuler des nodes Kubernetes.
# Sans Docker, K3d ne peut pas fonctionner.
# On ajoute l'utilisateur au groupe docker pour eviter de devoir utiliser sudo.
echo "[3/7] Installation de Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker "$USER"
    echo "Docker installe. Reconnexion peut etre necessaire (newgrp docker)."
else
    echo "Docker deja installe."
fi

# --- 4. Correction de la delegation cgroup ---
# Sur certains systemes (VM imbriquees, LXC, WSL...), Docker ne delegue pas
# le controleur "cpu" aux conteneurs. K3s a besoin du cgroup cpu pour
# fonctionner correctement. Sans ca, k3s crash avec :
#   "failed to find cpu cgroup (v2)"
#
# On active la delegation de tous les controleurs necessaires dans le
# sous-arbre cgroup du service Docker.
echo "[4/7] Verification de la delegation cgroup pour Docker..."
fix_cgroup_delegation() {
    # Verifie si le fichier de controle existe (cgroups v2 uniquement)
    local subtree="/sys/fs/cgroup/system.slice/docker.service/cgroup.subtree_control"
    if [ -f "$subtree" ]; then
        local current
        current=$(cat "$subtree" 2>/dev/null || true)
        if ! echo "$current" | grep -qw cpu; then
            echo "   Delegation cpu manquante, tentative de correction..."
            sudo sh -c "echo '+cpu +cpuset +io +memory +pids' > $subtree" 2>/dev/null || true
            # On redemarre Docker pour appliquer les changements
            sudo systemctl restart docker 2>/dev/null || true
            sleep 2
            echo "   Delegation cgroup corrigee et Docker redemarre."
        else
            echo "   Delegation cgroup OK (cpu present)."
        fi
    else
        # Sur certains systemes, le chemin est different
        # On tente aussi via le parent
        local parent="/sys/fs/cgroup/cgroup.subtree_control"
        if [ -f "$parent" ]; then
            local current
            current=$(cat "$parent" 2>/dev/null || true)
            if ! echo "$current" | grep -qw cpu; then
                echo "   Tentative de correction via $parent..."
                sudo sh -c "echo '+cpu +cpuset +io +memory +pids' > $parent" 2>/dev/null || true
                sudo systemctl restart docker 2>/dev/null || true
                sleep 2
            fi
        fi
        echo "   Delegation cgroup verifiee."
    fi
}
fix_cgroup_delegation

# --- 5. Installation de K3d ---
# K3d cree des clusters Kubernetes (K3s) a l'interieur de conteneurs Docker.
# Avantage par rapport a K3s natif : pas besoin de VM, demarrage en secondes.
echo "[5/7] Installation de K3d..."
if ! command -v k3d &> /dev/null; then
    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
else
    echo "K3d deja installe."
fi

# --- 6. Installation de kubectl ---
# kubectl est le CLI officiel de Kubernetes pour :
# - creer/modifier/supprimer des ressources (pods, services, namespaces...)
# - consulter l'etat du cluster
# - appliquer des fichiers YAML de configuration
echo "[6/7] Installation de kubectl..."
if ! command -v kubectl &> /dev/null; then
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
else
    echo "kubectl deja installe."
fi

# --- 7. Installation du CLI Argo CD ---
# Le CLI argocd permet de :
# - se connecter au serveur Argo CD
# - lister/syncer les applications
# - debugger les problemes de deploiement
# Pas strictement requis (on peut tout faire via kubectl), mais utile en demo.
echo "[7/7] Installation du CLI Argo CD..."
if ! command -v argocd &> /dev/null; then
    sudo curl -sSL -o /usr/local/bin/argocd \
        https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
    sudo chmod +x /usr/local/bin/argocd
else
    echo "argocd deja installe."
fi

echo ""
echo "Installation terminee !"
echo ""
echo "Si Docker vient d'etre installe, il faut recharger le groupe :"
echo "   newgrp docker"
echo "   (ou se deconnecter/reconnecter)"
echo ""
echo "Prochaine etape : make up  (deploie le cluster + Argo CD)"
