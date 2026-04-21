LOGIN    ?= $(USER)
SERVER   := $(LOGIN)S
WORKER   := $(LOGIN)SW
PROVIDER ?= libvirt

export P1_LOGIN := $(LOGIN)

.PHONY: all up destroy halt reload provision status ssh-server ssh-worker test

all: up

up:
	vagrant up $(SERVER) --provider=$(PROVIDER)
	vagrant up $(WORKER) --provider=$(PROVIDER)

destroy:
	vagrant destroy -f

halt:
	vagrant halt

reload:
	vagrant reload --provision

provision:
	vagrant provision

status:
	vagrant status

ssh-server:
	vagrant ssh $(SERVER)

ssh-worker:
	vagrant ssh $(WORKER)

test:
	bash scripts/test.sh
