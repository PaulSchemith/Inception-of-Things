# =============================================================================
# Makefile Bonus - GitLab local + Argo CD (Continuous Deployment 100% local)
# =============================================================================
#
# OBJECTIF DU BONUS :
#   Remplacer GitHub (P3) par une instance GitLab qui tourne DANS le cluster K3d.
#   La chaine CI/CD devient entierement locale :
#
#   GitLab local (namespace gitlab)
#       ↓ repo git + webhooks
#   Argo CD (namespace argocd) surveille GitLab en continu
#       ↓ detecte chaque commit, applique les manifests
#   Application wil42/playground (namespace dev)
#
# DIFFERENCES AVEC P3 :
#   P3    : Argo CD surveille GitHub (externe)
#   BONUS : Argo CD surveille GitLab (local, dans le cluster)
#           + namespace "gitlab" requis par le sujet
#           + Helm utilise pour deployer GitLab
#
# COMMANDES :
#   make setup      → Installe helm + docker + k3d + kubectl
#   make            → Deploie tout (K3d + GitLab + Argo CD)
#   make test       → Verifie que tout fonctionne
#   make status     → Affiche l'etat complet
#   make password   → Mot de passe admin Argo CD
#   make switch-v2  → Change l'app de v1 a v2 via l'API GitLab (demo CD)
#   make switch-v1  → Revient a v1
#   make clean      → Detruit le cluster K3d
#   make re         → clean + up (tout reconstruire)
#
# PORTS ACCESSIBLES DEPUIS LE HOST :
#   localhost:8888  → Application wil-playground
#   localhost:8929  → GitLab UI  (root / IoT-R00t@42Lab)
#   localhost:31080 → Argo CD UI (admin / make password)
#
# =============================================================================

GITLAB_ROOT_PASSWORD ?= IoT-R00t@42Lab
GITLAB_NS            := gitlab
ARGOCD_NS            := argocd

.PHONY: all setup up test clean re status password switch-v1 switch-v2

all: up

setup:
	@bash scripts/setup.sh

up:
	@GITLAB_ROOT_PASSWORD="$(GITLAB_ROOT_PASSWORD)" bash scripts/deploy.sh

test:
	@bash scripts/test.sh

clean:
	@k3d cluster delete mycluster || true

re: clean up

status:
	@echo "=== Cluster K3d ==="
	@k3d cluster list 2>/dev/null || echo "aucun cluster"
	@echo ""
	@echo "=== Nodes ==="
	@kubectl get nodes 2>/dev/null || echo "cluster inactif"
	@echo ""
	@echo "=== Pods GitLab ==="
	@kubectl get pods -n $(GITLAB_NS) 2>/dev/null || echo "namespace gitlab introuvable"
	@echo ""
	@echo "=== Pods Argo CD ==="
	@kubectl get pods -n $(ARGOCD_NS) 2>/dev/null || echo "namespace argocd introuvable"
	@echo ""
	@echo "=== Pods dev ==="
	@kubectl get pods -n dev 2>/dev/null || echo "namespace dev introuvable"
	@echo ""
	@echo "=== Application Argo CD ==="
	@kubectl get application wil-app -n $(ARGOCD_NS) -o wide 2>/dev/null || echo "application introuvable"

password:
	@kubectl get secret argocd-initial-admin-secret -n $(ARGOCD_NS) \
		-o jsonpath="{.data.password}" 2>/dev/null | base64 -d && echo \
		|| echo "Argo CD non installe"

# --- Demo : passage de v1 a v2 ---
# Modifie deployment.yaml dans GitLab via l'API REST.
# Argo CD detecte le nouveau commit et synchronise automatiquement (~3 minutes).
switch-v2:
	@bash scripts/switch-version.sh v2
	@kubectl wait --for=jsonpath='{.status.sync.status}'=Synced \
		application/wil-app -n $(ARGOCD_NS) --timeout=300s 2>/dev/null || true
	@curl -s http://localhost:8888 || echo "(app pas encore prete)"

# --- Demo : retour a v1 ---
switch-v1:
	@bash scripts/switch-version.sh v1
	@kubectl wait --for=jsonpath='{.status.sync.status}'=Synced \
		application/wil-app -n $(ARGOCD_NS) --timeout=300s 2>/dev/null || true
	@curl -s http://localhost:8888 || echo "(app pas encore prete)"
