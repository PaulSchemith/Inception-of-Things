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
#   localhost:8929  → GitLab UI  (root / GitLabP@ssw0rd!)
#   localhost:31080 → Argo CD UI (admin / make password)
#
# =============================================================================

# Mot de passe root GitLab (surcharge possible : GITLAB_ROOT_PASSWORD=xxx make up)
GITLAB_ROOT_PASSWORD ?= GitLabP@ssw0rd!
GITLAB_URL           := http://localhost:8929
GITLAB_NS            := gitlab
ARGOCD_NS            := argocd

all: up

# --- Installation des prerequis ---
# Installe helm, docker, k3d, kubectl + configure les cgroups
setup:
	@echo "Installation des prerequis..."
	@bash scripts/setup.sh

# --- Deploiement complet ---
# Cree le cluster, deploie GitLab (Helm), Argo CD, configure le repo GitLab,
# et lance le continuous deployment.
up:
	@echo "Deploiement infrastructure bonus..."
	@GITLAB_ROOT_PASSWORD="$(GITLAB_ROOT_PASSWORD)" bash scripts/deploy.sh

# --- Tests de validation ---
# Verifie tous les criteres du sujet : namespaces, GitLab, Argo CD, app HTTP.
test:
	@echo "Lancement des tests bonus..."
	@bash scripts/test.sh

# --- Destruction du cluster ---
clean:
	@echo "Destruction du cluster K3d..."
	@k3d cluster delete mycluster || true

# --- Reconstruction complete ---
re: clean up

# --- Etat de l'infrastructure ---
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

# --- Mot de passe Argo CD ---
password:
	@echo "Mot de passe admin Argo CD :"
	@kubectl get secret argocd-initial-admin-secret -n $(ARGOCD_NS) \
		-o jsonpath="{.data.password}" 2>/dev/null | base64 -d && echo \
		|| echo "Argo CD non installe"

# --- Demo : passage de v1 a v2 ---
# Modifie deployment.yaml dans GitLab via l'API REST.
# Argo CD detecte le nouveau commit et synchronise automatiquement (~3 minutes).
# Verifie avec : curl http://localhost:8888
switch-v2:
	@echo "Changement v1 → v2 dans GitLab..."
	@bash scripts/switch-version.sh v2
	@echo ""
	@echo "Attente de la synchro Argo CD..."
	@kubectl wait --for=jsonpath='{.status.sync.status}'=Synced \
		application/wil-app -n $(ARGOCD_NS) --timeout=300s 2>/dev/null || true
	@echo ""
	@echo "Version active :"
	@curl -s http://localhost:8888 || echo "(app pas encore prete)"

# --- Demo : retour a v1 ---
switch-v1:
	@echo "Changement v2 → v1 dans GitLab..."
	@bash scripts/switch-version.sh v1
	@echo ""
	@echo "Attente de la synchro Argo CD..."
	@kubectl wait --for=jsonpath='{.status.sync.status}'=Synced \
		application/wil-app -n $(ARGOCD_NS) --timeout=300s 2>/dev/null || true
	@echo ""
	@echo "Version active :"
	@curl -s http://localhost:8888 || echo "(app pas encore prete)"

.PHONY: all setup up test clean re status password switch-v1 switch-v2
