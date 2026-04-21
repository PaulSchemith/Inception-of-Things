#!/bin/bash
# setup_k3s.sh - Installe K3s server + déploie les 3 apps sur la VM unique de p2
set -eux

# === DÉPENDANCES ===
apt-get update -y
apt-get install -y curl

# === INSTALLATION K3s SERVER ===
# Une seule VM fait tout : control plane + worker.
curl -sfL https://get.k3s.io | sh -

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# === ATTENTE QUE LE NODE SOIT READY ===
until kubectl get nodes >/dev/null 2>&1; do sleep 2; done

# === DÉPLOIEMENT DES MANIFESTS ===
# Les manifests (app1.yaml, app2.yaml, app3.yaml, ingress.yaml) sont dans
# /vagrant/confs, accessible via le dossier partagé virtiofs.
kubectl apply -f /vagrant/confs

kubectl get pods
kubectl get ingress
