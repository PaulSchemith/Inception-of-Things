#!/bin/sh
# =============================================================================
# install_vagrant.sh - Installe Vagrant dans ~/.bin + autocomplete + libvirt
# =============================================================================
set -eu

VAGRANT_VERSION="2.4.9"
VAGRANT_URL="https://releases.hashicorp.com/vagrant/${VAGRANT_VERSION}/vagrant_${VAGRANT_VERSION}_linux_amd64.zip"
DEST="$HOME/.bin"
ZIP_PATH="/tmp/vagrant_${VAGRANT_VERSION}.zip"
VAGRANT_BIN="$DEST/vagrant"
PLUGIN_LOG="/tmp/vagrant-libvirt-install.log"
COMPLETION_DIR="$HOME/.config/vagrant"
COMPLETION_FILE="$COMPLETION_DIR/completion.bash"
COMPLETION_URL="https://raw.githubusercontent.com/hashicorp/vagrant/v${VAGRANT_VERSION}/contrib/bash/completion.sh"
BASHRC="$HOME/.bashrc"

mkdir -p "$DEST"

if command -v wget >/dev/null 2>&1; then
	wget -O "$ZIP_PATH" "$VAGRANT_URL"
elif command -v curl >/dev/null 2>&1; then
	curl -fsSL "$VAGRANT_URL" -o "$ZIP_PATH"
else
	echo "Erreur: wget ou curl est requis pour telecharger Vagrant."
	exit 1
fi

if ! command -v unzip >/dev/null 2>&1; then
	echo "Erreur: unzip est requis pour extraire Vagrant."
	exit 1
fi

unzip -o "$ZIP_PATH" -d "$DEST"
chmod +x "$VAGRANT_BIN"

# Rend vagrant disponible immediatement dans la session courante.
export PATH="$DEST:$PATH"

"$VAGRANT_BIN" --version

echo "Configuration de l'autocompletion Vagrant (bash)..."
mkdir -p "$COMPLETION_DIR"

if command -v wget >/dev/null 2>&1; then
	wget -O "$COMPLETION_FILE" "$COMPLETION_URL"
elif command -v curl >/dev/null 2>&1; then
	curl -fsSL "$COMPLETION_URL" -o "$COMPLETION_FILE"
else
	echo "Avertissement: impossible de telecharger l'autocompletion (wget/curl manquant)."
fi

if [ -f "$COMPLETION_FILE" ]; then
	# Supprime d'abord tout ancien bloc ajoute par ce script.
	awk 'BEGIN{skip=0} /# >>>> Vagrant command completion \(start\)/{skip=1;next} /# <<<<  Vagrant command completion \(end\)/{skip=0;next} !skip{print}' "$BASHRC" > /tmp/bashrc.vagrant.clean
	mv /tmp/bashrc.vagrant.clean "$BASHRC"

	{
		echo ""
		echo "# >>>> Vagrant command completion (start)"
		echo "if [ -f \"$COMPLETION_FILE\" ]; then"
		echo "  . \"$COMPLETION_FILE\""
		echo "fi"
		echo "# <<<<  Vagrant command completion (end)"
	} >> "$BASHRC"
fi

echo "Installation du plugin vagrant-libvirt (provider QEMU/KVM)..."
if "$VAGRANT_BIN" plugin list | grep -q '^vagrant-libvirt '; then
	echo "Plugin vagrant-libvirt deja installe."
else
	MISSING_TOOLS=""
	for tool in gcc make pkg-config; do
		if ! command -v "$tool" >/dev/null 2>&1; then
			MISSING_TOOLS="$MISSING_TOOLS $tool"
		fi
	done

	if [ -n "$MISSING_TOOLS" ]; then
		echo "Dependances manquantes pour compiler les gems natives:$MISSING_TOOLS"
		echo "Installe-les puis relance ce script."
		echo "Exemple Debian/Ubuntu: sudo apt-get install -y build-essential pkg-config libvirt-dev"
		exit 1
	fi

	if ! pkg-config --exists libvirt 2>/dev/null; then
		echo "libvirt-dev semble absent (pkg-config ne trouve pas 'libvirt')."
		echo "Installe-le puis relance ce script."
		echo "Exemple Debian/Ubuntu: sudo apt-get install -y libvirt-dev"
		exit 1
	fi

	if "$VAGRANT_BIN" plugin install vagrant-libvirt >"$PLUGIN_LOG" 2>&1; then
		echo "Plugin vagrant-libvirt installe avec succes."
	else
		echo "Echec d'installation de vagrant-libvirt."
		echo "Log detaille: $PLUGIN_LOG"
		if grep -q "fatal error: stdio.h: No such file or directory" "$PLUGIN_LOG"; then
			echo "Erreur detectee: compilation native Ruby impossible (stdio.h introuvable pendant build)."
			echo "Sur certains environnements, le binaire Vagrant portable (.zip) ne compile pas les plugins natifs."
			echo "Contournement recommande: utiliser Vagrant installe via paquets systeme (apt) puis installer vagrant-libvirt."
		else
			echo "Cause frequente: dependances libvirt manquantes (libvirt, qemu, ruby-dev, etc.)."
		fi
		exit 1
	fi
fi

echo ""
echo "Vagrant installe dans $DEST"

if ! echo ":$PATH:" | grep -q ":$DEST:"; then
	export PATH="$PATH:$DEST"
	echo "PATH courant mis a jour avec $DEST"
else
	echo "$DEST est deja present dans le PATH courant"
fi

if ! grep -Fq 'export PATH="$PATH:$HOME/.bin"' "$BASHRC"; then
	echo 'export PATH="$PATH:$HOME/.bin"' >> "$BASHRC"
	echo "Ajout de ~/.bin dans $BASHRC"
else
	echo "~/.bin deja configure dans $BASHRC"
fi
