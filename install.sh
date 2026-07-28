#!/usr/bin/env bash
# install.sh — Install Fusion360 on Linux.
# Order: deps → GE-Proton → prefix init + winetricks → setup-fusion → Fusion installer (last)
#
# Usage:
#   ./install.sh                                         # full install
#   ./install.sh --deps-only                             # system packages only
#   ./install.sh --ge-proton-only                        # download/extract GE-Proton only
#   ./install.sh --prefix-only                           # init Proton prefix + winetricks
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
      PKGS="icoutils zenity python3-tk cabextract wget xdg-utils desktop-file-utils winetricks"
      ;;
    fedora)
      INSTALL_CMD="sudo dnf install -y"
      PKGS="icoutils zenity python3-tk cabextract wget xdg-utils desktop-file-utils winetricks"
      ;;
    arch|manjaro|endeavour)
      INSTALL_CMD="sudo pacman -S --needed --noconfirm"
      PKGS="icoutils zenity python3-tk cabextract wget xdg-utils desktop-file-utils winetricks"
      ;;
    opensuse*|suse)
      INSTALL_CMD="sudo zypper install -y"
      PKGS="icoutils zenity python3-tk cabextract wget xdg-utils desktop-file-utils winetricks"
      ;;
    *)
      echo "ERROR: Unknown distro '$ID'. Install these manually, then re-run:"
      echo "  icoutils zenity python3-tk cabextract wget xdg-utils desktop-file-utils winetricks"
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
  echo "  [1/5] Installing packages: $PKGS"
  $INSTALL_CMD $PKGS
  echo "  [1/5] Done."
}

# ── Step 2: GE-Proton ─────────────────────────────────────────────────
install_ge_proton() {
  mkdir -p "$COMPAT_DIR"
  local existing
  existing=$(find "$COMPAT_DIR" -name proton -type f 2>/dev/null | head -1 || true)
  if [[ -n "$existing" ]]; then
    echo "  [2/5] GE-Proton already installed: $(dirname "$existing")"
    return 0
  fi

  local tarball="/tmp/${GE_PROTON_VERSION}.tar.gz"
  if [[ ! -f "$tarball" ]]; then
    echo "  [2/5] Downloading ${GE_PROTON_VERSION} (~500MB)..."
    wget -O "$tarball" "$GE_PROTON_URL"
  else
    echo "  [2/5] Already downloaded: $tarball"
  fi

  echo "  [2/5] Extracting..."
  tar -xf "$tarball" -C "$COMPAT_DIR"
  echo "  [2/5] Done: $COMPAT_DIR/$GE_PROTON_VERSION/proton"
}

# ── Step 3: initialize Proton prefix ──────────────────────────────────
init_prefix() {
  local proton
  proton=$(find "$COMPAT_DIR" -name proton -type f 2>/dev/null | head -1 || true)
  if [[ -z "$proton" ]]; then
    echo "  [3/5] GE-Proton not found. Run install.sh (without flags) first."
    exit 1
  fi

  if [[ -f "$PFX_DIR/pfx/user.reg" ]]; then
    echo "  [3/5] Proton prefix already initialized."
  else
    mkdir -p "$PFX_DIR"
    echo "  [3/5] Initializing Proton prefix (wineboot)..."
    STEAM_COMPAT_DATA_PATH="$PFX_DIR" \
    STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam" \
    "$proton" run wineboot -u 2>/dev/null || true
    echo "  [3/5] Prefix initialized."
  fi

  # Install VC++ runtimes via winetricks if available
  if command -v winetricks &>/dev/null; then
    if [[ ! -f "$PFX_DIR/pfx/drive_c/windows/system32/vcruntime140.dll" ]]; then
      echo "  [3/5] Installing VC++ runtimes via winetricks..."
      STEAM_COMPAT_DATA_PATH="$PFX_DIR" \
      STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam" \
      WINEPREFIX="$PFX_DIR/pfx" \
      winetricks -q vcrun2022 2>/dev/null || true
      echo "  [3/5] VC++ runtimes done."
    else
      echo "  [3/5] VC++ runtimes already present."
    fi
  else
    echo "  [3/5] winetricks not available — skipping VC++ runtime install."
  fi

  echo "  [3/5] Done."
}

# ── Step 4: setup-fusion (WebView2, config, handlers, desktop, icons) ─
run_setup() {
  if [[ -f "$SCRIPT_DIR/setup-fusion.sh" ]]; then
    echo "  [4/5] Running post-install configuration..."
    "$SCRIPT_DIR/setup-fusion.sh"
  else
    echo "  [4/5] setup-fusion.sh not found. Run it manually from the repo."
  fi
}

# ── Step 5: run Fusion installer (LAST) ───────────────────────────────
run_fusion_installer() {
  local proton
  proton=$(find "$COMPAT_DIR" -name proton -type f 2>/dev/null | head -1 || true)
  if [[ -z "$proton" ]]; then
    echo "  [5/5] GE-Proton not found. Run install.sh (without flags) first."
    exit 1
  fi

  # Use --installer-path if provided
  if [[ -n "${INSTALLER_PATH_OVERRIDE:-}" ]]; then
    if [[ -f "$INSTALLER_PATH_OVERRIDE" ]]; then
      INSTALLER_PATH="$INSTALLER_PATH_OVERRIDE"
    else
      echo "  [5/5] Specified path not found: $INSTALLER_PATH_OVERRIDE"
      exit 1
    fi
  fi

  # Auto-download if not found
  if [[ -z "${INSTALLER_PATH:-}" ]]; then
    mkdir -p "$HOME/Downloads/fusion360-linux-install"
    find_installer || true
  fi

  if [[ -z "${INSTALLER_PATH:-}" ]]; then
    echo "  [5/5] Downloading Fusion installer..."
    wget -O "$HOME/Downloads/fusion360-linux-install/FusionClientDownloader.exe" \
      "https://dl.appstreaming.autodesk.com/production/installers/Fusion%20Client%20Downloader.exe" || {
      cat >&2 <<EOF

  ┌─ Manual download ────────────────────────────────────────────┐
  │                                                                │
  │  Download FusionClientDownloader.exe manually from:             │
  │    https://dl.appstreaming.autodesk.com/production/installers/  │
  │      Fusion%20Client%20Downloader.exe                          │
  │                                                                │
  │  Then run:                                                     │
  │    ./install.sh --installer-path /path/to/FusionClientDownloader.exe
  │                                                                │
  └────────────────────────────────────────────────────────────────┘
EOF
      exit 1
    }
    find_installer || true
    if [[ -z "$INSTALLER_PATH" ]]; then
      echo "  [5/5] Download failed. Try manually with --installer-path."
      exit 1
    fi
  fi

  echo "  [5/5] Found: $INSTALLER_PATH"
  echo "  [5/5] Launching Fusion installer through Proton..."
  echo "  [5/5] A Windows installer window will appear. Click through it."
  echo ""
  echo "  ┌─ IMPORTANT ────────────────────────────────────────────┐"
  echo "  │ Complete the installer in the window that appears.     │"
  echo "  │ When it shows \"Finish\", the installation is done.      │"
  echo "  └────────────────────────────────────────────────────────┘"
  echo ""

  mkdir -p "$PFX_DIR"
  STEAM_COMPAT_DATA_PATH="$PFX_DIR" \
  STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam" \
  "$proton" run "$INSTALLER_PATH"

  echo ""
  echo "  [5/5] Installer exited. Checking for Fusion360.exe..."
  local fusion_exe
  fusion_exe=$(find "$PFX_DIR" -name Fusion360.exe -type f 2>/dev/null | head -1 || true)
  if [[ -n "$fusion_exe" ]]; then
    echo "  [5/5] Fusion360.exe found — install succeeded."
  else
    echo "  [5/5] Fusion360.exe not found yet. The installer may still be running"
    echo "  [5/5] or it may need to finish downloading components."
    echo "  [5/5] Run ./setup-fusion.sh once Fusion360.exe exists."
  fi
}

# ── Main ──────────────────────────────────────────────────────────────
main() {
  case "$MODE" in
    --deps-only)       install_deps; exit 0 ;;
    --ge-proton-only)  install_ge_proton; exit 0 ;;
    --prefix-only)     pre_flight; install_deps; install_ge_proton; init_prefix; exit 0 ;;
    --run-installer)   run_fusion_installer; exit 0 ;;
  esac

  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║     Fusion360 Linux Installer                               ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""

  pre_flight

  echo "── Step 1/5: System dependencies ──"
  install_deps
  echo ""

  echo "── Step 2/5: GE-Proton ──"
  install_ge_proton
  echo ""

  echo "── Step 3/5: Proton prefix + winetricks ──"
  init_prefix
  echo ""

  echo "── Step 4/5: Configuration (WebView2, handlers, desktop) ──"
  run_setup
  echo ""

  echo "── Step 5/5: Fusion Installer ──"
  run_fusion_installer
  echo ""

  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║     Install complete. Run:  ./launch-fusion.sh              ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
}

main "$@"
