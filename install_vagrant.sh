#!/bin/sh
set -eu

# Version récente de Vagrant compatible VirtualBox 7
VAGRANT="https://releases.hashicorp.com/vagrant/2.4.9/vagrant_2.4.9_linux_amd64.zip"
DEST="$HOME/bin"

mkdir -p "$DEST"

# Télécharger le zip
wget -O /tmp/vagrant.zip "$VAGRANT"

# Dézipper dans ~/bin
unzip -o /tmp/vagrant.zip -d "$DEST"

# Rendre exécutable
chmod +x "$DEST/vagrant"

# Ajouter ~/bin au PATH pour cette session
export PATH="$DEST:$PATH"

# Vérifier
"$DEST/vagrant" --version

# Installer autocompletion (optionnel)
"$DEST/vagrant" autocomplete install 1> /dev/null
