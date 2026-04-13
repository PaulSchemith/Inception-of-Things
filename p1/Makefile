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

.PHONY: all destroy setup up-server up-agent status ssh-server ssh-worker logs-server logs-worker

all: destroy setup up-server up-agent

# 1. Détruire les VMs existantes
destroy:
	@echo "Destruction des VMs..."
	@if [ -f $(PIDS)/loginS.pid ] && kill -0 $$(cat $(PIDS)/loginS.pid) 2>/dev/null; then \
		kill $$(cat $(PIDS)/loginS.pid); fi
	@if [ -f $(PIDS)/loginSW.pid ] && kill -0 $$(cat $(PIDS)/loginSW.pid) 2>/dev/null; then \
		kill $$(cat $(PIDS)/loginSW.pid); fi
	rm -f $(PIDS)/loginS.pid $(PIDS)/loginSW.pid
	rm -f $(IMGS)/loginS.qcow2 $(IMGS)/loginSW.qcow2
	rm -f $(GOINFRE)/seed-server.iso $(GOINFRE)/seed-worker.iso
	rm -f $(SHARED)/node-token

# 2. Créer les dossiers et télécharger l'image de base
setup:
	@echo "Setup des dossiers..."
	mkdir -p $(IMGS) $(SHARED) $(LOGS) $(PIDS)
	@if [ ! -f $(BASE_IMG) ]; then \
		echo "Téléchargement de l'image Ubuntu Jammy..."; \
		wget -q --show-progress -O $(BASE_IMG) $(BASE_URL); \
	fi

# 3. Démarrer la VM serveur
up-server: setup
	@echo "Démarrage VM serveur loginS..."
	$(SCRIPTS)/gen-seed.sh \
		loginS $(SERVER_IP) 52:54:00:12:34:01 52:54:00:ab:cd:01 \
		$(GOINFRE)/seed-server.iso \
		$(SCRIPTS)/setup_server.sh
	qemu-img create -f qcow2 -b $(BASE_IMG) -F qcow2 $(IMGS)/loginS.qcow2 20G
	qemu-system-x86_64 \
		-name guest=loginS \
		-m 1024 -smp 1 -enable-kvm -cpu host \
		-drive file=$(IMGS)/loginS.qcow2,if=virtio \
		-drive file=$(GOINFRE)/seed-server.iso,media=cdrom \
		-netdev user,id=net0,hostfwd=tcp::2222-:22 \
		-device virtio-net-pci,netdev=net0,mac=52:54:00:ab:cd:01 \
		-netdev socket,id=net1,mcast=$(MCAST) \
		-device virtio-net-pci,netdev=net1,mac=52:54:00:12:34:01 \
		-virtfs local,path=$(SHARED),mount_tag=shared,security_model=mapped-xattr \
		-nographic -serial file:$(LOGS)/loginS.log \
		2>>$(LOGS)/loginS-qemu.log & echo $$! > $(PIDS)/loginS.pid
	@echo "loginS démarrée (SSH: localhost:2222 | logs: make logs-server)"

# 4. Attendre le token puis démarrer le worker
up-agent:
	@echo "En attente du node-token serveur..."
	@while [ ! -f $(SHARED)/node-token ]; do sleep 5; done
	@echo "Token disponible, démarrage VM worker loginSW..."
	$(SCRIPTS)/gen-seed.sh \
		loginSW $(WORKER_IP) 52:54:00:12:34:02 52:54:00:ab:cd:02 \
		$(GOINFRE)/seed-worker.iso \
		$(SCRIPTS)/setup_worker.sh
	qemu-img create -f qcow2 -b $(BASE_IMG) -F qcow2 $(IMGS)/loginSW.qcow2 10G
	qemu-system-x86_64 \
		-name guest=loginSW \
		-m 512 -smp 1 -enable-kvm -cpu host \
		-drive file=$(IMGS)/loginSW.qcow2,if=virtio \
		-drive file=$(GOINFRE)/seed-worker.iso,media=cdrom \
		-netdev user,id=net0,hostfwd=tcp::2223-:22 \
		-device virtio-net-pci,netdev=net0,mac=52:54:00:ab:cd:02 \
		-netdev socket,id=net1,mcast=$(MCAST) \
		-device virtio-net-pci,netdev=net1,mac=52:54:00:12:34:02 \
		-virtfs local,path=$(SHARED),mount_tag=shared,security_model=mapped-xattr \
		-nographic -serial file:$(LOGS)/loginSW.log \
		2>>$(LOGS)/loginSW-qemu.log & echo $$! > $(PIDS)/loginSW.pid
	@echo "loginSW démarrée (SSH: localhost:2223 | logs: make logs-worker)"

status:
	@echo "=== Status des VMs ==="
	@if [ -f $(PIDS)/loginS.pid ] && kill -0 $$(cat $(PIDS)/loginS.pid) 2>/dev/null; then \
		echo "loginS:  running (PID: $$(cat $(PIDS)/loginS.pid))"; \
	else echo "loginS:  stopped"; fi
	@if [ -f $(PIDS)/loginSW.pid ] && kill -0 $$(cat $(PIDS)/loginSW.pid) 2>/dev/null; then \
		echo "loginSW: running (PID: $$(cat $(PIDS)/loginSW.pid))"; \
	else echo "loginSW: stopped"; fi

ssh-server:
	ssh -o StrictHostKeyChecking=no -p 2222 vagrant@localhost

ssh-worker:
	ssh -o StrictHostKeyChecking=no -p 2223 vagrant@localhost

logs-server:
	tail -f $(LOGS)/loginS.log

logs-worker:
	tail -f $(LOGS)/loginSW.log
