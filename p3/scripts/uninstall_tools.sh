#!/bin/bash
set -euo pipefail

echo "===== Cleaning k3d cluster (if exists) ====="

if command -v k3d >/dev/null 2>&1; then
    k3d cluster delete my-cluster || true
fi

echo "✅ Cleanup finished"
