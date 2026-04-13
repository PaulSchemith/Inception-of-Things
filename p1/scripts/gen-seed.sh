#!/bin/bash
# Génère une ISO cloud-init pour le provisionnement d'une VM
# Usage: gen-seed.sh hostname private_ip private_mac nat_mac output_iso setup_script
set -e

HOSTNAME=$1
PRIVATE_IP=$2
PRIVATE_MAC=$3
NAT_MAC=$4
OUTPUT_ISO=$5
SETUP_SCRIPT=$6

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Encode le script de provisionnement en base64
SETUP_CONTENT=$(base64 -w 0 "$SETUP_SCRIPT")

cat > "$TMPDIR/meta-data" <<EOF
instance-id: $HOSTNAME
local-hostname: $HOSTNAME
EOF

cat > "$TMPDIR/user-data" <<EOF
#cloud-config
hostname: $HOSTNAME

users:
  - name: vagrant
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    plain_text_passwd: 'vagrant'
    lock_passwd: false

ssh_pwauth: true

network:
  version: 2
  ethernets:
    nat0:
      match:
        macaddress: "$NAT_MAC"
      dhcp4: true
    priv0:
      match:
        macaddress: "$PRIVATE_MAC"
      dhcp4: false
      addresses:
        - $PRIVATE_IP/24

mounts:
  - ["shared", "/vagrant", "9p", "trans=virtio,version=9p2000.L,nofail", "0", "0"]

write_files:
  - path: /tmp/provision.sh
    permissions: '0755'
    encoding: b64
    content: $SETUP_CONTENT

runcmd:
  - mkdir -p /vagrant
  - mount -t 9p -o trans=virtio,version=9p2000.L shared /vagrant || true
  - /tmp/provision.sh
EOF

xorriso -as mkisofs \
    -output "$OUTPUT_ISO" \
    -volid cidata \
    -joliet -rock \
    "$TMPDIR/user-data" "$TMPDIR/meta-data" \
    2>/dev/null

echo "Seed ISO créée: $OUTPUT_ISO"
