#!/bin/bash
# Test script P1 - vérifie les exigences du sujet depuis le host

# === CONFIGURATION ===

# Chemin vers le dossier kvm dans goinfre (stockage persistant sur les machines 42)
GOINFRE="/goinfre/$(whoami)/kvm"

# Clé SSH privée générée par make setup, injectée dans les VMs via cloud-init
SSH_KEY="$GOINFRE/ssh/id_rsa"

# Options SSH communes : pas de vérif de fingerprint, pas de known_hosts,
# timeout 5s, authentification par clé uniquement (BatchMode=yes = pas de prompt)
SSH_BASE="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -i $SSH_KEY"

# Ports SSH forwardés par QEMU depuis le host vers les VMs
SERVER_PORT=2222  # host:2222 → loginS:22
WORKER_PORT=2223  # host:2223 → loginSW:22

# Noms des VMs construits depuis le login Unix ($USER = pschemit → pschemitS / pschemitSW)
SERVER_NAME="$(whoami)S"
WORKER_NAME="$(whoami)SW"

# Temps max d'attente (en secondes) pour chaque check qui peut prendre du temps
# (K3s install, netplan apply, SSH boot...) avant de déclarer un échec
TIMEOUT=300

# === COULEURS TERMINAL ===
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
RESET="\033[0m"

# Fonctions d'affichage avec symboles ✓ / ✗ / …
pass() { echo -e "${GREEN}[✓]${RESET} $1"; }
fail() { echo -e "${RED}[✗]${RESET} $1"; }
wait_msg() { echo -e "${YELLOW}[…]${RESET} $1"; }

# === FONCTIONS SSH ===

# Exécute une commande sur le serveur via SSH (port 2222)
# BatchMode=yes : échoue immédiatement si l'auth par clé ne marche pas (pas de prompt)
ssh_server() { ssh $SSH_BASE -o BatchMode=yes -p $SERVER_PORT vagrant@localhost "$1" 2>/dev/null; }

# Même chose pour le worker (port 2223)
ssh_worker() { ssh $SSH_BASE -o BatchMode=yes -p $WORKER_PORT vagrant@localhost "$1" 2>/dev/null; }

# === FONCTIONS D'ATTENTE ===

# Attend qu'une commande shell renvoie exactement la valeur $expected
# Réessaie toutes les 5s jusqu'à $TIMEOUT secondes
# $1 = description affiché pendant l'attente
# $2 = commande shell à évaluer (string, passée à eval)
# $3 = valeur attendue en retour
wait_for() {
    local desc="$1"
    local cmd="$2"
    local expected="$3"
    local elapsed=0
    while [ $elapsed -lt $TIMEOUT ]; do
        result=$(eval "$cmd" 2>/dev/null)
        if [ "$result" = "$expected" ]; then
            return 0  # succès
        fi
        wait_msg "$desc (${elapsed}s)..."
        sleep 5
        elapsed=$((elapsed + 5))
    done
    return 1  # timeout
}

# Attend que SSH réponde sur le port donné (la VM peut mettre du temps à booter)
# Tente un simple "exit" sans commande - si SSH répond, c'est bon
wait_ssh() {
    local port="$1"
    local name="$2"
    local elapsed=0
    while [ $elapsed -lt $TIMEOUT ]; do
        ssh $SSH_BASE -o BatchMode=yes -p "$port" vagrant@localhost "exit" 2>/dev/null && return 0
        wait_msg "SSH $name pas encore prêt (${elapsed}s)..."
        sleep 5
        elapsed=$((elapsed + 5))
    done
    return 1
}

# === DÉBUT DES TESTS ===
echo "========================================="
echo "  P1 - Tests Inception of Things"
echo "========================================="
echo ""

# --- CHECK 1 : VMs en cours d'exécution ---
# Vérifie que les fichiers PID existent et que les processus QEMU sont vivants
# kill -0 PID = envoie signal 0 = vérifie juste si le processus existe, sans le tuer
echo "[ VMs ]"
PIDS="$GOINFRE/pids"
if [ -f "$PIDS/$SERVER_NAME.pid" ] && kill -0 "$(cat $PIDS/$SERVER_NAME.pid)" 2>/dev/null; then
    pass "$SERVER_NAME est running"
else
    fail "$SERVER_NAME n'est pas running"; exit 1  # inutile de continuer sans les VMs
fi
if [ -f "$PIDS/$WORKER_NAME.pid" ] && kill -0 "$(cat $PIDS/$WORKER_NAME.pid)" 2>/dev/null; then
    pass "$WORKER_NAME est running"
else
    fail "$WORKER_NAME n'est pas running"; exit 1
fi
echo ""

# --- CHECK 2 : SSH sans mot de passe ---
# Le sujet impose SSH sans mot de passe.
# On utilise BatchMode=yes pour que SSH échoue immédiatement si une clé est requise
# mais absente, plutôt que d'attendre un prompt de mot de passe.
# On attend car la VM peut prendre ~30-60s à démarrer sshd après le boot.
echo "[ SSH sans mot de passe ]"
if wait_ssh $SERVER_PORT $SERVER_NAME; then
    pass "SSH $SERVER_NAME (port $SERVER_PORT) sans mot de passe"
else
    fail "SSH $SERVER_NAME (port $SERVER_PORT) sans mot de passe (timeout)"
fi
if wait_ssh $WORKER_PORT $WORKER_NAME; then
    pass "SSH $WORKER_NAME (port $WORKER_PORT) sans mot de passe"
else
    fail "SSH $WORKER_NAME (port $WORKER_PORT) sans mot de passe (timeout)"
fi
echo ""

# --- CHECK 3 : Hostnames ---
# Le sujet impose loginS et loginSW comme hostname (avec le login du binôme).
# On exécute "hostname" dans chaque VM et on compare au nom attendu.
echo "[ Hostnames ]"
if wait_for "hostname server" "ssh_server hostname" "$SERVER_NAME"; then
    pass "Hostname server = '$SERVER_NAME'"
else
    fail "Hostname server attendu '$SERVER_NAME', obtenu '$(ssh_server hostname)'"
fi
if wait_for "hostname worker" "ssh_worker hostname" "$WORKER_NAME"; then
    pass "Hostname worker = '$WORKER_NAME'"
else
    fail "Hostname worker attendu '$WORKER_NAME', obtenu '$(ssh_worker hostname)'"
fi
echo ""

# --- CHECK 4 : IPs privées ---
# Le sujet impose 192.168.56.110 sur le serveur et 192.168.56.111 sur le worker.
# Ces IPs sont sur l'interface ens4 (réseau multicast QEMU entre les deux VMs).
# On filtre "ip addr" sur le préfixe 192.168.56 et on extrait l'IP sans le masque CIDR.
echo "[ IPs 192.168.56.x ]"
get_ip_s() { ssh_server "ip -4 addr show | grep 192.168.56 | awk '{print \$2}' | cut -d/ -f1"; }
get_ip_w() { ssh_worker "ip -4 addr show | grep 192.168.56 | awk '{print \$2}' | cut -d/ -f1"; }

if wait_for "IP server 192.168.56.110" "get_ip_s" "192.168.56.110"; then
    pass "$SERVER_NAME IP privée = 192.168.56.110"
else
    fail "$SERVER_NAME IP privée attendue '192.168.56.110', obtenue '$(get_ip_s)'"
fi
if wait_for "IP worker 192.168.56.111" "get_ip_w" "192.168.56.111"; then
    pass "$WORKER_NAME IP privée = 192.168.56.111"
else
    fail "$WORKER_NAME IP privée attendue '192.168.56.111', obtenue '$(get_ip_w)'"
fi
echo ""

# --- CHECK 5 : Services K3s ---
# Le sujet impose K3s en mode controller sur le serveur et en mode agent sur le worker.
# - Sur le serveur : le service systemd s'appelle "k3s"
# - Sur le worker  : le service systemd s'appelle "k3s-agent"
# "systemctl is-active" renvoie "active" si le service tourne, sinon "inactive"/"failed"/etc.
# On attend car K3s peut prendre plusieurs minutes à démarrer (téléchargement, init).
echo "[ K3s ]"
get_k3s_s() { ssh_server "systemctl is-active k3s 2>/dev/null"; }
get_k3s_w() { ssh_worker "systemctl is-active k3s-agent 2>/dev/null"; }

if wait_for "k3s server actif" "get_k3s_s" "active"; then
    pass "K3s server (k3s.service) actif sur $SERVER_NAME"
else
    fail "K3s server inactif sur $SERVER_NAME (status: $(get_k3s_s))"
fi
if wait_for "k3s agent actif" "get_k3s_w" "active"; then
    pass "K3s agent (k3s-agent.service) actif sur $WORKER_NAME"
else
    fail "K3s agent inactif sur $WORKER_NAME (status: $(get_k3s_w))"
fi
echo ""

# --- CHECK 6 : Cluster K3s ---
# On vérifie que les deux nodes apparaissent bien dans le cluster avec le status "Ready".
# Kubernetes force les noms de nodes en lowercase → pschemitS devient pschemits.
# On interroge kubectl sur le serveur (seul le serveur a les droits admin sur le cluster).
# On attend car le worker peut prendre ~1-2min après le démarrage du service pour s'enregistrer.
echo "[ Cluster K3s ]"
SERVER_K8S="${SERVER_NAME,,}"  # lowercase bash : pschemitS → pschemits
WORKER_K8S="${WORKER_NAME,,}"  # lowercase bash : pschemitSW → pschemitsw

# Récupère la liste des nodes avec leur status (colonnes NAME STATUS)
get_nodes() { ssh_server "sudo kubectl get nodes --no-headers 2>/dev/null | awk '{print \$1, \$2}'"; }

# Attend qu'un node spécifique soit Ready dans le cluster
wait_node_ready() {
    local node="$1"
    local elapsed=0
    while [ $elapsed -lt $TIMEOUT ]; do
        result=$(get_nodes 2>/dev/null)
        # grep -qi = case-insensitive, vérifie présence du node ET son status Ready
        if echo "$result" | grep -qi "$node" && echo "$result" | grep -i "$node" | grep -q "Ready"; then
            return 0
        fi
        wait_msg "$node dans le cluster (${elapsed}s)..."
        sleep 5
        elapsed=$((elapsed + 5))
    done
    return 1
}

if wait_node_ready "$SERVER_K8S"; then
    pass "$SERVER_NAME présent dans le cluster (Ready)"
else
    fail "$SERVER_NAME absent ou NotReady dans le cluster"
fi
if wait_node_ready "$WORKER_K8S"; then
    pass "$WORKER_NAME présent dans le cluster (Ready)"
else
    fail "$WORKER_NAME absent ou NotReady dans le cluster"
fi

# Affichage final du cluster pour confirmation visuelle
echo ""
echo "========================================="
echo "  kubectl get nodes (depuis $SERVER_NAME)"
echo "========================================="
ssh_server "sudo kubectl get nodes"
