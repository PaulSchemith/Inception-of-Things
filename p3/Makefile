K3D_CMD = k3d
KUBECTL_CMD = kubectl
CLUSTER_NAME = my-cluster
ARGO_NS = argocd
DEV_NS = dev

.PHONY: install uninstall create namespace install-argocd ingress check

install:
	@chmod +x scripts/install_tools.sh
	@./scripts/install_tools.sh

uninstall:
	@chmod +x scripts/uninstall_tools.sh
	@./scripts/uninstall_tools.sh

create:
	@$(K3D_CMD) cluster create $(CLUSTER_NAME) \
		--api-port 6443 \
		-p 8888:80@loadbalancer \
		--agents 2 || \
	echo "⚠️ k3d cluster not created (42 limitation)"

namespace:
	@$(KUBECTL_CMD) create namespace $(ARGO_NS) 2>/dev/null || true
	@$(KUBECTL_CMD) create namespace $(DEV_NS) 2>/dev/null || true
	@$(KUBECTL_CMD) get namespaces || true

install-argocd:
	@$(KUBECTL_CMD) apply -n $(ARGO_NS) \
		-f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml || \
	echo "⚠️ Argo CD installation skipped"

ingress:
	@$(KUBECTL_CMD) apply -f confs/argocd-ingress.yaml -n argocd || true
	@$(KUBECTL_CMD) apply -f confs/argocd-app.yaml -n argocd || true

check:
	@$(KUBECTL_CMD) get ns || true
	@$(KUBECTL_CMD) get pods -n $(ARGO_NS) || true
	@$(KUBECTL_CMD) get pods -n $(DEV_NS) || true
	@$(KUBECTL_CMD) get ingress -n argocd || true
