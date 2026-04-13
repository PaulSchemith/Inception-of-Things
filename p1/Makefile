# Makefile pour P1 - VM + K3s (KVM/QEMU)

GOINFRE    := /goinfre/$(USER)/kvm
IMGS       := $(GOINFRE)/disks
SHARED     := $(GOINFRE)/shared
LOGS       := $(GOINFRE)/logs
PIDS       := $(GOINFRE)/pids
BASE_IMG   := $(GOINFRE)/ubuntu-jammy-base.img
BASE_URL   := https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
SERVER_IP  := 192.168.56.110
WORKER_IP  := 192.168.56.111
MCAST      := 230.0.0.1:1234
SCRIPTS    := $(CURDIR)/scripts
SSH_KEY    := $(GOINFRE)/ssh/id_rsa
SERVER     := $(USER)S
WORKER     := $(USER)SW

.PHONY: all destroy setup up-server up-agent status ssh-server ssh-worker logs-server logs-worker

all: destroy setup up-server up-agent

# 1. Détruire les VMs existantes
destroy:
	@echo "Destruction des VMs..."
	@for pid_file in $(PIDS)/*.pid; do \
		[ -f "$$pid_file" ] || continue; \
		pid=$$(cat "$$pid_file"); \
		kill -0 "$$pid" 2>/dev/null && kill "$$pid" || true; \
		rm -f "$$pid_file"; \
	done
	rm -f $(IMGS)/$(SERVER).qcow2 $(IMGS)/$(WORKER).qcow2
	rm -f $(GOINFRE)/seed-server.iso $(GOINFRE)/seed-worker.iso
	rm -f $(SHARED)/node-token

# 2. Créer les dossiers et télécharger l'image de base
setup:
	@echo "Setup des dossiers..."
	mkdir -p $(IMGS) $(SHARED) $(LOGS) $(PIDS) $(GOINFRE)/ssh
	@if [ ! -f $(SSH_KEY) ]; then \
		ssh-keygen -t ed25519 -N "" -f $(SSH_KEY) -C "p1-iot"; \
	fi
	@if [ ! -f $(BASE_IMG) ]; then \
		echo "Téléchargement de l'image Ubuntu Jammy..."; \
		wget -q --show-progress -O $(BASE_IMG) $(BASE_URL); \
	fi

# 3. Démarrer la VM serveur
up-server: setup
	@echo "Démarrage VM serveur $(SERVER)..."
	$(SCRIPTS)/gen-seed.sh \
		$(SERVER) $(SERVER_IP) 52:54:00:12:34:01 52:54:00:ab:cd:01 \
		$(GOINFRE)/seed-server.iso \
		$(SCRIPTS)/setup_server.sh \
		$(SSH_KEY).pub
	qemu-img create -f qcow2 -b $(BASE_IMG) -F qcow2 $(IMGS)/$(SERVER).qcow2 20G
	qemu-system-x86_64 \
		-name guest=$(SERVER) \
		-m 1024 -smp 1 -enable-kvm -cpu host \
		-drive file=$(IMGS)/$(SERVER).qcow2,if=virtio \
		-drive file=$(GOINFRE)/seed-server.iso,media=cdrom \
		-netdev user,id=net0,hostfwd=tcp::2222-:22 \
		-device virtio-net-pci,netdev=net0,mac=52:54:00:ab:cd:01 \
		-netdev socket,id=net1,mcast=$(MCAST) \
		-device virtio-net-pci,netdev=net1,mac=52:54:00:12:34:01 \
		-virtfs local,path=$(SHARED),mount_tag=shared,security_model=mapped-xattr \
		-nographic -serial file:$(LOGS)/$(SERVER).log \
		2>>$(LOGS)/$(SERVER)-qemu.log & echo $$! > $(PIDS)/$(SERVER).pid
	@echo "$(SERVER) démarrée (SSH: localhost:2222 | logs: make logs-server)"

# 4. Attendre le token puis démarrer le worker
up-agent:
	@echo "En attente du node-token serveur..."
	@while [ ! -f $(SHARED)/node-token ]; do sleep 5; done
	@echo "Token disponible, démarrage VM worker $(WORKER)..."
	$(SCRIPTS)/gen-seed.sh \
		$(WORKER) $(WORKER_IP) 52:54:00:12:34:02 52:54:00:ab:cd:02 \
		$(GOINFRE)/seed-worker.iso \
		$(SCRIPTS)/setup_worker.sh \
		$(SSH_KEY).pub
	qemu-img create -f qcow2 -b $(BASE_IMG) -F qcow2 $(IMGS)/$(WORKER).qcow2 10G
	qemu-system-x86_64 \
		-name guest=$(WORKER) \
		-m 512 -smp 1 -enable-kvm -cpu host \
		-drive file=$(IMGS)/$(WORKER).qcow2,if=virtio \
		-drive file=$(GOINFRE)/seed-worker.iso,media=cdrom \
		-netdev user,id=net0,hostfwd=tcp::2223-:22 \
		-device virtio-net-pci,netdev=net0,mac=52:54:00:ab:cd:02 \
		-netdev socket,id=net1,mcast=$(MCAST) \
		-device virtio-net-pci,netdev=net1,mac=52:54:00:12:34:02 \
		-virtfs local,path=$(SHARED),mount_tag=shared,security_model=mapped-xattr \
		-nographic -serial file:$(LOGS)/$(WORKER).log \
		2>>$(LOGS)/$(WORKER)-qemu.log & echo $$! > $(PIDS)/$(WORKER).pid
	@echo "$(WORKER) démarrée (SSH: localhost:2223 | logs: make logs-worker)"

status:
	@echo "=== Status des VMs ==="
	@if [ -f $(PIDS)/$(SERVER).pid ] && kill -0 $$(cat $(PIDS)/$(SERVER).pid) 2>/dev/null; then \
		echo "$(SERVER):  running (PID: $$(cat $(PIDS)/$(SERVER).pid))"; \
	else echo "$(SERVER):  stopped"; fi
	@if [ -f $(PIDS)/$(WORKER).pid ] && kill -0 $$(cat $(PIDS)/$(WORKER).pid) 2>/dev/null; then \
		echo "$(WORKER): running (PID: $$(cat $(PIDS)/$(WORKER).pid))"; \
	else echo "$(WORKER): stopped"; fi

ssh-server:
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $(SSH_KEY) -p 2222 vagrant@localhost

ssh-worker:
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $(SSH_KEY) -p 2223 vagrant@localhost

logs-server:
	tail -f $(LOGS)/$(SERVER).log

logs-worker:
	tail -f $(LOGS)/$(WORKER).log
