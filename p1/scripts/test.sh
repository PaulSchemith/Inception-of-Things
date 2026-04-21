#!/bin/bash
# ==============================================================================
# P1 - TEST SCRIPT (Vagrant + libvirt)
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

pass() { echo -e "${GREEN}[OK]${RESET} $1"; }
fail() { echo -e "${RED}[KO]${RESET} $1"; }
wait_msg() { echo -e "${YELLOW}[..]${RESET} $1"; }

ssh_server() { vagrant ssh "$SERVER_NAME" -c "$1" 2>/dev/null; }
ssh_worker() { vagrant ssh "$WORKER_NAME" -c "$1" 2>/dev/null; }

vagrant_state() {
    local machine="$1"
    vagrant status "$machine" --machine-readable 2>/dev/null | awk -F, '/,state,/ {state=$4} END {print state}'
}

wait_for() {
    local desc="$1"
    local cmd="$2"
    local expected="$3"
    local elapsed=0
    local result
    while [ "$elapsed" -lt "$TIMEOUT" ]; do
        result=$(eval "$cmd" 2>/dev/null)
        if [ "$result" = "$expected" ]; then
            return 0
        fi
        wait_msg "$desc (${elapsed}s)..."
        sleep 5
        elapsed=$((elapsed + 5))
    done
    return 1
}

wait_node_ready() {
    local node="$1"
    local elapsed=0
    local result
    while [ "$elapsed" -lt "$TIMEOUT" ]; do
        result=$(ssh_server "sudo kubectl get nodes --no-headers 2>/dev/null | awk '{print \\$1, \\$2}'")
        if echo "$result" | grep -qi "^${node}[[:space:]]\+Ready$"; then
            return 0
        fi
        wait_msg "$node dans le cluster (${elapsed}s)..."
        sleep 5
        elapsed=$((elapsed + 5))
    done
    return 1
}

echo "========================================="
echo "  P1 - Tests Inception of Things"
echo "========================================="
echo ""

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

echo "[ SSH via Vagrant ]"
if ssh_server "exit" >/dev/null; then
    pass "SSH OK vers $SERVER_NAME"
else
    fail "SSH KO vers $SERVER_NAME"; exit 1
fi
if ssh_worker "exit" >/dev/null; then
    pass "SSH OK vers $WORKER_NAME"
else
    fail "SSH KO vers $WORKER_NAME"; exit 1
fi
echo ""

echo "[ Hostnames ]"
if wait_for "hostname server" "ssh_server hostname" "$SERVER_NAME"; then
    pass "Hostname server = $SERVER_NAME"
else
    fail "Hostname server attendu $SERVER_NAME, obtenu $(ssh_server hostname)"
fi
if wait_for "hostname worker" "ssh_worker hostname" "$WORKER_NAME"; then
    pass "Hostname worker = $WORKER_NAME"
else
    fail "Hostname worker attendu $WORKER_NAME, obtenu $(ssh_worker hostname)"
fi
echo ""

echo "[ IPs 192.168.56.x ]"
get_ip_s() { ssh_server "ip -4 addr show | grep 192.168.56 | awk '{print \\$2}' | cut -d/ -f1"; }
get_ip_w() { ssh_worker "ip -4 addr show | grep 192.168.56 | awk '{print \\$2}' | cut -d/ -f1"; }

if wait_for "IP server 192.168.56.110" "get_ip_s" "192.168.56.110"; then
    pass "$SERVER_NAME IP privee = 192.168.56.110"
else
    fail "$SERVER_NAME IP privee attendue 192.168.56.110, obtenue $(get_ip_s)"
fi
if wait_for "IP worker 192.168.56.111" "get_ip_w" "192.168.56.111"; then
    pass "$WORKER_NAME IP privee = 192.168.56.111"
else
    fail "$WORKER_NAME IP privee attendue 192.168.56.111, obtenue $(get_ip_w)"
fi
echo ""

echo "[ K3s ]"
get_k3s_s() { ssh_server "systemctl is-active k3s 2>/dev/null"; }
get_k3s_w() { ssh_worker "systemctl is-active k3s-agent 2>/dev/null"; }

if wait_for "k3s server actif" "get_k3s_s" "active"; then
    pass "K3s server actif sur $SERVER_NAME"
else
    fail "K3s server inactif sur $SERVER_NAME (status: $(get_k3s_s))"
fi
if wait_for "k3s agent actif" "get_k3s_w" "active"; then
    pass "K3s agent actif sur $WORKER_NAME"
else
    fail "K3s agent inactif sur $WORKER_NAME (status: $(get_k3s_w))"
fi
echo ""

echo "[ Cluster K3s ]"
SERVER_K8S="${SERVER_NAME,,}"
WORKER_K8S="${WORKER_NAME,,}"

if wait_node_ready "$SERVER_K8S"; then
    pass "$SERVER_NAME present dans le cluster (Ready)"
else
    fail "$SERVER_NAME absent ou NotReady dans le cluster"
fi
if wait_node_ready "$WORKER_K8S"; then
    pass "$WORKER_NAME present dans le cluster (Ready)"
else
    fail "$WORKER_NAME absent ou NotReady dans le cluster"
fi

echo ""
echo "========================================="
echo "  kubectl get nodes (depuis $SERVER_NAME)"
echo "========================================="
ssh_server "sudo kubectl get nodes"
