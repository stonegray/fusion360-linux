#!/usr/bin/env bash
# install.sh — Install Fusion360 on Linux: deps, GE-Proton, Fusion installer, post-setup.
# Runs the full install flow. The Fusion GUI installer still requires clicks,
# but everything else is automated.
#
# Usage:
#   ./install.sh                                         # full install
#   ./install.sh --deps-only                             # system packages only
#   ./install.sh --ge-proton-only                        # download/extract GE-Proton only
#   ./install.sh --run-installer                         # launch Fusion installer only
#   ./install.sh --installer-path /path/to/downloader.exe  # use manually-downloaded installer

set -euo pipefail
if [[ $EUID -eq 0 ]]; then
  cat >&2 <<EOF
ERROR: Do not run install.sh as root.
  Run it as a normal user — the script will use sudo when needed.
EOF
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:-}"
INSTALLER_PATH_OVERRIDE=""

if [[ "${1:-}" == "--installer-path" ]]; then
  INSTALLER_PATH_OVERRIDE="${2:-}"
  if [[ -z "$INSTALLER_PATH_OVERRIDE" ]]; then
    echo "Usage: ./install.sh --installer-path /path/to/FusionClientDownloader.exe"
    exit 1
  fi
  MODE="--run-installer"
fi

# ── Config ────────────────────────────────────────────────────────────
GE_PROTON_VERSION="GE-Proton11-3"
GE_PROTON_URL="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${GE_PROTON_VERSION}/${GE_PROTON_VERSION}.tar.gz"
COMPAT_DIR="$HOME/.local/share/Steam/compatibilitytools.d"
PFX_DIR="$HOME/.fusion360-proton2"
INSTALLER_PATH=""

find_installer() {
  local candidates=(
    "$HOME/Downloads/fusion360-linux-install/FusionClientDownloader.exe"
    "$HOME/Downloads/FusionClientDownloader.exe"
    "$HOME/Desktop/FusionClientDownloader.exe"
  )
  for c in "${candidates[@]}"; do
    if [[ -f "$c" ]]; then
      INSTALLER_PATH="$c"
      return 0
    fi
  done
  return 1
}

# ── Distro detection ──────────────────────────────────────────────────
detect_distro() {
  source /etc/os-release
  case "$ID" in
    ubuntu|neon|debian|pop|elementary|linuxmint)
      INSTALL_CMD="sudo apt-get install -y"
      PKGS="icoutils zenity python3-tk cabextract wget xdg-utils desktop-file-utils"
      ;;
    fedora)
      INSTALL_CMD="sudo dnf install -y"
      PKGS="icoutils zenity python3-tk cabextract wget xdg-utils desktop-file-utils"
      ;;
    arch|manjaro|endeavour)
      INSTALL_CMD="sudo pacman -S --needed --noconfirm"
      PKGS="icoutils zenity python3-tk cabextract wget xdg-utils desktop-file-utils"
      ;;
    opensuse*|suse)
      INSTALL_CMD="sudo zypper install -y"
      PKGS="icoutils zenity python3-tk cabextract wget xdg-utils desktop-file-utils"
      ;;
    *)
      echo "ERROR: Unknown distro '$ID'. Install these manually, then re-run:"
      echo "  icoutils zenity python3-tk cabextract wget xdg-utils desktop-file-utils"
      exit 1
      ;;
  esac
}

# ── Pre-flight ────────────────────────────────────────────────────────
pre_flight() {
  if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
    echo "ERROR: No display server detected. Are you running from a desktop session?"
    exit 1
  fi
  if ! sudo -n true 2>/dev/null; then
    if [[ -z "${SUDO_ASKPASS:-}" ]]; then
      echo "sudo access is required. Run this script as a normal user; it will prompt for sudo."
    fi
  fi
  local avail_kb; avail_kb=$(df --output=avail "$HOME" 2>/dev/null | tail -n1)
  local avail_gb=$((avail_kb / 1024 / 1024))
  if [[ $avail_gb -lt 15 ]]; then
    echo "WARNING: Only ${avail_gb}GB free on $HOME. Fusion needs ~10GB."
    echo "  Press Ctrl+C to abort, or wait 5s to continue..."
    sleep 5
  fi
}

# ── Step 1: system deps ───────────────────────────────────────────────
install_deps() {
  detect_distro
  echo "  [deps] Installing packages: $PKGS"
  $INSTALL_CMD $PKGS
  mkdir -p "$COMPAT_DIR" "$PFX_DIR"
  echo "  [deps] Done."
}

# ── Step 2: GE-Proton ─────────────────────────────────────────────────
install_ge_proton() {
  mkdir -p "$COMPAT_DIR"

  existing=$(find "$COMPAT_DIR" -name proton -type f 2>/dev/null | head -1 || true)
  if [[ -n "$existing" ]]; then
    echo "  [ge-proton] Already installed: $(dirname "$existing")"
    return 0
  fi

  local tarball="/tmp/${GE_PROTON_VERSION}.tar.gz"
  if [[ ! -f "$tarball" ]]; then
    echo "  [ge-proton] Downloading ${GE_PROTON_VERSION} (~500MB)..."
    echo "  [ge-proton] URL: $GE_PROTON_URL"
    wget -O "$tarball" "$GE_PROTON_URL"
  else
    echo "  [ge-proton] Already downloaded: $tarball"
  fi

  echo "  [ge-proton] Extracting to $COMPAT_DIR..."
  tar -xf "$tarball" -C "$COMPAT_DIR"
  echo "  [ge-proton] Done: $COMPAT_DIR/$GE_PROTON_VERSION/proton"
}

# ── Step 3: run Fusion installer ──────────────────────────────────────
run_fusion_installer() {
  local proton
  proton=$(find "$COMPAT_DIR" -name proton -type f 2>/dev/null | head -1 || true)
  if [[ -z "$proton" ]]; then
    echo "  [installer] GE-Proton not found. Run install.sh (without flags) first."
    exit 1
  fi

  # Use --installer-path if provided
  if [[ -n "${INSTALLER_PATH_OVERRIDE:-}" ]]; then
    if [[ -f "$INSTALLER_PATH_OVERRIDE" ]]; then
      INSTALLER_PATH="$INSTALLER_PATH_OVERRIDE"
    else
      echo "  [installer] Specified path not found: $INSTALLER_PATH_OVERRIDE"
      exit 1
    fi
  fi

  # Auto-download if not found
  if [[ -z "${INSTALLER_PATH:-}" ]]; then
    mkdir -p "$HOME/Downloads/fusion360-linux-install"
    find_installer || true
  fi

  if [[ -z "${INSTALLER_PATH:-}" ]]; then
    echo "  [installer] Downloading Fusion installer..."
    wget -O "$HOME/Downloads/fusion360-linux-install/FusionClientDownloader.exe" \
      "https://dl.appstreaming.autodesk.com/production/installers/Fusion%20Client%20Downloader.exe" || {
      echo "  [installer] Download failed."
      cat >&2 <<EOF

  ┌─ Manual download ────────────────────────────────────────────┐
  │                                                                │
  │  Download FusionClientDownloader.exe manually from:             │
  │    https://dl.appstreaming.autodesk.com/production/installers/  │
  │      Fusion%20Client%20Downloader.exe                          │
  │                                                                │
  │  Then run the installer with:                                  │
  │    ./install.sh --installer-path /path/to/FusionClientDownloader.exe
  │                                                                │
  └────────────────────────────────────────────────────────────────┘
EOF
      exit 1
    }
    find_installer || true
    if [[ -z "$INSTALLER_PATH" ]]; then
      echo "  [installer] Download failed. Try manually with --installer-path."
      exit 1
    fi
  fi

  echo "  [installer] Found: $INSTALLER_PATH"
  echo "  [installer] Launching Fusion installer through Proton..."
  echo "  [installer] A Windows installer window will appear. Click through it."
  echo ""
  echo "  ┌─ IMPORTANT ────────────────────────────────────────────┐"
  echo "  │ Complete the installer in the window that appears.     │"
  echo "  │ When it shows \"Finish\", the installation is done.      │"
  echo "  │ Close the installer window, then come back here.       │"
  echo "  └────────────────────────────────────────────────────────┘"
  echo ""

  mkdir -p "$PFX_DIR"
  STEAM_COMPAT_DATA_PATH="$PFX_DIR" \
  STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam" \
  "$proton" run "$INSTALLER_PATH"

  echo ""
  echo "  [installer] Installer exited. Checking for Fusion360.exe..."
  local fusion_exe
  fusion_exe=$(find "$PFX_DIR" -name Fusion360.exe -type f 2>/dev/null | head -1 || true)
  if [[ -n "$fusion_exe" ]]; then
    echo "  [installer] Fusion360.exe found — install succeeded."
  else
    echo "  [installer] Fusion360.exe not found yet. The installer may still be running"
    echo "  [installer] or it may need to finish downloading components."
    echo "  [installer] Run ./setup-fusion.sh once Fusion360.exe exists."
  fi
}

# ── Step 4: post-install setup ────────────────────────────────────────
run_setup() {
  if [[ -f "$SCRIPT_DIR/setup-fusion.sh" ]]; then
    echo "  [setup] Running post-install configuration..."
    "$SCRIPT_DIR/setup-fusion.sh"
  else
    echo "  [setup] setup-fusion.sh not found. Run it manually from the repo."
  fi
}

# ── Main ──────────────────────────────────────────────────────────────
main() {
  case "$MODE" in
    --deps-only)
      install_deps
      exit 0
      ;;
    --ge-proton-only)
      install_ge_proton
      exit 0
      ;;
    --run-installer)
      run_fusion_installer
      exit 0
      ;;
  esac

  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║     Fusion360 Linux Installer                               ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""

  pre_flight

  # Step 1: system deps
  echo "── Step 1/4: System dependencies ──"
  install_deps
  echo ""

  # Step 2: GE-Proton
  echo "── Step 2/4: GE-Proton ──"
  install_ge_proton
  echo ""

  # Step 3: Fusion installer
  echo "── Step 3/4: Fusion Installer ──"
  run_fusion_installer
  echo ""

  # Step 4: post-install setup
  echo "── Step 4/4: Post-install Setup ──"
  run_setup
  echo ""

  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║     Install complete. Run:  ./launch-fusion.sh              ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
}

main "$@"
