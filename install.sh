#!/usr/bin/env bash
# install.sh — Install Fusion360 on Linux.
# Thin wrapper over src/install/*.sh (numbered steps).
# Sets up cleanup traps to kill installer on Ctrl+C or unexpected exit.
#
# Usage:
#   ./install.sh                                         # full install
#   ./install.sh --deps-only                             # step 1 only
#   ./install.sh --ge-proton-only                        # step 2 only
#   ./install.sh --prefix-only                           # step 3 only
#   ./install.sh --uninstall                            # interactive selective uninstall
#   ./install.sh --kill                                  # kill all Fusion/Wine/Proton processes
#   ./install.sh --installer-path /path/to/downloader.exe  # step 5 with local file
#   ./install.sh --upload-fix                            # opt-in: patched wineserver for fast cloud uploads
#   ./install.sh --upload-fix-revert                     # restore the original wineserver

set -euo pipefail 2>/dev/null || set -euo

if [[ $EUID -eq 0 ]]; then
  cat >&2 <<EOF
ERROR: Do not run install.sh as root.
  Run it as a normal user — the script will use sudo when needed.
EOF
  exit 1
fi
LOCK_DIR="$(mktemp -d -t fusion360-install.XXXX)"
_this_file="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$_this_file")" && pwd)"
if [[ "${1:-}" == "--kill" ]]; then
  echo "Killing all Fusion 360 / Wine / Proton processes..."
  PFX_DIR="${PFX_DIR:-$HOME/.fusion360-proton2}"
  # Reuse the tested library implementation: it terminates the prefix's
  # wineserver first, covers launch-fusion.sh and the shell daemons (so the
  # launcher watchdog can't respawn the stack), scales TERM -> KILL, and
  # uses /bin/kill to dodge shell-builtin shadowing.
  source "$SCRIPT_DIR/share/load.sh"
  export PFX_DIR
  if kill_fusion_processes; then
    echo "All Fusion/Wine/Proton processes killed."
  else
    echo "Warning: some processes survived. Check with: ps aux | grep -i fusion"
  fi
  exit 0
fi


MODE="${1:-}"
INSTALLER_PATH_OVERRIDE=""

if [[ "${1:-}" == "--installer-path" ]]; then
  INSTALLER_PATH_OVERRIDE="${2:-}"
  [[ -n "$INSTALLER_PATH_OVERRIDE" ]] || { echo "Usage: ./install.sh --installer-path /path/to/exe"; exit 1; }
  MODE="--run-installer"
fi

source "$SCRIPT_DIR/src/install/00-common.sh"


# Trap — kill Fusion processes on Ctrl+C, clean up lock file on exit
trap 'kill_fusion_processes 2>/dev/null || true; rm -rf "$LOCK_DIR" 2>/dev/null || true; exit 1' INT TERM
trap 'rm -rf "$LOCK_DIR"' EXIT
run_step() {
  source "$SCRIPT_DIR/src/install/$1"
}

case "$MODE" in
  --deps-only)
    log_info " Detecting operating system..."
    local distro; distro="$(detect_distro)"
    INSTALL_CMD="sudo $(distro_install_cmd "$distro")"
    local distro_file="$SCRIPT_DIR/src/install/distro/${distro}.txt"
    if [[ ! -f "$distro_file" ]]; then distro_file="$SCRIPT_DIR/src/install/distro/generic.txt"; fi
    PKGS=$(tr '\n' ' ' < "$distro_file" 2>/dev/null | sed 's/ *$//')
    run_step 10-deps.sh
    exit 0
    ;;
  --ge-proton-only)
    run_step 20-ge-proton.sh
    exit 0
    ;;
  --prefix-only)
    log_info " Detecting operating system..."
    local distro; distro="$(detect_distro)"
    INSTALL_CMD="sudo $(distro_install_cmd "$distro")"
    local distro_file="$SCRIPT_DIR/src/install/distro/${distro}.txt"
    if [[ ! -f "$distro_file" ]]; then distro_file="$SCRIPT_DIR/src/install/distro/generic.txt"; fi
    PKGS=$(tr '\n' ' ' < "$distro_file" 2>/dev/null | sed 's/ *$//')
    log_info " Distro: $distro -- using: $INSTALL_CMD"
    pre_flight
    run_step 10-deps.sh
    run_step 20-ge-proton.sh
    run_step 25-install-to-location.sh
    run_step 30-prefix.sh
    exit 0
    ;;
  --uninstall)
    source "$SCRIPT_DIR/src/runtime/uninstall-select.sh"
    exit 0
    ;;
  --run-installer)
    run_step 40-fusion-installer.sh
    exit 0
    ;;
  --upload-fix|--upload-fix-revert)
    log_step "Cloud upload fix (patched wineserver)"
    [[ "$MODE" == --upload-fix-revert ]] && UPLOAD_FIX_ACTION=revert
    run_step 43-upload-fix.sh || exit 1
    exit 0
    ;;
esac

log_step "Step 1/14: Preflight checks"
run_step 05-preflight.sh
echo ""

log_step "Step 2/14: System dependencies"
run_step 10-deps.sh
echo ""

log_step "Step 3/14: GE-Proton"
run_step 20-ge-proton.sh
echo ""

log_step "Step 4/14: Install to system"
run_step 25-install-to-location.sh
echo ""

log_step "Step 5/14: Build runtime helpers"
run_step 26-runtime-patches.sh
echo ""

log_step "Step 6/14: Proton prefix"
run_step 30-prefix.sh
echo ""

log_step "Step 7/14: WebView2"
run_step 35-webview2.sh
echo ""

log_step "Step 8/14: Config"
run_step 37-config.sh
echo ""

log_step "Step 9/14: Display DPI"
run_step 38-dpi.sh
echo ""

log_step "Step 10/14: Windows Version"
run_step 39-windows-version.sh
echo ""

log_step "Step 11/14: Fusion Installer"
run_step 40-fusion-installer.sh
echo ""

log_step "Step 12/14: LaunchDarkly streaming fix"
run_step 42-ld-streaming-fix.sh
echo ""

log_step "Step 13/14: File type associations"
run_step 45-filetypes.sh
echo ""

log_step "Step 14/14: Health check"
if [[ -x "$SCRIPT_DIR/src/doctor/doctor.sh" ]]; then
  "$SCRIPT_DIR/src/doctor/doctor.sh" --quick || true
fi

# The Fusion installer spawns background processes (streamer, AdskIdentity,
# Fusion360.exe) asynchronously and can bring them back up after step 10's
# kill. Sweep again now that every step has finished, so the user is not
# left with a stray Wine stack running after "installation complete".
log_info " Cleaning up installer processes..."
kill_fusion_processes || log_warn " Some processes may still be running. Use ./install.sh --kill to force."
echo ""

log_pass "Fusion 360 installation complete."
log_detail "   Cloud saves slow (~100 KB/s)? Optional fix: ./install.sh --upload-fix  (see docs/troubleshooting.md)"
