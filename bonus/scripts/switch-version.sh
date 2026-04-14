#!/bin/bash
# =============================================================================
# switch-version.sh - Bascule l'app entre v1 et v2 via l'API GitLab
# =============================================================================
#
# DEMO DU CONTINUOUS DEPLOYMENT :
#   Ce script illustre exactement ce que le sujet demande de montrer en evaluation.
#
#   SANS script (a la main, comme le sujet le decrit) :
#     1. Editer deployment.yaml dans GitLab (localhost:8929/root/iot-wil-app)
#     2. Modifier "image: wil42/playground:v1" → "image: wil42/playground:v2"
#     3. Commiter
#     4. Argo CD detecte le commit (~3 min de polling)
#     5. Argo CD applique le nouveau manifest → pod mis a jour
#     6. curl http://localhost:8888 → {"status":"ok","message":"v2"}
#
#   AVEC ce script (automatique, pour gagner du temps en defense) :
#     make switch-v2   ou   bash scripts/switch-version.sh v2
#
# COMMENT CA MARCHE :
#   1. Recupere le token GitLab stocke dans un Secret Kubernetes
#   2. Recupere le contenu actuel de deployment.yaml via l'API GitLab
#   3. Remplace le tag de version (v1 → v2 ou v2 → v1)
#   4. Pousse un nouveau commit via l'API GitLab (PUT /repository/files/)
#   5. Argo CD detecte le commit et synchronise automatiquement
#
# =============================================================================
set -e

TARGET="${1:-v2}"
GITLAB_NS="gitlab"
GITLAB_URL="http://localhost:8929"
PROJECT="root%2Fiot-wil-app"   # URL-encoded "root/iot-wil-app"

# Version source = l'inverse de la cible
case "$TARGET" in
    v1) FROM="v2" ;;
    v2) FROM="v1" ;;
    *)  echo "Usage: $0 v1|v2"; exit 1 ;;
esac

echo "Changement : wil42/playground:${FROM} → wil42/playground:${TARGET}"

# === RECUPERATION DU TOKEN ===
# Le token a ete sauvegarde dans un Secret Kubernetes par deploy.sh.
# On le lit directement plutot que de regenerer via rails runner.
GL_TOKEN=$(kubectl get secret gitlab-iot-token \
    -n "$GITLAB_NS" \
    -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null || true)

if [ -z "$GL_TOKEN" ]; then
    echo "ERREUR : token GitLab introuvable (Secret gitlab-iot-token absent)."
    echo "  Lance 'make up' pour initialiser l'environnement."
    exit 1
fi

# === RECUPERATION DU FICHIER ACTUEL ===
# L'API retourne : { "content": "<base64>", "encoding": "base64", ... }
# On decode le base64 pour obtenir le YAML clair.
FILE_RESP=$(curl -sf \
    "${GITLAB_URL}/api/v4/projects/${PROJECT}/repository/files/deployment.yaml?ref=main" \
    -H "PRIVATE-TOKEN: $GL_TOKEN")

CURRENT_CONTENT=$(echo "$FILE_RESP" | jq -r '.content' | base64 -d 2>/dev/null)

if [ -z "$CURRENT_CONTENT" ]; then
    echo "ERREUR : deployment.yaml introuvable dans le repo GitLab."
    echo "  Lance 'make up' pour l'initialiser."
    exit 1
fi

# Verifie que la version source est bien presente
if ! echo "$CURRENT_CONTENT" | grep -q "playground:${FROM}"; then
    echo "  L'image est peut-etre deja en ${TARGET} ou dans un etat inattendu."
    echo "  Contenu actuel :"
    echo "$CURRENT_CONTENT" | grep "image:" || true
    exit 0
fi

# === MODIFICATION DU CONTENU ===
NEW_CONTENT=$(echo "$CURRENT_CONTENT" | \
    sed "s|wil42/playground:${FROM}|wil42/playground:${TARGET}|g")

# === PUSH VIA L'API GITLAB ===
# PUT /repository/files/ = git add + commit + push en une seule requete.
# jq construit le JSON proprement pour eviter les problemes d'echappement
# (base64 peut contenir des +, /, = qui casseraient un JSON mal echappe).
PUSH_BODY=$(jq -n \
    --arg branch  "main" \
    --arg content "$(echo "$NEW_CONTENT" | base64 -w0)" \
    --arg msg     "feat: switch to wil42/playground:${TARGET}" \
    '{branch: $branch, content: $content, encoding: "base64", commit_message: $msg}')

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -X PUT "${GITLAB_URL}/api/v4/projects/${PROJECT}/repository/files/deployment.yaml" \
    -H "PRIVATE-TOKEN: $GL_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PUSH_BODY")

if [ "$HTTP_STATUS" = "200" ]; then
    echo "  Commit pousse dans GitLab (HTTP 200 OK)."
    echo ""
    echo "  Argo CD va detecter ce commit dans ~3 minutes (polling interval)."
    echo "  Pour forcer la synchro immediatement :"
    echo "    kubectl annotate app wil-app -n argocd argocd.argoproj.io/refresh=normal"
    echo ""
    echo "  Verification : curl http://localhost:8888"
else
    echo "ERREUR : push GitLab HTTP $HTTP_STATUS"
    exit 1
fi
