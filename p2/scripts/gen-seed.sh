#!/bin/bash
# gen-seed.sh - Génère une ISO cloud-init pour boostraper une VM au premier démarrage
#
# cloud-init est un standard de provisionnement de VMs : au boot, la VM lit
# une ISO étiquetée "cidata" et exécute les instructions qu'elle contient
# (créer des users, configurer le réseau, monter des disques, lancer des scripts...).
# C'est l'équivalent de ce que Vagrant faisait avec son Vagrantfile + provider VirtualBox.
#
# Usage: gen-seed.sh hostname private_ip private_mac nat_mac output_iso setup_script pubkey

# set -e : arrête le script immédiatement si une commande échoue
set -e

# === ARGUMENTS ===
HOSTNAME=$1       # Nom de la VM (ex: pschemitS)
PRIVATE_IP=$2     # IP fixe sur le réseau privé inter-VMs (ex: 192.168.56.110)
PRIVATE_MAC=$3    # Adresse MAC de l'interface réseau privée (ex: 52:54:00:12:34:01)
NAT_MAC=$4        # Adresse MAC de l'interface NAT/internet (ex: 52:54:00:ab:cd:01)
OUTPUT_ISO=$5     # Chemin de sortie de l'ISO générée
SETUP_SCRIPT=$6   # Chemin vers setup_server.sh ou setup_worker.sh à embarquer
PUBKEY=$(cat "$7") # Clé publique SSH à injecter dans la VM (lit le fichier .pub)

# === DOSSIER TEMPORAIRE ===
# mktemp -d crée un dossier temporaire unique (/tmp/tmp.XXXXXX)
# trap garantit qu'il sera supprimé à la fin du script, même en cas d'erreur
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# === ENCODAGE DU SCRIPT DE PROVISIONNING ===
# cloud-init ne peut pas lire des fichiers externes : on encode le script en base64
# pour l'embarquer directement dans le fichier user-data (format texte).
# -w 0 = pas de retour à la ligne dans l'encodage (cloud-init le veut sur une seule ligne)
SETUP_CONTENT=$(base64 -w 0 "$SETUP_SCRIPT")

# === meta-data ===
# Fichier obligatoire pour cloud-init. instance-id doit être unique pour que
# cloud-init re-exécute sa config si on recrée la VM avec le même nom.
cat > "$TMPDIR/meta-data" <<EOF
instance-id: $HOSTNAME
local-hostname: $HOSTNAME
EOF

# === user-data ===
# Fichier principal cloud-init (format YAML). Contient toute la configuration
# à appliquer au premier boot de la VM.
cat > "$TMPDIR/user-data" <<EOF
#cloud-config
hostname: $HOSTNAME

# Création de l'utilisateur "vagrant" (nom standard pour les VMs de dev)
# sudo sans mot de passe → les scripts de provisionning peuvent utiliser sudo librement
# lock_passwd: true + ssh_pwauth: false → connexion par clé SSH uniquement (sujet impose pas de mdp)
# ssh_authorized_keys : injecte notre clé publique générée par make setup
users:
  - name: vagrant
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - $PUBKEY

ssh_pwauth: false

# Montage du dossier partagé host↔VM via le protocole 9p (VirtFS)
# "shared" est le tag QEMU déclaré avec -virtfs dans le Makefile
# /vagrant = chemin de montage dans la VM (même convention que Vagrant)
# nofail = ne bloque pas le boot si le montage échoue
mounts:
  - ["shared", "/vagrant", "9p", "trans=virtio,version=9p2000.L,nofail", "0", "0"]

write_files:
  # Le script de provisionning (setup_server.sh ou setup_worker.sh) est décodé
  # depuis le base64 et écrit dans /tmp/provision.sh avant l'exécution
  - path: /tmp/provision.sh
    permissions: '0755'
    encoding: b64
    content: $SETUP_CONTENT

  # Configuration réseau netplan pour Ubuntu.
  # On identifie chaque interface par son adresse MAC (plus fiable que le nom ens3/ens4
  # qui peut changer selon l'ordre de détection des périphériques).
  # - nat0 : interface NAT QEMU (accès internet, IP dynamique DHCP 10.0.2.x)
  # - priv0 : interface réseau privée inter-VMs (IP fixe 192.168.56.x)
  # permissions 0600 : netplan refuse les fichiers lisibles par tous
  - path: /etc/netplan/99-private.yaml
    permissions: '0600'
    content: |
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

# Commandes exécutées en root au premier boot, dans l'ordre :
runcmd:
  # Applique la config réseau netplan écrite ci-dessus (monte l'interface privée avec l'IP fixe)
  - netplan apply
  # Crée le point de montage /vagrant s'il n'existe pas déjà
  - mkdir -p /vagrant
  # Monte le dossier partagé 9p (|| true = continue même si déjà monté via fstab/mounts)
  - mount -t 9p -o trans=virtio,version=9p2000.L shared /vagrant || true
  # Lance le script de provisionning K3s
  - /tmp/provision.sh
EOF

# === CRÉATION DE L'ISO ===
# xorriso crée une ISO au format attendu par cloud-init :
# -volid cidata : label obligatoire, cloud-init ne lit que les ISOs avec ce label exact
# -joliet -rock : formats de noms de fichiers (Joliet = Windows, Rock Ridge = Unix)
# Les deux fichiers user-data et meta-data sont mis à la racine de l'ISO
xorriso -as mkisofs \
    -output "$OUTPUT_ISO" \
    -volid cidata \
    -joliet -rock \
    "$TMPDIR/user-data" "$TMPDIR/meta-data" \
    2>/dev/null

echo "Seed ISO créée: $OUTPUT_ISO"
