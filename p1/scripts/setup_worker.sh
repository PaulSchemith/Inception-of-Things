#!/bin/bash
set -eux

# Dépendances
apt-get update -y
apt-get install -y curl

# IP du serveur K3s
SERVER_IP="192.168.56.110"

# Attendre que le token soit disponible dans le dossier partagé
echo "Waiting for K3s token from server..."
while [ ! -f /vagrant/node-token ]; do
  sleep 5
done

# Lire le token
K3S_TOKEN=$(cat /vagrant/node-token)

# Vérifier que le serveur est joignable avant de lancer l'agent
until curl -k -s https://$SERVER_IP:6443 >/dev/null; do
  echo "Waiting for K3s server to be ready..."
  sleep 5
done

# Installer K3s en mode agent
curl -sfL https://get.k3s.io | K3S_URL="https://$SERVER_IP:6443" K3S_TOKEN="$K3S_TOKEN" sh -

echo "Worker node installation complete"
