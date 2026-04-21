#!/bin/bash
# setup_server.sh - Installe K3s en mode "server" (control plane) sur la VM loginS
set -eux

# === INSTALLATION DES DÉPENDANCES ===
apt-get update -y
apt-get install -y curl

# === INSTALLATION DE K3S EN MODE SERVER ===
# Sans argument, le script d'install crée un "server" = control plane Kubernetes.
curl -sfL https://get.k3s.io | sh -

# === SYMLINKS POUR LES OUTILS K3s ===
# K3s installe ses binaires dans /usr/local/bin.
# On crée des liens symboliques dans /usr/bin pour la compatibilité.
ln -sf /usr/local/bin/kubectl /usr/bin/kubectl
ln -sf /usr/local/bin/crictl /usr/bin/crictl
ln -sf /usr/local/bin/ctr    /usr/bin/ctr

# === ATTENTE QUE K3s SOIT OPÉRATIONNEL ===
# K3s démarre en arrière-plan — on boucle jusqu'à ce que l'API server réponde.
until kubectl get nodes >/dev/null 2>&1; do sleep 5; done

# === PARTAGE DU TOKEN AVEC LE WORKER ===
# /vagrant est monté via virtiofs (dossier partagé host<->VMs).
# Le worker attend ce fichier pour rejoindre le cluster.
cp /var/lib/rancher/k3s/server/node-token /vagrant/node-token
chmod 644 /vagrant/node-token

kubectl get nodes
