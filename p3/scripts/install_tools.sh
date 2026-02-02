#!/bin/bash
set -euo pipefail

echo "===== Checking required tools for Part 3 ====="

check() {
    if command -v "$1" >/dev/null 2>&1; then
        echo "✅ $1 found"
    else
        echo "⚠️  $1 not found (environment limitation)"
    fi
}

check docker
check kubectl
check k3d

echo ""
echo "ℹ️ No system installation performed (42 compatible)"
echo "✅ Tool check finished"
