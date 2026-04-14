#!/bin/sh
# =============================================================================
# install_vagrant.sh - Installe Vagrant sans droits root (dans ~/bin)
# =============================================================================
#
# POURQUOI CE SCRIPT ?
#   Sur les machines 42, on n'a pas les droits root pour apt-get install vagrant.
#   Ce script installe Vagrant dans le dossier personnel (~/.bin) qui est
#   accessible en ecriture sans sudo.
#
# UTILISATION :
#   bash install_vagrant.sh
#   (Vagrant sera disponible dans cette session de terminal)
#
# NOTE :
#   Pour que Vagrant soit disponible dans les prochaines sessions, ajouter
#   ~/bin au PATH dans ~/.zshrc ou ~/.bashrc :
#     export PATH="$HOME/bin:$PATH"
#
# =============================================================================
set -eu

# Version de Vagrant a installer (compatible avec VirtualBox 7.x)
VAGRANT="https://releases.hashicorp.com/vagrant/2.4.9/vagrant_2.4.9_linux_amd64.zip"

# Dossier d'installation dans le home de l'utilisateur (pas besoin de root)
DEST="$HOME/bin"
mkdir -p "$DEST"

# Telecharge l'archive ZIP de Vagrant dans /tmp
wget -O /tmp/vagrant.zip "$VAGRANT"

# Extrait le binaire vagrant dans ~/bin
# -o = ecrase si deja present (idempotent)
unzip -o /tmp/vagrant.zip -d "$DEST"
chmod +x "$DEST/vagrant"

# Ajoute ~/bin au PATH pour la session courante
export PATH="$DEST:$PATH"

# Verifie que l'installation a fonctionne
"$DEST/vagrant" --version

# Installe l'autocompletion Vagrant (optionnel, ignore les erreurs)
"$DEST/vagrant" autocomplete install 1>/dev/null || true

echo "Vagrant installe dans $DEST"
echo "Ajoute 'export PATH=\"\$HOME/bin:\$PATH\"' a ton ~/.zshrc pour le garder."
