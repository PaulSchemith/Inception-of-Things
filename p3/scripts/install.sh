#!/bin/bash
set -e

echo "[+] Installing tools in user space (no sudo)"

BIN_DIR="$HOME/bin"
mkdir -p "$BIN_DIR"

# Ensure PATH
if ! echo "$PATH" | grep -q "$BIN_DIR"; then
  echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
  export PATH="$HOME/bin:$PATH"
fi

################################
# kubectl
################################
echo "[+] Installing kubectl"
K8S_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)
curl -sL "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/amd64/kubectl" -o kubectl
chmod +x kubectl
mv kubectl "$BIN_DIR/"

################################
# k3d (manual binary install)
################################
echo "[+] Installing k3d (manual binary)"
K3D_VERSION=$(curl -s https://api.github.com/repos/k3d-io/k3d/releases/latest | grep tag_name | cut -d '"' -f 4)

curl -sL \
"https://github.com/k3d-io/k3d/releases/download/${K3D_VERSION}/k3d-linux-amd64" \
-o k3d

chmod +x k3d
mv k3d "$BIN_DIR/"

################################
# Checks
################################
echo "[+] Checking versions"
kubectl version --client
k3d version
docker version

echo "[+] Installation finished successfully"
