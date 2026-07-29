# src/install/00-common.sh — Shared functions and vars for install steps
# Sourced by install.sh, not executed directly.


# Load share/ modules (path resolution: this file is at src/install/,
# share/ is at the repo root)
_share_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../share" 2>/dev/null && pwd)" || true
if [[ -d "$_share_dir" ]]; then
  source "$_share_dir/load.sh"
fi
unset _share_dir
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
  if [[ ! -f /etc/os-release ]]; then
    echo "ERROR: /etc/os-release not found. Cannot detect distro." >&2
    exit 1
  fi
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

  if [[ -z "$INSTALL_CMD" ]]; then
    echo "ERROR: Unsupported distribution '$ID'. Please install the required" >&2
    echo "       packages manually, or add support for your distro." >&2
    echo "       Required: curl, wget, xdg-utils, ImageMagick or ffmpeg," >&2
    echo "       icoutils, desktop-file-utils, MAME icon tools (wrestool)." >&2
    exit 1
  fi

  # Normalize distro ID for package file lookup (aliases map to canonical files)
  local distro_id="$ID"
  case "$distro_id" in
    ubuntu|neon|pop|elementary|linuxmint) distro_id="debian" ;;
    manjaro|endeavour) distro_id="arch" ;;
    opensuse*|suse) distro_id="opensuse" ;;
  esac
  local distro_file="$SCRIPT_DIR/src/install/distro/${distro_id}.txt"
  if [[ ! -f "$distro_file" ]]; then
    distro_file="$SCRIPT_DIR/src/install/distro/generic.txt"
  fi

  if [[ -f "$distro_file" ]]; then
    PKGS=$(tr '\n' ' ' < "$distro_file" | sed 's/ *$//')
  else
    echo "ERROR: Package list not found for distro '$distro_id' and no generic.txt fallback." >&2
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
  [[ -z "$avail_kb" ]] && avail_kb=0
  local avail_gb=$((avail_kb / 1024 / 1024))
  if [[ $avail_gb -lt 15 ]]; then
    echo "WARNING: Only ${avail_gb}GB free on $HOME. Fusion needs ~10GB."
    echo "  Press Ctrl+C to abort, or wait 5s to continue..."
    sleep 5
  fi
}




