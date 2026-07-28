# install-scripts/00-defaults.sh — Standard paths for Fusion360 Linux
# Sourced by 00-common.sh. All install scripts should reference these
# instead of hardcoding paths.

# XDG base directories
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_BIN_HOME="${XDG_BIN_HOME:-$HOME/.local/bin}"

# Fusion360 install target (stable location, not tied to repo)
F360_DATA_DIR="$XDG_DATA_HOME/fusion360-linux"
F360_CONFIG_DIR="$XDG_CONFIG_HOME/fusion360-linux"
F360_CONFIG_FILE="$F360_CONFIG_DIR/config"
F360_BIN_DIR="$XDG_BIN_HOME"

# Desktop integration
F360_APPS_DIR="$XDG_DATA_HOME/applications"
F360_ICONS_DIR="$XDG_DATA_HOME/icons/hicolor"

# Proton / Wine
COMPAT_DIR="$HOME/.local/share/Steam/compatibilitytools.d"
PFX_DIR="$HOME/.fusion360-proton2"
GE_PROTON_VERSION="GE-Proton11-3"
GE_PROTON_URL="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${GE_PROTON_VERSION}/${GE_PROTON_VERSION}.tar.gz"

# Installer paths
INSTALLER_PATH=""
INSTALL_CMD=""
PKGS=""
