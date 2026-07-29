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




