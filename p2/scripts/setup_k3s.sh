#!/bin/bash
set -eux

apt-get update -y
apt-get install -y curl

# Install K3s server
curl -sfL https://get.k3s.io | sh -

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Wait for node ready
until kubectl get nodes; do
  sleep 2
done

# Enable ingress (Traefik is installed by default in k3s)
kubectl apply -f /vagrant/confs
