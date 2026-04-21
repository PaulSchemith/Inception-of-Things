# Makefile pour P1 - Vagrant + libvirt (QEMU/KVM)

LOGIN       ?= $(USER)
SERVER      := $(LOGIN)S
WORKER      := $(LOGIN)SW
VAGRANT_CMD ?= vagrant
PROVIDER    ?= libvirt

export P1_LOGIN := $(LOGIN)

.PHONY: all up up-server up-agent destroy halt reload provision status ssh-server ssh-worker test

all: up

up:
	@echo "Démarrage des VMs via Vagrant ($(PROVIDER))..."
	$(VAGRANT_CMD) up $(SERVER) --provider=$(PROVIDER)
	$(VAGRANT_CMD) up $(WORKER) --provider=$(PROVIDER)

# Compatibilite avec l'ancien workflow: demarre seulement le serveur.
up-server:
	@echo "Démarrage VM serveur $(SERVER) via Vagrant ($(PROVIDER))..."
	$(VAGRANT_CMD) up $(SERVER) --provider=$(PROVIDER)

# Compatibilite avec l'ancien workflow: demarre seulement le worker.
up-agent:
	@echo "Démarrage VM worker $(WORKER) via Vagrant ($(PROVIDER))..."
	$(VAGRANT_CMD) up $(WORKER) --provider=$(PROVIDER)

destroy:
	@echo "Destruction des VMs Vagrant..."
	$(VAGRANT_CMD) destroy -f

halt:
	@echo "Arrêt des VMs Vagrant..."
	$(VAGRANT_CMD) halt

reload:
	@echo "Redémarrage des VMs et reprovisionnement..."
	$(VAGRANT_CMD) reload --provision

provision:
	@echo "Provisionnement des VMs..."
	$(VAGRANT_CMD) provision

status:
	@echo "=== Status des VMs ==="
	$(VAGRANT_CMD) status

ssh-server:
	$(VAGRANT_CMD) ssh $(SERVER)

ssh-worker:
	$(VAGRANT_CMD) ssh $(WORKER)

test:
	bash scripts/test.sh
