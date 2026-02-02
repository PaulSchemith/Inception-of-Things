#!/bin/bash
set -e

CLUSTER_NAME="iot-cluster"
PROJECT_DIR="/goinfre/pschemit/Inception-of-Things"
KUBE_DIR="$PROJECT_DIR/.kube"

echo "[+] Configuration de l'environnement dans $PROJECT_DIR..."
# 1. Crée le dossier .kube dans le projet
mkdir -p "$KUBE_DIR"

# 2. Crée un lien symbolique depuis ton home
ln -sf "$KUBE_DIR" ~/.kube

# 3. Vérifie la config Docker
echo "[+] Vérification de Docker Root Dir..."
docker info | grep "Docker Root Dir"

echo "[+] Suppression de l'ancien cluster (s'il existe)..."
k3d cluster delete $CLUSTER_NAME 2>/dev/null || true

echo "[+] Nettoyage Docker..."
docker system prune -f

echo "[+] Création du cluster k3d..."
k3d cluster create $CLUSTER_NAME \
  --api-port 6443 \
  --servers 1 \
  --agents 0 \
  --k3s-arg "--disable=traefik@server:0" \
  --port "8080:80@loadbalancer" \
  --port "8443:443@loadbalancer"

echo "[+] Configuration kubectl..."
export KUBECONFIG="$KUBE_DIR/config"
k3d kubeconfig merge $CLUSTER_NAME --kubeconfig-merge-default --kubeconfig-switch-context

echo "[+] Attente que le cluster soit prêt..."
sleep 10

echo "[+] Test de la connexion..."
kubectl get nodes -o wide

echo ""
echo "✅ Cluster créé avec succès !"
echo ""
echo "⚠️  IMPORTANT : Pour utiliser kubectl dans d'autres terminaux, exécute :"
echo "    export KUBECONFIG=$KUBE_DIR/config"
echo ""
echo "💡 Tu peux l'ajouter automatiquement à ton ~/.zshrc :"
echo "    echo 'export KUBECONFIG=$KUBE_DIR/config' >> ~/.zshrc"
```

**Structure du projet après exécution :**
```
/goinfre/pschemit/Inception-of-Things/
├── .kube/
│   └── config          # Ton kubeconfig
├── p3/
│   └── scripts/
│       └── cluster.sh  # Ce script
└── ...