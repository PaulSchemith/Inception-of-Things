#!/bin/bash
# setup_worker.sh - Installe K3s en mode "agent" sur la VM loginSW
#
# Ce script est embarqué dans l'ISO cloud-init par gen-seed.sh et exécuté
# automatiquement au premier boot de la VM worker, en tant que root.
# Le worker rejoint le cluster créé par le serveur.

# set -eux :
# -e = arrête si une commande échoue
# -u = arrête si une variable non définie est utilisée
# -x = affiche chaque commande avant de l'exécuter (visible dans les logs cloud-init)
set -eux

# === INSTALLATION DES DÉPENDANCES ===
apt-get update -y
apt-get install -y curl

# === IP DU SERVEUR K3s ===
# Le worker a besoin de connaître l'adresse du control plane pour s'y connecter.
# On utilise l'IP fixe sur le réseau privé inter-VMs (192.168.56.0/24),
# configuré par netplan via l'interface multicast QEMU.
SERVER_IP="192.168.56.110"

# === ATTENTE DU TOKEN ===
# Le token est créé par setup_server.sh et copié dans /vagrant/node-token.
# /vagrant est le dossier partagé 9p entre host et VMs (monté par cloud-init).
# On boucle jusqu'à ce que le fichier apparaisse = le serveur a fini son installation.
# (Le Makefile attend aussi côté host, mais cette boucle est une sécurité côté VM)
echo "Waiting for K3s token from server..."
while [ ! -f /vagrant/node-token ]; do
  sleep 5
done

# Lit le token depuis le fichier partagé
K3S_TOKEN=$(cat /vagrant/node-token)

# === ATTENTE QUE LE SERVEUR SOIT JOIGNABLE ===
# Même si le token existe, l'API server K3s doit être prêt à accepter des connexions
# sur le port 6443 (port HTTPS de l'API Kubernetes).
# curl -k = ignore la vérification du certificat TLS (certificat auto-signé par K3s)
# curl -s = silencieux (pas d'affichage de progression)
until curl -k -s https://$SERVER_IP:6443 >/dev/null; do
  echo "Waiting for K3s server to be ready..."
  sleep 5
done

# === INSTALLATION DE K3S EN MODE AGENT ===
# K3S_URL  = adresse de l'API server du control plane
# K3S_TOKEN = token d'authentification pour rejoindre le cluster
# Le script d'install détecte ces variables et installe K3s en mode agent
# (= worker node : exécute des pods mais ne gère pas le cluster)
curl -sfL https://get.k3s.io | K3S_URL="https://$SERVER_IP:6443" K3S_TOKEN="$K3S_TOKEN" sh -

echo "Worker node installation complete"
