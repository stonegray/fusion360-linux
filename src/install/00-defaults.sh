# src/install/00-defaults.sh — Standard paths for Fusion360 Linux
# Sourced by 00-common.sh. All install scripts should reference these
# instead of hardcoding paths.

: "${HOME:?HOME is not set — aborting}"

# XDG base directories
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_BIN_HOME="${XDG_BIN_HOME:-$HOME/.local/bin}"

# Fusion360 install target (stable location, not tied to repo)
F360_DATA_DIR="$XDG_DATA_HOME/fusion360-linux"     # runtime scripts live here
F360_CONFIG_DIR="$XDG_CONFIG_HOME/fusion360-linux"  # config
F360_CONFIG_FILE="$F360_CONFIG_DIR/config"           # config file
F360_BIN_DIR="$XDG_BIN_HOME"                         # CLI symlinks

# Desktop integration — apps under a fusion360-linux subdir to avoid polluting
F360_APPS_DIR="$XDG_DATA_HOME/applications/fusion360-linux"
F360_ICONS_DIR="$XDG_DATA_HOME/icons/hicolor"

# Proton / Wine
COMPAT_DIR="$HOME/.local/share/Steam/compatibilitytools.d"
PFX_DIR="$HOME/.fusion360-proton2"
GE_PROTON_VERSION="GE-Proton10-32"
GE_PROTON_URL="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${GE_PROTON_VERSION}/${GE_PROTON_VERSION}.tar.gz"

# Installer paths
INSTALLER_PATH=""
INSTALL_CMD=""
PKGS=""
