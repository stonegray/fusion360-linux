# install-scripts/00-common.sh — Shared functions and vars for install steps
# Sourced by install.sh, not executed directly.

GE_PROTON_VERSION="GE-Proton11-3"
GE_PROTON_URL="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/${GE_PROTON_VERSION}/${GE_PROTON_VERSION}.tar.gz"
COMPAT_DIR="$HOME/.local/share/Steam/compatibilitytools.d"
PFX_DIR="$HOME/.fusion360-proton2"
INSTALLER_PATH=""
INSTALL_CMD=""
PKGS=""

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
      echo "ERROR: Unknown distro '$ID'. Install these manually:"
      echo "  icoutils zenity python3-tk cabextract wget xdg-utils desktop-file-utils winetricks"
      exit 1
      ;;
  esac
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
  local user; user=$(id -u)

  # Collect ALL wine/proton PIDs — check both cmdline AND /proc/PID/exe
  # because Wine processes show Windows paths in cmdline (no "wine" string)
  # but their actual binary is wine64-preloader or similar
  local pids=()
  local pid

  # Method 1: pgrep by cmdline patterns
  for pattern in wineserver wine proton xalia streamer \
    Fusion360 FusionClientDownloader AdskIdentity adexmtsv \
    steam.exe node.exe fusion-gray-overlay; do
    while IFS= read -r pid; do
      pids+=("$pid")
    done < <(pgrep -u "$user" -f "$pattern" 2>/dev/null || true)
  done

  # Method 2: scan /proc/PID/exe for wine/proton binaries
  for proc in /proc/[0-9]*/exe; do
    exe=$(readlink "$proc" 2>/dev/null || true)
    [[ -z "$exe" ]] && continue
    if [[ "$exe" == *wine* ]] || [[ "$exe" == *proton* ]]; then
      pid=${proc%/exe}
      pid=${pid#/proc/}
      pids+=("$pid")
    fi
  done

  # Deduplicate and remove empty entries
  local unique=()
  for pid in "${pids[@]}"; do
    [[ -z "$pid" ]] && continue
    case " ${unique[*]} " in *" $pid "*) continue ;; esac
    unique+=("$pid")
  done

  if (( ${#unique[@]} == 0 )); then
    return 0
  fi

  echo "  [lifecycle] Killing ${#unique[@]} Wine/Proton process(es)..."

  # Kill tracked installer PID
  if [[ -n "${INSTALLER_PID:-}" ]] && kill -0 "$INSTALLER_PID" 2>/dev/null; then
    kill "$INSTALLER_PID" 2>/dev/null || true
    sleep 0.3
    kill -9 "$INSTALLER_PID" 2>/dev/null || true
  fi

  # Kill all collected PIDs
  for pid in "${unique[@]}"; do
    kill -9 "$pid" 2>/dev/null || true
  done

  sleep 1

  # Verify — rescan with same methods
  local survivors=0
  for proc in /proc/[0-9]*/exe; do
    exe=$(readlink "$proc" 2>/dev/null || true)
    [[ -z "$exe" ]] && continue
    if [[ "$exe" == *wine* ]] || [[ "$exe" == *proton* ]]; then
      pid=${proc%/exe}
      pid=${pid#/proc/}
      echo "  [lifecycle]   SURVIVED: PID $pid ($exe)"
      survivors=$((survivors + 1))
    fi
  done

  if (( survivors == 0 )); then
    echo "  [lifecycle] Killed successfully."
  else
    echo "  [lifecycle] $survivors process(es) still running."
  fi

  # Remove wineserver lock so next start is clean
  rm -f "$PFX_DIR/pfx/.wineserver.lock" 2>/dev/null || true
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
