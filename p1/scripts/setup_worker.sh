#!/bin/bash
# setup_worker.sh - Installe K3s en mode "agent" sur la VM loginSW
set -eux

# === INSTALLATION DES DÉPENDANCES ===
apt-get update -y
apt-get install -y curl

# === IP DU SERVEUR K3s ===
# IP fixe du control plane sur le réseau privé inter-VMs (192.168.56.0/24).
SERVER_IP="192.168.56.110"

# === ATTENTE DU TOKEN ===
# Le token est déposé par setup_server.sh dans /vagrant (monté via virtiofs).
# On boucle jusqu'à ce que le fichier apparaisse = le serveur a fini son installation.
until [ -f /vagrant/node-token ]; do sleep 5; done
K3S_TOKEN=$(cat /vagrant/node-token)

# === ATTENTE QUE L'API SERVER SOIT JOIGNABLE ===
# K3s écoute sur le port 6443 (HTTPS). -k ignore le certificat auto-signé.
until curl -k -s "https://$SERVER_IP:6443" >/dev/null; do sleep 5; done

# === INSTALLATION DE K3S EN MODE AGENT ===
# K3S_URL   = adresse de l'API server du control plane
# K3S_TOKEN = token d'authentification pour rejoindre le cluster
curl -sfL https://get.k3s.io | K3S_URL="https://$SERVER_IP:6443" K3S_TOKEN="$K3S_TOKEN" sh -
