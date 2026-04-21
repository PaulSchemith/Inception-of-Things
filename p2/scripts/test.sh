#!/bin/bash
# ==============================================================================
# P2 - TEST SCRIPT
# Vérifie les exigences du sujet Inception of Things - Part 2
# ==============================================================================

set -u

LOGIN="${P2_LOGIN:-$(whoami)}"
SERVER_NAME="${LOGIN}S"
SERVER_IP="192.168.56.110"
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
ssh_vm() { vagrant ssh "$SERVER_NAME" -c "$1" 2>/dev/null | strip_ansi; }

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
        sleep 5; elapsed=$((elapsed + 5))
    done
    return 1
}

wait_deploy_ready() {
    local name="$1" expected="$2" elapsed=0 ready
    while [ "$elapsed" -lt "$TIMEOUT" ]; do
        ready=$(ssh_vm "sudo kubectl get deployment $name -o jsonpath='{.status.readyReplicas}' 2>/dev/null")
        [ "$ready" = "$expected" ] && return 0
        warn "$name: $ready/$expected ready... (${elapsed}s)"
        sleep 5; elapsed=$((elapsed + 5))
    done
    return 1
}

wait_http() {
    local host="$1" expected="$2" elapsed=0 result
    while [ "$elapsed" -lt "$TIMEOUT" ]; do
        if [ -n "$host" ]; then
            result=$(curl -s --max-time 3 -H "Host: $host" "http://$SERVER_IP" 2>/dev/null)
        else
            result=$(curl -s --max-time 3 "http://$SERVER_IP" 2>/dev/null)
        fi
        echo "$result" | grep -q "$expected" && return 0
        warn "HTTP ${host:-(no host)} → $expected... (${elapsed}s)"
        sleep 5; elapsed=$((elapsed + 5))
    done
    return 1
}

echo "========================================="
echo "  P2 - Tests Inception of Things"
echo "========================================="
echo ""

echo "[ VM Vagrant ]"
if [ "$(vagrant_state "$SERVER_NAME")" = "running" ]; then
    pass "$SERVER_NAME est running"
else
    fail "$SERVER_NAME n'est pas running"; exit 1
fi
echo ""

echo "[ SSH sans mot de passe ]"
if ssh_vm "exit 0" >/dev/null; then
    pass "SSH OK vers $SERVER_NAME"
else
    fail "SSH KO vers $SERVER_NAME"; exit 1
fi
echo ""

echo "[ Hostname ]"
if wait_for "hostname" "ssh_vm hostname" "$SERVER_NAME"; then
    pass "Hostname = $SERVER_NAME"
else
    fail "Hostname incorrect (obtenu: $(ssh_vm hostname))"
fi
echo ""

echo "[ IP 192.168.56.110 ]"
get_ip() { ssh_vm "ip -4 addr show | grep '192\.168\.56' | awk '{print \$2}' | cut -d/ -f1 | head -1"; }
if wait_for "IP $SERVER_IP" "get_ip" "$SERVER_IP"; then
    pass "IP = $SERVER_IP"
else
    fail "IP incorrecte (obtenu: $(get_ip))"
fi
echo ""

echo "[ K3s server ]"
get_k3s() { ssh_vm "systemctl is-active k3s 2>/dev/null"; }
if wait_for "k3s actif" "get_k3s" "active"; then
    pass "K3s server actif"
else
    fail "K3s server inactif (status: $(get_k3s))"
fi
echo ""

echo "[ kubectl ]"
if ssh_vm "which kubectl >/dev/null 2>&1"; then
    pass "kubectl installé"
else
    fail "kubectl absent"
fi
echo ""

echo "[ Deployments ]"
if wait_deploy_ready "app1" "1"; then
    pass "app1 : 1/1 replica Ready"
else
    fail "app1 : pas prêt"
fi
if wait_deploy_ready "app2" "3"; then
    pass "app2 : 3/3 replicas Ready"
else
    fail "app2 : pas 3 replicas prêts"
fi
if wait_deploy_ready "app3" "1"; then
    pass "app3 : 1/1 replica Ready"
else
    fail "app3 : pas prêt"
fi
echo ""

echo "[ Ingress ]"
ingress=$(ssh_vm "sudo kubectl get ingress ingress --no-headers 2>/dev/null | awk '{print \$1}'")
if [ "$ingress" = "ingress" ]; then
    pass "Ingress 'ingress' existe"
    ssh_vm "sudo kubectl get ingress"
else
    fail "Ingress introuvable"
fi
echo ""

echo "[ Routing HTTP → http://$SERVER_IP ]"
if wait_http "app1.com" "APP1"; then
    pass "Host: app1.com → APP1"
else
    fail "Host: app1.com → réponse inattendue"
fi
if wait_http "app2.com" "APP2"; then
    pass "Host: app2.com → APP2"
else
    fail "Host: app2.com → réponse inattendue"
fi
if wait_http "random.com" "APP3"; then
    pass "Host: random.com → APP3 (catch-all)"
else
    fail "Host: random.com → APP3 attendu"
fi
if wait_http "" "APP3"; then
    pass "Host: (aucun) → APP3 (catch-all)"
else
    fail "Host: (aucun) → APP3 attendu"
fi
echo ""

echo "========================================="
echo "  kubectl get all (depuis $SERVER_NAME)"
echo "========================================="
ssh_vm "sudo kubectl get pods,svc,ingress"

echo ""
echo "========================================="
echo "  Resultats : $PASS OK / $((PASS + FAIL)) tests"
echo "========================================="
[ "$FAIL" -eq 0 ]
