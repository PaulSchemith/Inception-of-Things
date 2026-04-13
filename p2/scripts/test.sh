#!/bin/bash
# Test script P2 - vérifie les exigences du sujet depuis le host

GOINFRE="/goinfre/$(whoami)/kvm-p2"
SSH_KEY="/goinfre/$(whoami)/kvm/ssh/id_rsa"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -i $SSH_KEY"
SSH_PORT=2224       # Port SSH forwardé par QEMU (host:2224 → VM:22)
APP_PORT=8081       # Port HTTP forwardé (host:8081 → VM:80 → Traefik ingress)
SERVER_NAME="$(whoami)S"
TIMEOUT=120

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
RESET="\033[0m"

pass() { echo -e "${GREEN}[✓]${RESET} $1"; }
fail() { echo -e "${RED}[✗]${RESET} $1"; }
wait_msg() { echo -e "${YELLOW}[…]${RESET} $1"; }

ssh_vm() { ssh $SSH_OPTS -o BatchMode=yes -p $SSH_PORT vagrant@localhost "$1" 2>/dev/null; }

wait_for() {
    local desc="$1" cmd="$2" expected="$3" elapsed=0
    while [ $elapsed -lt $TIMEOUT ]; do
        [ "$(eval "$cmd" 2>/dev/null)" = "$expected" ] && return 0
        wait_msg "$desc (${elapsed}s)..."
        sleep 5; elapsed=$((elapsed + 5))
    done
    return 1
}

wait_ssh() {
    local elapsed=0
    while [ $elapsed -lt $TIMEOUT ]; do
        ssh $SSH_OPTS -o BatchMode=yes -p $SSH_PORT vagrant@localhost "exit" 2>/dev/null && return 0
        wait_msg "SSH pas encore prêt (${elapsed}s)..."
        sleep 5; elapsed=$((elapsed + 5))
    done
    return 1
}

echo "========================================="
echo "  P2 - Tests Inception of Things"
echo "========================================="
echo ""

# --- VM running ---
echo "[ VM ]"
PIDS="$GOINFRE/pids"
if [ -f "$PIDS/$SERVER_NAME.pid" ] && kill -0 "$(cat $PIDS/$SERVER_NAME.pid)" 2>/dev/null; then
    pass "$SERVER_NAME est running"
else
    fail "$SERVER_NAME n'est pas running"; exit 1
fi
echo ""

# --- SSH sans mot de passe ---
echo "[ SSH sans mot de passe ]"
if wait_ssh; then
    pass "SSH $SERVER_NAME (port $SSH_PORT) sans mot de passe"
else
    fail "SSH $SERVER_NAME (port $SSH_PORT) - timeout"; exit 1
fi
echo ""

# --- Hostname ---
echo "[ Hostname ]"
if wait_for "hostname" "ssh_vm hostname" "$SERVER_NAME"; then
    pass "Hostname = '$SERVER_NAME'"
else
    fail "Hostname attendu '$SERVER_NAME', obtenu '$(ssh_vm hostname)'"
fi
echo ""

# --- IP privée ---
echo "[ IP 192.168.56.110 ]"
get_ip() { ssh_vm "ip -4 addr show | grep 192.168.56 | awk '{print \$2}' | cut -d/ -f1"; }
if wait_for "IP 192.168.56.110" "get_ip" "192.168.56.110"; then
    pass "IP privée = 192.168.56.110"
else
    fail "IP privée attendue '192.168.56.110', obtenue '$(get_ip)'"
fi
echo ""

# --- K3s server ---
echo "[ K3s server ]"
get_k3s() { ssh_vm "systemctl is-active k3s 2>/dev/null"; }
if wait_for "k3s actif" "get_k3s" "active"; then
    pass "K3s server actif"
else
    fail "K3s server inactif (status: $(get_k3s))"
fi
echo ""

# --- Deployments et pods ---
echo "[ Deployments ]"

wait_deploy_ready() {
    local name="$1" expected_replicas="$2" elapsed=0
    while [ $elapsed -lt $TIMEOUT ]; do
        ready=$(ssh_vm "sudo kubectl get deployment $name -o jsonpath='{.status.readyReplicas}' 2>/dev/null")
        [ "$ready" = "$expected_replicas" ] && return 0
        wait_msg "$name ready: $ready/$expected_replicas (${elapsed}s)..."
        sleep 5; elapsed=$((elapsed + 5))
    done
    return 1
}

if wait_deploy_ready "app1" "1"; then
    pass "app1 : 1/1 replica Ready"
else
    fail "app1 : pas prêt"
fi

if wait_deploy_ready "app2" "3"; then
    pass "app2 : 3/3 replicas Ready (sujet impose 3)"
else
    fail "app2 : pas 3 replicas prêts ($(ssh_vm "sudo kubectl get deployment app2 -o jsonpath='{.status.readyReplicas}' 2>/dev/null")/3)"
fi

if wait_deploy_ready "app3" "1"; then
    pass "app3 : 1/1 replica Ready"
else
    fail "app3 : pas prêt"
fi
echo ""

# --- Ingress existe ---
echo "[ Ingress ]"
ingress=$(ssh_vm "sudo kubectl get ingress ingress --no-headers 2>/dev/null | awk '{print \$1}'")
if [ "$ingress" = "ingress" ]; then
    pass "Ingress 'ingress' existe"
    ssh_vm "sudo kubectl get ingress"
else
    fail "Ingress introuvable"
fi
echo ""

# --- Routing HTTP ---
echo "[ Routing via Host header → http://localhost:$APP_PORT ]"

wait_http() {
    local host="$1" expected="$2" elapsed=0
    while [ $elapsed -lt $TIMEOUT ]; do
        if [ -n "$host" ]; then
            result=$(curl -s --max-time 3 -H "Host: $host" http://localhost:$APP_PORT 2>/dev/null)
        else
            result=$(curl -s --max-time 3 http://localhost:$APP_PORT 2>/dev/null)
        fi
        echo "$result" | grep -q "$expected" && return 0
        wait_msg "HTTP ${host:-'(no host)'} pas encore prêt (${elapsed}s)..."
        sleep 5; elapsed=$((elapsed + 5))
    done
    return 1
}

if wait_http "app1.com" "APP1"; then
    pass "Host: app1.com → APP1"
else
    fail "Host: app1.com → réponse inattendue: $(curl -s -H 'Host: app1.com' http://localhost:$APP_PORT 2>/dev/null)"
fi

if wait_http "app2.com" "APP2"; then
    pass "Host: app2.com → APP2"
else
    fail "Host: app2.com → réponse inattendue"
fi

if wait_http "" "APP3"; then
    pass "Host: (aucun) → APP3 (défaut)"
else
    fail "Host: (aucun) → APP3 attendu, obtenu: $(curl -s http://localhost:$APP_PORT 2>/dev/null)"
fi

if wait_http "random.com" "APP3"; then
    pass "Host: random.com → APP3 (défaut)"
else
    fail "Host: random.com → APP3 attendu"
fi

echo ""
echo "========================================="
echo "  kubectl get all (depuis $SERVER_NAME)"
echo "========================================="
ssh_vm "sudo kubectl get pods,svc,ingress"
