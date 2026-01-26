#!/bin/bash
set -eux

# Mettre à jour et installer curl
apt-get update -y
apt-get install -y curl

# Installer K3s en mode serveur
curl -sfL https://get.k3s.io | sh -

# Créer des symlinks pour kubectl, crictl, ctr
ln -sf /usr/local/bin/kubectl /usr/bin/kubectl
ln -sf /usr/local/bin/crictl /usr/bin/crictl
ln -sf /usr/local/bin/ctr /usr/bin/ctr

# Attendre que K3s soit pleinement opérationnel
echo "Waiting for K3s server to be ready..."
until sudo kubectl get nodes >/dev/null 2>&1; do
  sleep 5
done

# Copier le token dans le dossier partagé pour le worker
sudo cp /var/lib/rancher/k3s/server/node-token /vagrant/node-token
sudo chmod 644 /vagrant/node-token

# Vérification finale
echo "Server node installation complete. Cluster nodes:"
sudo kubectl get nodes
