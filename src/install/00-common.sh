# src/install/00-common.sh — Shared functions and vars for install steps
# Sourced by install.sh, not executed directly.

# Path defaults (XDG-compliant, single source of truth)
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
source "$SCRIPT_DIR/src/install/00-defaults.sh"

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

detect_distro() {
  source /etc/os-release
  case "$ID" in
    ubuntu|neon|debian|pop|elementary|linuxmint)
      INSTALL_CMD="sudo apt-get install -y"
      ;;
    fedora)
      INSTALL_CMD="sudo dnf install -y"
      ;;
    arch|manjaro|endeavour)
      INSTALL_CMD="sudo pacman -S --needed --noconfirm"
      ;;
    opensuse*|suse)
      INSTALL_CMD="sudo zypper install -y"
      ;;
    void)
      INSTALL_CMD="sudo xbps-install -S"
      ;;
    solus)
      INSTALL_CMD="sudo eopkg install -y"
      ;;
    *)
      INSTALL_CMD=""
      echo "WARNING: Unknown distro '$ID'. Installing generic packages — you may need to adapt."
      ;;
  esac

  # Read package list from distro file, fall back to generic
  local distro_file="$SCRIPT_DIR/src/install/distro/${ID}.txt"
  if [[ ! -f "$distro_file" ]]; then
    distro_file="$SCRIPT_DIR/src/install/distro/generic.txt"
  fi

  if [[ -f "$distro_file" ]]; then
    PKGS=$(cat "$distro_file" | tr '\n' ' ' | sed 's/ *$//')
  else
    echo "ERROR: Package list not found for distro '$ID' and no generic.txt fallback." >&2
    exit 1
  fi
}

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

# ── Install lifecycle management ──────────────────────────────────────
INSTALLER_PID=""

kill_installer() {
  # Kill tracked installer PID
  if [[ -n "${INSTALLER_PID:-}" ]] && kill -0 "$INSTALLER_PID" 2>/dev/null; then
    kill "$INSTALLER_PID" 2>/dev/null || true
    sleep 0.3
    kill -9 "$INSTALLER_PID" 2>/dev/null || true
  fi

  # Use the shared kill function from launcher-functions.sh
  if [[ -f "$SCRIPT_DIR/src/runtime/launcher-functions.sh" ]]; then
    source "$SCRIPT_DIR/src/runtime/launcher-functions.sh"
    kill_fusion_processes
  else
    # Fallback: simple pgrep kill
    local user; user=$(id -u)
    for pattern in wineserver wine proton; do
      pkill -u "$user" -f "$pattern" 2>/dev/null || true
    done
  fi

  # Remove wineserver lock so next start is clean
  [[ -n "${PFX_DIR:-}" ]] && rm -f "$PFX_DIR/pfx/.wineserver.lock" 2>/dev/null || true
}

installer_is_running() {
  # Check if a Fusion installer is already running through Proton
  pgrep -f "FusionClientDownloader" 2>/dev/null | grep -q . && return 0
  # Check if wineserver is running for our prefix
  [[ -f "$PFX_DIR/pfx/.wineserver.lock" ]] && return 0
  return 1
}

setup_traps() {
  trap_cleanup() {
    echo ""
    echo "  [lifecycle] Interrupted. Cleaning up..."
    kill_installer
    exit 1
  }
  trap trap_cleanup INT TERM
}

clear_traps() {
  trap - INT TERM
}
