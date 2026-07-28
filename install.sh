#!/usr/bin/env bash
set -euo pipefail

# install.sh — Phase 1: System dependencies & directory setup for Fusion360 on Linux
# This script installs system packages, creates required directories,
# and prints instructions for Phase 2 (Fusion installer via Proton).

# ── Root guard ─────────────────────────────────────────────────────────
if [[ $EUID -eq 0 ]]; then
  cat >&2 <<EOF
ERROR: Do not run install.sh as root.
  Run it as a normal user — the script will use sudo when needed.
  Running as root creates directories under /root/ instead of your home.
EOF
  exit 1
fi

# ── Distro detection ──────────────────────────────────────────────────
detect_distro() {
  source /etc/os-release
  case "$ID" in
    ubuntu|neon|debian|pop|elementary|linuxmint)
      PKG_MGR="apt-get"
      PKGS="icoutils zenity python3-tk cabextract wget xdg-utils desktop-file-utils"
      INSTALL_CMD="sudo apt-get install -y"
      ;;
    fedora)
      PKG_MGR="dnf"
      PKGS="icoutils zenity python3-tk cabextract wget xdg-utils desktop-file-utils"
      INSTALL_CMD="sudo dnf install -y"
      ;;
    arch|manjaro|endeavour)
      PKG_MGR="pacman"
      PKGS="icoutils zenity python3-tk cabextract wget xdg-utils desktop-file-utils"
      INSTALL_CMD="sudo pacman -S --needed --noconfirm"
      ;;
    opensuse*|suse)
      PKG_MGR="zypper"
      PKGS="icoutils zenity python3-tk cabextract wget xdg-utils desktop-file-utils"
      INSTALL_CMD="sudo zypper install -y"
      ;;
    *)
      echo "============================================================"
      echo "WARNING: Unknown distro '$ID'. Install these packages manually:"
      echo "  icoutils zenity python3-tk cabextract wget xdg-utils desktop-file-utils"
      echo "Then re-run this script, or continue manually."
      echo "============================================================"
      exit 1
      ;;
  esac
}

# ── Pre-flight checks ────────────────────────────────────────────────
pre_flight() {
  # Display server
  if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
    echo "ERROR: No display server detected (\$DISPLAY and \$WAYLAND_DISPLAY both unset)."
    echo "  Are you running from a desktop session?"
    exit 1
  fi

  # Sudo access
  if ! sudo -n true 2>/dev/null; then
    echo "NOTE: Passwordless sudo not available. Trying sudo with askpass..."
    if [[ -n "${SUDO_ASKPASS:-}" ]]; then
      SUDO_CMD="sudo -A"
    else
      echo "============================================================"
      echo "sudo access is required to install packages."
      echo "Set SUDO_ASKPASS if you want a GUI prompt, or simply run:"
      echo "  sudo $INSTALL_CMD $PKGS"
      echo "Then re-run this script to continue."
      echo "============================================================"
      exit 1
    fi
  fi

  # Disk space (check home partition)
  local available_kb
  available_kb=$(df --output=avail "$HOME" 2>/dev/null | tail -n1)
  local available_gb=$((available_kb / 1024 / 1024))
  if [[ $available_gb -lt 10 ]]; then
    echo "WARNING: Only ${available_gb}GB free on $HOME partition."
    echo "  Fusion360 + Proton prefix requires at least 10GB free space."
    echo "  Consider freeing space before continuing."
    echo ""
  fi
}

# ── Main ─────────────────────────────────────────────────────────────
main() {
  echo "=== Fusion360 Linux — Phase 1: System Preparation ==="
  echo ""

  detect_distro
  pre_flight

  echo "Detected: $(source /etc/os-release && echo "$PRETTY_NAME")"
  echo "Package manager: $PKG_MGR"
  echo "Packages: $PKGS"
  echo ""

  # Install packages
  echo "Installing system dependencies..."
  $INSTALL_CMD $PKGS
  echo ""

  # Create required directories
  echo "Creating directories..."
  mkdir -p "$HOME/.local/share/Steam/compatibilitytools.d"
  mkdir -p "$HOME/.fusion360-proton2"
  echo "  Created: $HOME/.local/share/Steam/compatibilitytools.d"
  echo "  Created: $HOME/.fusion360-proton2"
  echo ""

  # ── Phase 1 complete — print Phase 2 instructions ──────────────
  cat <<EOF
============================================================
PHASE 1 COMPLETE: System dependencies installed.

PHASE 2: Install Fusion360
---------------------------
Step 1: Download GE-Proton (if not already done):
  wget https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton11-3/GE-Proton11-3.tar.gz
  tar -xf GE-Proton*.tar.gz -C "$HOME/.local/share/Steam/compatibilitytools.d/"

Step 2: Download the Fusion 360 installer from Autodesk:
  Place FusionClientDownloader.exe in ~/Downloads/fusion360-linux-install/

Step 3: Run the Fusion installer through Proton:
  STEAM_COMPAT_DATA_PATH="$HOME/.fusion360-proton2" \\
  STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam" \\
  "$HOME/.local/share/Steam/compatibilitytools.d/GE-Proton11-3/proton" run \\
  "$HOME/Downloads/fusion360-linux-install/FusionClientDownloader.exe"

After the installer finishes, run Phase 3:
  ./setup-fusion.sh
============================================================
EOF
}

main "$@"
