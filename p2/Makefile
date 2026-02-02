# Makefile P2 - VM unique K3s + déploiement
SHELL := /bin/bash
VAGRANT := vagrant
VAGRANT_DIR := $(CURDIR)

.PHONY: up destroy deploy

# Lancer la VM et provisionner K3s + manifests
up:
	@echo "🚀 Démarrage de la VM..."
	cd $(VAGRANT_DIR) && $(VAGRANT) up

# Détruire la VM
destroy:
	@echo "🗑️ Destruction de la VM..."
	cd $(VAGRANT_DIR) && $(VAGRANT) destroy -f

# Si besoin, réappliquer les manifests sur la VM existante
deploy:
	@echo "⌛ Déploiement des manifests..."
	cd $(VAGRANT_DIR) && $(VAGRANT) ssh default -c "\
		cd /home/vagrant/confs && \
		sudo kubectl apply -f . && \
		echo 'Pods et ingress appliqués:' && \
		sudo kubectl get pods && \
		sudo kubectl get ingress"
