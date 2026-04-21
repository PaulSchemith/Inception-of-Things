LOGIN    ?= $(USER)
SERVER   := $(LOGIN)S
PROVIDER ?= libvirt

export P2_LOGIN := $(LOGIN)

.PHONY: all up destroy halt reload provision deploy status ssh test

all: up

up:
	vagrant up $(SERVER) --provider=$(PROVIDER)

# Réapplique les manifests sans recréer la VM
deploy:
	vagrant ssh $(SERVER) -c "sudo kubectl apply -f /vagrant/confs"

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

ssh:
	vagrant ssh $(SERVER)

test:
	bash scripts/test.sh
