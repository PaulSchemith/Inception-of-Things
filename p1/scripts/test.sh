#!/bin/bash
# ==============================================================================
# P1 - TEST SCRIPT (Vagrant + libvirt)
# Verifie les exigences du sujet Inception of Things - Part 1
# ==============================================================================

set -u

LOGIN="${P1_LOGIN:-$(whoami)}"
SERVER_NAME="${LOGIN}S"
WORKER_NAME="${LOGIN}SW"
TIMEOUT=300

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
RESET="\033[0m"

PASS=0
FAIL=0

pass() { echo -e "${GREEN}[OK]${RESET} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}[KO]${RESET} $1"; FAIL=$((FAIL + 1)); }
warn() { echo -e "${YELLOW}[..]${RESET} $1"; }

strip_ansi() { sed 's/\x1b\[[0-9;]*[mGKHFABCDsuJKlh]//g' | tr -d '\r'; }
ssh_server() { vagrant ssh "$SERVER_NAME" -c "$1" 2>/dev/null | strip_ansi; }
ssh_worker() { vagrant ssh "$WORKER_NAME" -c "$1" 2>/dev/null | strip_ansi; }

vagrant_state() {
    vagrant status "$1" --machine-readable 2>/dev/null \
        | awk -F, '/,state,/ {print $4}'
}

wait_for() {
    local desc="$1" cmd="$2" expected="$3"
    local elapsed=0 result
    while [ "$elapsed" -lt "$TIMEOUT" ]; do
        result=$(eval "$cmd" 2>/dev/null | tail -1)
        [ "$result" = "$expected" ] && return 0
        warn "$desc... (${elapsed}s)"
        sleep 5
        elapsed=$((elapsed + 5))
    done
    return 1
}

wait_node_ready() {
    local node elapsed=0 result
    node=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    while [ "$elapsed" -lt "$TIMEOUT" ]; do
        result=$(ssh_server "sudo kubectl get nodes --no-headers 2>/dev/null" \
            | awk '{print $1, $2}' | grep -i "^${node} ")
        echo "$result" | grep -qi "Ready$" && return 0
        warn "$node dans le cluster... (${elapsed}s)"
        sleep 5
        elapsed=$((elapsed + 5))
    done
    return 1
}

echo "========================================="
echo "  P1 - Tests Inception of Things"
echo "========================================="
echo ""

# --- VMs en cours d'execution ---
echo "[ VMs Vagrant ]"
if [ "$(vagrant_state "$SERVER_NAME")" = "running" ]; then
    pass "$SERVER_NAME est running"
else
    fail "$SERVER_NAME n'est pas running"; exit 1
fi
if [ "$(vagrant_state "$WORKER_NAME")" = "running" ]; then
    pass "$WORKER_NAME est running"
else
    fail "$WORKER_NAME n'est pas running"; exit 1
fi
echo ""

# --- SSH sans mot de passe ---
echo "[ SSH sans mot de passe ]"
if ssh_server "exit 0" >/dev/null; then
    pass "SSH OK vers $SERVER_NAME"
else
    fail "SSH KO vers $SERVER_NAME"; exit 1
fi
if ssh_worker "exit 0" >/dev/null; then
    pass "SSH OK vers $WORKER_NAME"
else
    fail "SSH KO vers $WORKER_NAME"; exit 1
fi
echo ""

# --- Hostnames ---
echo "[ Hostnames ]"
if wait_for "hostname $SERVER_NAME" "ssh_server hostname" "$SERVER_NAME"; then
    pass "Hostname $SERVER_NAME correct"
else
    fail "Hostname $SERVER_NAME incorrect (obtenu: $(ssh_server hostname))"
fi
if wait_for "hostname $WORKER_NAME" "ssh_worker hostname" "$WORKER_NAME"; then
    pass "Hostname $WORKER_NAME correct"
else
    fail "Hostname $WORKER_NAME incorrect (obtenu: $(ssh_worker hostname))"
fi
echo ""

# --- IPs reseau prive ---
echo "[ IPs 192.168.56.x ]"
get_ip_s() { ssh_server "ip -4 addr show | grep '192\.168\.56' | awk '{print \$2}' | cut -d/ -f1 | head -1"; }
get_ip_w() { ssh_worker "ip -4 addr show | grep '192\.168\.56' | awk '{print \$2}' | cut -d/ -f1 | head -1"; }

if wait_for "IP $SERVER_NAME" "get_ip_s" "192.168.56.110"; then
    pass "$SERVER_NAME IP = 192.168.56.110"
else
    fail "$SERVER_NAME IP incorrecte (obtenu: $(get_ip_s))"
fi
if wait_for "IP $WORKER_NAME" "get_ip_w" "192.168.56.111"; then
    pass "$WORKER_NAME IP = 192.168.56.111"
else
    fail "$WORKER_NAME IP incorrecte (obtenu: $(get_ip_w))"
fi
echo ""

# --- K3s services ---
echo "[ K3s ]"
get_k3s_s() { ssh_server "systemctl is-active k3s 2>/dev/null"; }
get_k3s_w() { ssh_worker "systemctl is-active k3s-agent 2>/dev/null"; }

if wait_for "k3s server actif" "get_k3s_s" "active"; then
    pass "K3s server (controller) actif sur $SERVER_NAME"
else
    fail "K3s server inactif sur $SERVER_NAME (status: $(get_k3s_s))"
fi
if wait_for "k3s agent actif" "get_k3s_w" "active"; then
    pass "K3s agent (worker) actif sur $WORKER_NAME"
else
    fail "K3s agent inactif sur $WORKER_NAME (status: $(get_k3s_w))"
fi
echo ""

# --- kubectl installe ---
echo "[ kubectl ]"
if ssh_server "which kubectl >/dev/null 2>&1"; then
    pass "kubectl installe sur $SERVER_NAME"
else
    fail "kubectl absent sur $SERVER_NAME"
fi
if ssh_worker "which kubectl >/dev/null 2>&1"; then
    pass "kubectl installe sur $WORKER_NAME"
else
    fail "kubectl absent sur $WORKER_NAME"
fi
echo ""

# --- Cluster K3s (les deux noeuds Ready) ---
echo "[ Cluster K3s ]"
if wait_node_ready "$SERVER_NAME"; then
    pass "$SERVER_NAME present dans le cluster (Ready)"
else
    fail "$SERVER_NAME absent ou NotReady dans le cluster"
fi
if wait_node_ready "$WORKER_NAME"; then
    pass "$WORKER_NAME present dans le cluster (Ready)"
else
    fail "$WORKER_NAME absent ou NotReady dans le cluster"
fi

echo ""
echo "========================================="
echo "  kubectl get nodes (depuis $SERVER_NAME)"
echo "========================================="

ssh_server "sudo kubectl get nodes"

echo ""
echo "========================================="
echo "  Resultats : $PASS OK / $((PASS + FAIL)) tests"
echo "========================================="
[ "$FAIL" -eq 0 ]
