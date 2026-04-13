# =============================================================================
# Makefile P3 - K3d + Argo CD (Continuous Deployment via GitOps)
# =============================================================================
#
# RESUME DU SUJET :
#   P3 met en place une infrastructure de continuous deployment :
#   - Un cluster K3d (K3s dans Docker, pas de VM)
#   - Argo CD surveille un repo GitHub
#   - L'application est deployee automatiquement dans le namespace "dev"
#   - Changer la version dans GitHub → Argo CD synchronise automatiquement
#
# COMMANDES DISPONIBLES :
#   make setup    → Installe les prerequis (Docker, K3d, kubectl, argocd CLI)
#   make          → Cree le cluster et deploie tout (= make up)
#   make test     → Verifie que tout est correct (namespaces, pods, HTTP...)
#   make status   → Affiche l'etat du cluster et des pods
#   make password → Affiche le mot de passe admin Argo CD
#   make clean    → Detruit le cluster K3d
#   make re       → clean + up (tout reconstruire)
#
# =============================================================================

NAME = p3

# Cible par defaut : deployer tout
all: up

# --- Installation des prerequis ---
# Installe Docker, K3d, kubectl, argocd CLI + corrige les cgroups si necessaire.
# A lancer une seule fois (ou lors de la defense pour montrer l'installation).
setup:
	@echo "Installation des prerequis..."
	@bash scripts/setup.sh

# --- Deploiement complet ---
# Cree le cluster K3d, installe Argo CD, deploie l'application.
# Idempotent : peut etre relance sans tout casser.
up:
	@echo "Deploiement de l'infrastructure..."
	@bash scripts/deploy.sh

# --- Tests de validation ---
# Verifie toutes les exigences du sujet :
# - Cluster K3d operationnel
# - Namespaces argocd + dev
# - Argo CD fonctionnel et accessible
# - Application deployee et repondant sur localhost:8888
test:
	@echo "Lancement des tests..."
	@bash scripts/test.sh

# --- Destruction du cluster ---
# Supprime le cluster K3d et tous ses conteneurs Docker associes.
# Les images Docker restent en cache (pas besoin de les re-telecharger).
clean:
	@echo "Destruction du cluster K3d..."
	@k3d cluster delete mycluster || true

# --- Reconstruction complete ---
# Detruit puis recree tout depuis zero.
re: clean up

# --- Etat de l'infrastructure ---
# Affiche un resume rapide : cluster, nodes, pods argocd, pods dev.
# Utile pendant la defense pour montrer l'etat.
status:
	@echo "=== Etat du cluster ==="
	@k3d cluster list 2>/dev/null || echo "K3d non installe ou aucun cluster"
	@echo ""
	@echo "=== Nodes Kubernetes ==="
	@kubectl get nodes 2>/dev/null || echo "Aucun cluster actif"
	@echo ""
	@echo "=== Pods Argo CD ==="
	@kubectl get pods -n argocd 2>/dev/null || echo "Namespace argocd introuvable"
	@echo ""
	@echo "=== Pods dev ==="
	@kubectl get pods -n dev 2>/dev/null || echo "Namespace dev introuvable"

# --- Mot de passe admin Argo CD ---
# Argo CD genere un mot de passe aleatoire a l'installation, stocke dans un Secret.
# Login : admin / Password : (affiche par cette commande)
password:
	@echo "Mot de passe admin Argo CD :"
	@kubectl get secret argocd-initial-admin-secret -n argocd \
		-o jsonpath="{.data.password}" 2>/dev/null | base64 -d && echo \
		|| echo "Argo CD non installe ou secret introuvable"

.PHONY: all setup up test clean re status password
