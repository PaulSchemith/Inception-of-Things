# Makefile P2 - VM unique K3s + déploiement (KVM/QEMU)

GOINFRE    := /goinfre/$(USER)/kvm-p2
IMGS       := $(GOINFRE)/disks
SHARED     := $(GOINFRE)/shared
LOGS       := $(GOINFRE)/logs
PIDS       := $(GOINFRE)/pids
BASE_IMG   := /goinfre/$(USER)/kvm/ubuntu-jammy-base.img
BASE_URL   := https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
SERVER_IP  := 192.168.56.110
# Port SSH différent de p1 pour éviter les conflits si les deux tournent en même temps
SSH_PORT   := 2224
APP_PORT   := 8081
MCAST      := 230.0.0.1:1235
SCRIPTS    := $(CURDIR)/scripts
SSH_KEY    := /goinfre/$(USER)/kvm/ssh/id_rsa
SERVER     := $(USER)S

.PHONY: all destroy setup up deploy status ssh logs

all: destroy setup up

# 1. Détruire la VM existante
destroy:
	@echo "Destruction de la VM..."
	# Stoppe la VM existante en tuant le PID QEMU stocké dans $(PIDS).
	@for pid_file in $(PIDS)/*.pid; do \
		[ -f "$$pid_file" ] || continue; \
		pid=$$(cat "$$pid_file"); \
		kill -0 "$$pid" 2>/dev/null && kill "$$pid" || true; \
		rm -f "$$pid_file"; \
	done
	# Supprime le disque virtuel et l'ISO cloud-init de p2.
	rm -f $(IMGS)/$(SERVER).qcow2 $(GOINFRE)/seed-p2.iso

# 2. Préparer les dossiers et l'image de base
setup:
	@echo "Setup des dossiers..."
	# Prépare les dossiers de travail pour l'image, les logs et les PID.
	mkdir -p $(IMGS) $(SHARED) $(LOGS) $(PIDS)
	# Réutilise la clé SSH et l'image de base générées par p1
	# Génère une clé SSH si elle n'existe pas encore.
	@if [ ! -f $(SSH_KEY) ]; then \
		mkdir -p /goinfre/$(USER)/kvm/ssh; \
		ssh-keygen -t ed25519 -N "" -f $(SSH_KEY) -C "iot-kvm"; \
	fi
	# Télécharge l'image Ubuntu de base si elle est absente.
	@if [ ! -f $(BASE_IMG) ]; then \
		echo "Téléchargement de l'image Ubuntu Jammy..."; \
		wget -q --show-progress -O $(BASE_IMG) $(BASE_URL); \
	fi
	# Copie les manifests K8s dans le dossier partagé pour que la VM y ait accès via /vagrant
	# Rend les manifests disponibles dans /vagrant pour le déploiement.
	cp -r $(CURDIR)/confs $(SHARED)/

# 3. Lancer la VM
up: setup
	@echo "Démarrage VM $(SERVER)..."
	# Génère l'ISO cloud-init avec le script K3s de la VM p2.
	$(SCRIPTS)/gen-seed.sh \
		$(SERVER) $(SERVER_IP) 52:54:00:12:35:01 52:54:00:ab:ce:01 \
		$(GOINFRE)/seed-p2.iso \
		$(SCRIPTS)/setup_k3s.sh \
		$(SSH_KEY).pub
	# Crée le disque de la VM p2.
	qemu-img create -f qcow2 -b $(BASE_IMG) -F qcow2 $(IMGS)/$(SERVER).qcow2 20G
	# Démarre la VM avec SSH, port HTTP et réseau privé.
	qemu-system-x86_64 \
		-name guest=$(SERVER)-p2 \
		-m 1024 -smp 1 -enable-kvm -cpu host \
		-drive file=$(IMGS)/$(SERVER).qcow2,if=virtio \
		-drive file=$(GOINFRE)/seed-p2.iso,media=cdrom \
		-netdev user,id=net0,hostfwd=tcp::$(SSH_PORT)-:22,hostfwd=tcp::$(APP_PORT)-:80 \
		-device virtio-net-pci,netdev=net0,mac=52:54:00:ab:ce:01 \
		-netdev socket,id=net1,mcast=$(MCAST) \
		-device virtio-net-pci,netdev=net1,mac=52:54:00:12:35:01 \
		-virtfs local,path=$(SHARED),mount_tag=shared,security_model=mapped-xattr \
		-nographic -serial file:$(LOGS)/$(SERVER).log \
		2>>$(LOGS)/$(SERVER)-qemu.log & echo $$! > $(PIDS)/$(SERVER).pid
	@echo "$(SERVER) démarrée (SSH: localhost:$(SSH_PORT) | Apps: http://localhost:$(APP_PORT))"

# Réappliquer les manifests sur la VM existante sans la recréer
deploy:
	@echo "Déploiement des manifests..."
	# Recopie les manifests dans le dossier partagé avant application.
	cp -r $(CURDIR)/confs $(SHARED)/
	# Applique les manifests Kubernetes depuis la VM via SSH.
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		-i $(SSH_KEY) -p $(SSH_PORT) vagrant@localhost \
		"sudo kubectl apply -f /vagrant/confs && sudo kubectl get pods && sudo kubectl get ingress"

status:
	@echo "=== Status ==="
	# Vérifie si la VM p2 tourne toujours.
	@if [ -f $(PIDS)/$(SERVER).pid ] && kill -0 $$(cat $(PIDS)/$(SERVER).pid) 2>/dev/null; then \
		echo "$(SERVER): running (PID: $$(cat $(PIDS)/$(SERVER).pid))"; \
	else echo "$(SERVER): stopped"; fi

ssh:
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		-i $(SSH_KEY) -p $(SSH_PORT) vagrant@localhost

logs:
	tail -f $(LOGS)/$(SERVER).log
