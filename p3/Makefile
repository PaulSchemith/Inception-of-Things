# =============================================================================
# Makefile P3 - K3d + Argo CD (Continuous Deployment via GitOps)
#
#   make setup    → Installe les prerequis (Docker, K3d, kubectl, argocd CLI)
#   make          → Cree le cluster et deploie tout (= make up)
#   make test     → Verifie que tout est correct
#   make status   → Affiche l'etat du cluster et des pods
#   make password → Affiche le mot de passe admin Argo CD
#   make clean    → Detruit le cluster K3d
#   make re       → clean + up
# =============================================================================

NAME = p3

.PHONY: all setup up test clean re status password

all: up

setup:
	@bash scripts/setup.sh

up:
	@bash scripts/deploy.sh

test:
	@bash scripts/test.sh

clean:
	@k3d cluster delete mycluster || true

re: clean up

status:
	@echo "=== Cluster K3d ==="
	@k3d cluster list 2>/dev/null || echo "Aucun cluster"
	@echo ""
	@echo "=== Nodes ==="
	@kubectl get nodes 2>/dev/null || echo "Aucun cluster actif"
	@echo ""
	@echo "=== Pods argocd ==="
	@kubectl get pods -n argocd 2>/dev/null || echo "Namespace argocd introuvable"
	@echo ""
	@echo "=== Pods dev ==="
	@kubectl get pods -n dev 2>/dev/null || echo "Namespace dev introuvable"

password:
	@kubectl get secret argocd-initial-admin-secret -n argocd \
		-o jsonpath="{.data.password}" 2>/dev/null | base64 -d && echo \
		|| echo "Argo CD non installe ou secret introuvable"
