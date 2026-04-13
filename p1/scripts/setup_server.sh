#!/bin/bash
# setup_server.sh - Installe K3s en mode "server" (control plane) sur la VM loginS
#
# Ce script est embarqué dans l'ISO cloud-init par gen-seed.sh et exécuté
# automatiquement au premier boot de la VM serveur, en tant que root.
# Il correspond à la partie "provision" que faisait Vagrant.

# set -eux :
# -e = arrête si une commande échoue
# -u = arrête si une variable non définie est utilisée
# -x = affiche chaque commande avant de l'exécuter (visible dans les logs cloud-init)
set -eux

# === INSTALLATION DES DÉPENDANCES ===
apt-get update -y
apt-get install -y curl  # curl est nécessaire pour télécharger le script d'install K3s

# === INSTALLATION DE K3S EN MODE SERVER ===
# K3s est une distribution Kubernetes légère (Rancher).
# Sans argument, le script d'install crée un "server" = control plane Kubernetes.
# Le server gère l'API, le scheduler, et peut aussi exécuter des pods.
curl -sfL https://get.k3s.io | sh -

# === SYMLINKS POUR LES OUTILS K3s ===
# K3s installe ses binaires dans /usr/local/bin mais certains outils s'attendent
# à les trouver dans /usr/bin. On crée des liens symboliques pour la compatibilité.
# - kubectl : CLI pour interagir avec le cluster Kubernetes
# - crictl  : CLI pour inspecter les containers (Container Runtime Interface)
# - ctr     : CLI bas niveau pour containerd (le runtime de containers)
ln -sf /usr/local/bin/kubectl /usr/bin/kubectl
ln -sf /usr/local/bin/crictl /usr/bin/crictl
ln -sf /usr/local/bin/ctr /usr/bin/ctr

# === ATTENTE QUE K3s SOIT OPÉRATIONNEL ===
# K3s démarre en arrière-plan. On boucle jusqu'à ce que "kubectl get nodes"
# réponde sans erreur = l'API server est prêt à accepter des connexions.
echo "Waiting for K3s server to be ready..."
until sudo kubectl get nodes >/dev/null 2>&1; do
  sleep 5
done

# === PARTAGE DU TOKEN AVEC LE WORKER ===
# K3s génère un token secret à l'install. Le worker en a besoin pour
# s'authentifier et rejoindre le cluster (comme un mot de passe de cluster).
# On le copie dans /vagrant (dossier partagé 9p entre host et VMs) pour que
# le Makefile puisse détecter qu'il est prêt, et que le worker puisse le lire.
sudo cp /var/lib/rancher/k3s/server/node-token /vagrant/node-token
sudo chmod 644 /vagrant/node-token  # lisible par tous (le worker le lit sans être root)

# === VÉRIFICATION FINALE ===
echo "Server node installation complete. Cluster nodes:"
sudo kubectl get nodes
