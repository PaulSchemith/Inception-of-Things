#!/bin/bash
# setup_k3s.sh - Installe K3s server + déploie les apps Kubernetes sur la VM unique de p2
#
# Ce script est embarqué dans l'ISO cloud-init par gen-seed.sh et exécuté
# automatiquement au premier boot. Il correspond au "provision" du Vagrantfile original.

# set -eux : arrête sur erreur, variable indéfinie, affiche les commandes
set -eux

# === DÉPENDANCES ===
apt-get update -y
apt-get install -y curl

# === INSTALLATION K3s SERVER ===
# Mode server = control plane Kubernetes.
# Pour p2, une seule VM fait tout : controller + worker.
curl -sfL https://get.k3s.io | sh -

# La config kubectl de K3s est dans ce fichier. On l'exporte pour que
# les commandes kubectl suivantes fonctionnent sans sudo -E.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# === ATTENTE QUE LE NODE SOIT READY ===
# K3s démarre en arrière-plan, on boucle jusqu'à ce que le node réponde.
until kubectl get nodes; do
  sleep 2
done

# === DÉPLOIEMENT DES MANIFESTS ===
# Les manifests (app1.yaml, app2.yaml, app3.yaml, ingress.yaml) sont dans /vagrant/confs.
# /vagrant est le dossier partagé 9p monté par cloud-init depuis le host
# (correspond à goinfre/.../shared/ sur le host, où le Makefile a copié confs/).
kubectl apply -f /vagrant/confs

echo "Déploiement terminé."
kubectl get pods
kubectl get ingress
