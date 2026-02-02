# Makefile pour P1 - VM + K3s

# Variables
VAGRANT_DIR := $(CURDIR)
GOINFRE_DIR := /goinfre/$(USER)/VirtualBoxVMs
SERVER_IP := 192.168.56.110

.PHONY: all destroy setup configure-vbox up-server up-agent

all: destroy setup configure-vbox up-server up-agent

# 1. Détruire toutes les VMs existantes
destroy:
	@echo "🗑️  Destruction des VMs existantes..."
	vagrant destroy -f || true

# 2. Créer le dossier /goinfre si nécessaire
setup:
	@echo "📁 Création du dossier /goinfre pour VirtualBox..."
	mkdir -p $(GOINFRE_DIR)

# 3. Configurer VirtualBox pour utiliser ce dossier
configure-vbox:
	@echo "⚙️  Configuration de VirtualBox..."
	VBoxManage setproperty machinefolder $(GOINFRE_DIR)
	@echo "💡 Vérification de la configuration:"
	VBoxManage list systemproperties | grep "Default machine folder"

up-server:
	@echo "🚀 Démarrage de la VM serveur..."
	cd $(VAGRANT_DIR) && vagrant up loginS

up-agent:
	@echo "🚀 Démarrage des VMs agents..."
	cd $(VAGRANT_DIR) && vagrant up loginSW

