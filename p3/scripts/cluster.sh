#!/bin/bash
set -e

# Configuration
CLUSTER_NAME="iot-cluster"
PROJECT_DIR="/goinfre/pschemit/Inception-of-Things"
KUBE_DIR="$PROJECT_DIR/.kube"

# 1. Configuration de l'environnement
echo "[+] Configuration de l'environnement..."
mkdir -p "$KUBE_DIR"
rm -rf ~/.kube 2>/dev/null || true
ln -sf "$KUBE_DIR" ~/.kube

# 2. Nettoyage des ressources existantes
echo "[+] Nettoyage des ressources existantes..."
k3d cluster delete "$CLUSTER_NAME" 2>/dev/null || true
docker ps -aq --filter "name=k3d-$CLUSTER_NAME" | xargs docker rm -f 2>/dev/null || true
docker network prune -f
docker volume prune -f

# 3. Création du cluster avec K3s v1.19.16 (sans cgroups v2)
echo "[+] Création du cluster K3d avec K3s v1.19.16-k3s1 (sans cgroups v2)..."
k3d cluster create "$CLUSTER_NAME" \
  --image docker.io/rancher/k3s:v1.18.20-k3s1 \
  --api-port 6443 \
  --servers 1 \
  --agents 0 \
  --k3s-arg "--disable=traefik@server:0" \
  --port "8080:80@loadbalancer" \
  --port "8443:443@loadbalancer" \
  --wait

# 4. Configuration de kubectl
echo "[+] Configuration de kubectl..."
export KUBECONFIG="$KUBE_DIR/config"
k3d kubeconfig merge "$CLUSTER_NAME" --kubeconfig-merge-default --kubeconfig-switch-context

# 5. Vérification du cluster
echo "[+] Vérification du cluster..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s
kubectl get nodes -o wide
kubectl get pods -A

# 6. Message de succès
echo ""
echo "✅ Cluster K3d '$CLUSTER_NAME' créé avec succès !"
echo ""
echo "📝 Pour utiliser kubectl dans d'autres terminaux :"
echo "   export KUBECONFIG=$KUBE_DIR/config"
echo ""
echo "💡 Ajoutez cette ligne à votre ~/.zshrc pour persister la configuration :"
echo "   echo 'export KUBECONFIG=$KUBE_DIR/config' >> ~/.zshrc"
