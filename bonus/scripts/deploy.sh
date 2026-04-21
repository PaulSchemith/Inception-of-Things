#!/bin/bash
# =============================================================================
# Bonus Deploy Script - K3d + GitLab (Helm) + Argo CD (GitOps 100% local)
# =============================================================================
#
# CE QUE CE SCRIPT FAIT (dans l'ordre) :
#
#  [ 1] Cree le cluster K3d avec 3 ports mappes :
#         8888  → app wil-playground
#         8929  → GitLab UI  (via NodePort 30929)
#         31080 → Argo CD UI
#  [ 2] Cree les 3 namespaces : argocd, dev, gitlab
#  [ 3] Installe GitLab via Helm (chart officiel gitlab/gitlab)
#  [ 4] Expose GitLab sur localhost:8929 + attend migrations + webservice ready
#  [ 5] Installe Argo CD (identique a P3)
#  [ 6] Cree le compte root + Personal Access Token GitLab via le pod "toolbox"
#  [ 7] Cree le projet GitLab et pousse le manifest deployment.yaml
#  [ 8] Configure Argo CD pour surveiller le repo GitLab local
#  [ 9] Cree l'Application Argo CD
#  [10] Attend la synchronisation Argo CD → app dans namespace dev
#
# NOTE SUR LE TOOLBOX :
#   Dans le chart cloud-native (Helm) de GitLab, les pods webservice tournent
#   avec Puma et ne permettent PAS d'executer "gitlab-rails runner".
#   Le pod "toolbox" est LE conteneur prevu pour ca : il a gitlab-rails en PATH,
#   les bonnes variables d'environnement Rails, et l'acces a la base de donnees.
#
# =============================================================================
set -e

# === CONFIGURATION ===
CLUSTER_NAME="${CLUSTER_NAME:-mycluster}"
ARGOCD_NS="argocd"
DEV_NS="dev"
GITLAB_NS="gitlab"
APP_NAME="wil-app"

GITLAB_ROOT_PASSWORD="${GITLAB_ROOT_PASSWORD:-IoT-R00t@42Lab}"
GITLAB_NODEPORT=30929       # NodePort K8s (range valide : 30000-32767)
GITLAB_HOST_PORT=8929       # Port accessible depuis le host (via K3d loadbalancer)
ARGOCD_NODEPORT=31080

# Deux URLs pour GitLab selon le contexte :
# - EXTERNAL : depuis le HOST (scripts, navigateur)  → via K3d loadbalancer
# - INTERNAL : depuis le CLUSTER (Argo CD)           → via DNS K8s interne
GITLAB_EXTERNAL="http://localhost:${GITLAB_HOST_PORT}"
GITLAB_INTERNAL="http://gitlab-webservice-default.${GITLAB_NS}.svc.cluster.local:8181"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFS_DIR="$PROJECT_DIR/confs"

# Verifie les fichiers de config necessaires
for f in gitlab-values.yaml gitlab-nodeport.yaml argocd-server.yaml deployment.yaml; do
    [ -f "$CONFS_DIR/$f" ] || { echo "ERREUR : $CONFS_DIR/$f introuvable"; exit 1; }
done

# =============================================================================
# CHECK CGROUP CPU
# =============================================================================
# K3s (tourne dans un conteneur Docker via K3d) a besoin du controleur cgroup
# "cpu" pour gerer les ressources des pods. Sur certains environnements
# (machines virtuelles imbriquees, conteneurs LXC...), Docker ne delegue pas
# ce controleur → K3s crash au demarrage avec "failed to find cpu cgroup".
check_cgroup() {
    local ctrl
    ctrl=$(docker run --rm alpine:3.20 sh -c \
        'cat /sys/fs/cgroup/cgroup.controllers 2>/dev/null || true' 2>/dev/null || true)
    if echo "$ctrl" | grep -qw cpu; then
        echo "[*] Cgroup CPU OK."
        return 0
    fi
    echo "[*] Correction cgroup CPU..."
    local subtree="/sys/fs/cgroup/system.slice/docker.service/cgroup.subtree_control"
    [ -f "$subtree" ] && \
        sudo sh -c "echo '+cpu +cpuset +io +memory +pids' > $subtree" 2>/dev/null && \
        sudo systemctl restart docker 2>/dev/null && sleep 3
    ctrl=$(docker run --rm alpine:3.20 sh -c \
        'cat /sys/fs/cgroup/cgroup.controllers 2>/dev/null || true' 2>/dev/null || true)
    echo "$ctrl" | grep -qw cpu || { echo "ERREUR: cgroup CPU indisponible."; exit 1; }
    echo "[*] Cgroup CPU corrige."
}

echo "[*] Verification environnement..."
check_cgroup

# =============================================================================
# ETAPE 1 : Cluster K3d
# =============================================================================
# K3d cree un cluster K3s (Kubernetes leger) dans des conteneurs Docker.
# Les 3 mappings de ports :
#   "-p HOST:NODE@loadbalancer" = K3d redirige le port HOST vers le port NODE
#   du load balancer, qui lui-meme route vers les Services Kubernetes.
echo "[1/10] Creation du cluster K3d..."
cluster_ok() {
    k3d cluster list "$CLUSTER_NAME" >/dev/null 2>&1 || return 1
    k3d kubeconfig merge "$CLUSTER_NAME" --kubeconfig-switch-context >/dev/null 2>&1 || return 1
    kubectl get nodes --request-timeout=5s >/dev/null 2>&1 || return 1
}

if ! cluster_ok; then
    k3d cluster list "$CLUSTER_NAME" >/dev/null 2>&1 && k3d cluster delete "$CLUSTER_NAME" || true
    k3d cluster create "$CLUSTER_NAME" \
        --wait \
        -p "8888:8888@loadbalancer" \
        -p "${GITLAB_HOST_PORT}:${GITLAB_NODEPORT}@loadbalancer" \
        -p "${ARGOCD_NODEPORT}:${ARGOCD_NODEPORT}@loadbalancer"
else
    echo "  Cluster deja sain, reutilisation."
fi
k3d kubeconfig merge "$CLUSTER_NAME" --kubeconfig-switch-context

# =============================================================================
# ETAPE 2 : Namespaces
# =============================================================================
# Le sujet exige 3 namespaces specifiques.
# Les namespaces isolent les ressources K8s entre elles.
echo "[2/10] Creation des namespaces..."
for ns in "$ARGOCD_NS" "$DEV_NS" "$GITLAB_NS"; do
    kubectl create namespace "$ns" 2>/dev/null \
        && echo "  namespace/$ns cree" \
        || echo "  namespace/$ns existe deja"
done

# =============================================================================
# ETAPE 3 : Installation de GitLab via Helm
# =============================================================================
# Helm est le gestionnaire de packages pour Kubernetes.
# Un "chart" = archive contenant des templates YAML + valeurs par defaut.
# "helm install" instancie les templates avec nos valeurs (gitlab-values.yaml)
# et applique tout au cluster.
#
# Le Secret du mot de passe root DOIT exister avant helm install car les
# migrations (Job Kubernetes one-shot) en ont besoin pour creer le compte root.
echo "[3/10] Installation GitLab via Helm..."

# Cree le Secret du mot de passe root GitLab
kubectl get secret gitlab-initial-root-password -n "$GITLAB_NS" >/dev/null 2>&1 \
    || kubectl create secret generic gitlab-initial-root-password \
        -n "$GITLAB_NS" \
        --from-literal=password="${GITLAB_ROOT_PASSWORD}"

helm repo add gitlab https://charts.gitlab.io/ 2>/dev/null || true
helm repo update

if helm status gitlab -n "$GITLAB_NS" >/dev/null 2>&1; then
    echo "  GitLab deja installe via Helm."
else
    echo "  Installation en cours (peut prendre 10-20 min pour le telechargement des images)..."
    helm install gitlab gitlab/gitlab \
        --namespace "$GITLAB_NS" \
        --values "$CONFS_DIR/gitlab-values.yaml" \
        --timeout 20m \
        --wait
fi

# =============================================================================
# ETAPE 4 : Exposition de GitLab via NodePort
# =============================================================================
# Helm cree un Service ClusterIP pour le webservice (accessible seulement
# dans le cluster). On ajoute un Service NodePort pour l'acces depuis le host.
echo "[4/10] Exposition GitLab sur localhost:${GITLAB_HOST_PORT}..."
kubectl apply -f "$CONFS_DIR/gitlab-nodeport.yaml"

# Attente des migrations (Job one-shot qui initialise la base de donnees)
# Les migrations DOIVENT se terminer avant de pouvoir utiliser l'API.
# Le nom du Job varie selon la version du chart (gitlab-migrations, gitlab-migrations-1...).
echo "[*] Attente du job de migrations GitLab (peut prendre 5-10 min)..."
MIGRATION_JOB=""
elapsed=0
until [ -n "$MIGRATION_JOB" ]; do
    MIGRATION_JOB=$(kubectl get jobs -n "$GITLAB_NS" --no-headers 2>/dev/null \
        | grep "migrations" | awk '{print $1}' | head -1 || true)
    [ -n "$MIGRATION_JOB" ] && break
    printf "  attente creation job migrations (%ds)...\r" "$elapsed"
    sleep 5; elapsed=$((elapsed + 5))
    [ $elapsed -gt 300 ] && echo "" && echo "  WARN: job migrations introuvable apres 5min, on continue..." && break
done
if [ -n "$MIGRATION_JOB" ]; then
    echo "  Job trouve : $MIGRATION_JOB"
    kubectl wait --for=condition=complete \
        "job/$MIGRATION_JOB" \
        -n "$GITLAB_NS" \
        --timeout=900s
fi

# Attente que le webservice soit ready
echo "[*] Attente que GitLab webservice soit disponible..."
kubectl wait --for=condition=available \
    deployment/gitlab-webservice-default \
    -n "$GITLAB_NS" \
    --timeout=600s

# Attente que GitLab reponde sur HTTP (pas juste que le pod soit Running)
echo "[*] Attente que GitLab reponde sur ${GITLAB_EXTERNAL}..."
elapsed=0
until curl -sf --max-time 5 "${GITLAB_EXTERNAL}/-/readiness" \
        -o /dev/null 2>/dev/null; do
    printf "  attente GitLab HTTP (%ds)...\r" "$elapsed"
    sleep 10
    elapsed=$((elapsed + 10))
    [ $elapsed -gt 300 ] && echo "" && echo "  WARN: GitLab lent, on continue..." && break
done
echo ""

# =============================================================================
# ETAPE 5 : Installation d'Argo CD
# =============================================================================
# Identique a P3 : manifests officiels Argo CD + --server-side pour les CRDs
# trop grandes pour les annotations kubectl classiques.
echo "[5/10] Installation d'Argo CD..."
kubectl apply --server-side -n "$ARGOCD_NS" \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl wait --for=condition=available --timeout=600s \
    deployment/argocd-server -n "$ARGOCD_NS"

# Remplace le Service ClusterIP par un LoadBalancer avec NodePort fixe
kubectl delete svc argocd-server -n "$ARGOCD_NS" 2>/dev/null || true
kubectl apply -f "$CONFS_DIR/argocd-server.yaml"

# =============================================================================
# ETAPE 6 : Creation du Personal Access Token GitLab
# =============================================================================
# Pour automatiser la config GitLab (creer projet, pousser fichiers), on a
# besoin d'un token d'authentification API.
#
# Dans le chart cloud-native de GitLab, le pod "toolbox" est LE seul endroit
# prevu pour executer "gitlab-rails runner" :
#   - Le pod webservice fait tourner Puma + Workhorse mais n'expose pas rails CLI
#   - Le pod toolbox a gitlab-rails en PATH + le bon environnement Rails
#
# La commande Ruby cree un PersonalAccessToken en base de donnees GitLab.
# Le sentinel "TOKEN=" permet d'extraire juste le token depuis la sortie
# qui peut contenir des messages de log Rails.
echo "[6/10] Creation du Personal Access Token GitLab..."

# Attente que le toolbox soit pret
TOOLBOX_POD=$(kubectl get pods -n "$GITLAB_NS" \
    -l "app=toolbox" \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [ -z "$TOOLBOX_POD" ]; then
    echo "  Attente du pod toolbox..."
    kubectl wait --for=condition=ready \
        pod -l "app=toolbox" \
        -n "$GITLAB_NS" \
        --timeout=300s
    TOOLBOX_POD=$(kubectl get pods -n "$GITLAB_NS" \
        -l "app=toolbox" \
        -o jsonpath='{.items[0].metadata.name}')
fi
echo "  Pod toolbox : $TOOLBOX_POD"

# Execute du Ruby via gitlab-rails runner (bash -c pour eviter les problemes
# de transmission stdin avec kubectl exec + heredoc).
#
# Etape 6a : creation du compte root si absent (GitLab 17+ exige une Organization
# sur le Namespace utilisateur ; on la recupere depuis la base avant de sauvegarder).
kubectl exec -n "$GITLAB_NS" "$TOOLBOX_POD" -- bash -c "
gitlab-rails runner \"
if User.find_by_username('root').nil?
  org = Organizations::Organization.first
  u   = User.new(name: 'Administrator', username: 'root',
                 email: 'admin@local.example', admin: true)
  u.password              = '${GITLAB_ROOT_PASSWORD}'
  u.password_confirmation = '${GITLAB_ROOT_PASSWORD}'
  u.confirmed_at          = Time.current
  ns = u.build_namespace
  ns.organization = org
  u.save ? \\\$stdout.puts('root created') : \\\$stderr.puts(u.errors.full_messages.to_s)
else
  \\\$stdout.puts 'root already exists'
end
\"" 2>&1

# Etape 6b : creation (ou recuperation) du Personal Access Token.
# Le sentinel TOKEN= permet d'extraire uniquement le token parmi les logs Rails.
GL_TOKEN=$(kubectl exec -n "$GITLAB_NS" "$TOOLBOX_POD" -- bash -c "
gitlab-rails runner \"
begin
  user  = User.find_by_username!('root')
  token = PersonalAccessToken.find_by(name: 'iot-automation', user: user)
  if token.nil? || token.revoked?
    token = user.personal_access_tokens.create!(
      name:       'iot-automation',
      scopes:     %w[api read_repository write_repository],
      expires_at: 1.year.from_now
    )
  end
  \\\$stdout.puts 'TOKEN=' + token.token
rescue => e
  \\\$stderr.puts 'ERROR: ' + e.message
  exit 1
end
\"" 2>/dev/null)

GL_TOKEN=$(echo "$GL_TOKEN" | grep '^TOKEN=' | cut -d= -f2 | tr -d '[:space:]')

if [ -z "$GL_TOKEN" ]; then
    echo "ERREUR : impossible de creer le token GitLab."
    echo "  Verifier les logs : kubectl logs -n $GITLAB_NS $TOOLBOX_POD"
    exit 1
fi
echo "  Token GitLab cree (glpat-...)."

# Sauvegarde du token dans un Secret K8s (utile pour switch-version.sh et debug)
kubectl create secret generic gitlab-iot-token \
    -n "$GITLAB_NS" \
    --from-literal=token="$GL_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -

# =============================================================================
# ETAPE 7 : Creation du projet GitLab et push du manifest
# =============================================================================
# On utilise l'API REST GitLab v4 pour :
#   1. Creer le projet "iot-wil-app" (public)
#   2. Pousser deployment.yaml comme premier commit
#
# Pourquoi l'API et non git push ?
#   → Pas besoin de configurer git, ssh-keyscan, ~/.netrc
#   → L'API permet de faire tout en HTTP avec juste curl + le token
echo "[7/10] Creation du projet GitLab et push du manifest..."

# Cree le projet (ou recupere son ID s'il existe deja)
PROJECT_RESP=$(curl -sf "${GITLAB_EXTERNAL}/api/v4/projects" \
    -H "PRIVATE-TOKEN: $GL_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"name":"iot-wil-app","visibility":"public","initialize_with_readme":false}' \
    2>/dev/null || true)

PROJECT_ID=$(echo "$PROJECT_RESP" | jq -r '.id // empty' 2>/dev/null || true)

if [ -z "$PROJECT_ID" ]; then
    # Le projet existe peut-etre deja → on recupere son ID
    PROJECT_ID=$(curl -sf \
        "${GITLAB_EXTERNAL}/api/v4/projects/root%2Fiot-wil-app" \
        -H "PRIVATE-TOKEN: $GL_TOKEN" 2>/dev/null \
        | jq -r '.id // empty')
fi

if [ -z "$PROJECT_ID" ]; then
    echo "ERREUR : impossible de creer/recuperer le projet GitLab."
    exit 1
fi
echo "  Projet GitLab ID : $PROJECT_ID"

# Pousse deployment.yaml via l'API Files.
# On encode le contenu en base64 pour eviter les problemes de caracteres
# speciaux dans le JSON. L'API GitLab supporte l'encodage base64 nativement.
# jq est utilise pour construire le JSON proprement (evite les problemes
# d'echappement si on injectait directement dans un heredoc).
DEPLOY_CONTENT=$(base64 -w0 "$CONFS_DIR/deployment.yaml")
PUSH_BODY=$(jq -n \
    --arg branch "main" \
    --arg content "$DEPLOY_CONTENT" \
    --arg msg "Initial deployment - wil42/playground:v1" \
    '{branch: $branch, content: $content, encoding: "base64", commit_message: $msg}')

PUSH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "${GITLAB_EXTERNAL}/api/v4/projects/${PROJECT_ID}/repository/files/deployment.yaml" \
    -H "PRIVATE-TOKEN: $GL_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PUSH_BODY")

case "$PUSH_STATUS" in
    201) echo "  deployment.yaml pousse (201 Created)." ;;
    400) echo "  deployment.yaml existe deja dans le repo." ;;
    *)   echo "  WARN: push HTTP $PUSH_STATUS" ;;
esac

# =============================================================================
# ETAPE 8 : Connexion Argo CD ↔ GitLab local
# =============================================================================
# Argo CD lit les repos Git pour synchroniser l'etat du cluster.
# On lui dit de faire confiance au repo GitLab local via un Secret Kubernetes
# avec le label special "argocd.argoproj.io/secret-type: repository".
#
# URL interne : Argo CD (dans le cluster) atteint GitLab via le DNS K8s :
#   gitlab-webservice-default.gitlab.svc.cluster.local:8181
# (pas besoin de passer par le NodePort externe)
echo "[8/10] Configuration du repo GitLab dans Argo CD..."

GITLAB_REPO_URL="${GITLAB_INTERNAL}/root/iot-wil-app.git"

kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: gitlab-repo-creds
  namespace: ${ARGOCD_NS}
  labels:
    # Label magique : Argo CD scanne les Secrets avec ce label
    # et les ajoute automatiquement a sa liste de repos connus.
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: ${GITLAB_REPO_URL}
  username: root
  password: "${GL_TOKEN}"
  # insecure=true : autorise les repos HTTP (pas de TLS).
  # En production : utiliser HTTPS avec un certificat valide.
  insecure: "true"
  insecureIgnoreHostKey: "true"
EOF

# =============================================================================
# ETAPE 9 : Application Argo CD
# =============================================================================
# La ressource "Application" (CRD d'Argo CD) connecte un repo Git a un
# namespace Kubernetes. Argo CD surveille le repo toutes les ~3 minutes
# et applique les changements automatiquement (syncPolicy.automated).
echo "[9/10] Creation de l'Application Argo CD..."

kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${APP_NAME}
  namespace: ${ARGOCD_NS}
spec:
  project: default
  source:
    # URL INTERNE GitLab (Argo CD → GitLab, tous deux dans le cluster)
    repoURL: ${GITLAB_REPO_URL}
    targetRevision: HEAD
    path: .
  destination:
    server: https://kubernetes.default.svc
    namespace: ${DEV_NS}
  syncPolicy:
    automated:
      prune: true      # Supprime les ressources retirees du repo
      selfHeal: true   # Re-applique si quelqu'un modifie le cluster manuellement
EOF

# =============================================================================
# ETAPE 10 : Attente synchronisation finale
# =============================================================================
echo "[10/10] Attente de la synchronisation Argo CD..."
kubectl wait \
    --for=jsonpath='{.status.health.status}'=Healthy \
    --timeout=600s \
    "application/${APP_NAME}" -n "$ARGOCD_NS" 2>/dev/null || true

kubectl wait --for=condition=Ready pod --all \
    -n "$DEV_NS" --timeout=300s 2>/dev/null || true

# =============================================================================
# RESULTAT
# =============================================================================
ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret \
    -n "$ARGOCD_NS" -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "(make password)")

echo ""
echo "Deploiement termine !"
echo "================================================"
echo ""
echo "GitLab            : ${GITLAB_EXTERNAL}"
echo "  Login           : root / ${GITLAB_ROOT_PASSWORD}"
echo "  Repo            : ${GITLAB_EXTERNAL}/root/iot-wil-app"
echo ""
echo "Argo CD           : https://localhost:${ARGOCD_NODEPORT}"
echo "  Login           : admin / ${ARGOCD_PASSWORD}"
echo ""
echo "Application       : curl http://localhost:8888"
echo ""
echo "Demo CD           : make switch-v2  (puis curl localhost:8888)"
echo "================================================"
