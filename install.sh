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

set -euo pipefail

if [[ $EUID -eq 0 ]]; then
  cat >&2 <<EOF
ERROR: Do not run install.sh as root.
  Run it as a normal user — the script will use sudo when needed.
EOF
  exit 1
fi
LOCK_DIR="/tmp/fusion360-install.lock"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${1:-}" == "--kill" ]]; then
  source "$SCRIPT_DIR/src/runtime/launcher-functions.sh"
  kill_fusion_processes
  exit 0
fi
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "ERROR: Another install is already running (lock at $LOCK_DIR)." >&2
  exit 1
fi
trap 'rm -rf "$LOCK_DIR"' EXIT INT TERM INT TERM

MODE="${1:-}"
INSTALLER_PATH_OVERRIDE=""

if [[ "${1:-}" == "--installer-path" ]]; then
  INSTALLER_PATH_OVERRIDE="${2:-}"
  [[ -n "$INSTALLER_PATH_OVERRIDE" ]] || { echo "Usage: ./install.sh --installer-path /path/to/exe"; exit 1; }
  MODE="--run-installer"
fi

source "$SCRIPT_DIR/src/install/00-common.sh"
setup_traps

run_step() {
  source "$SCRIPT_DIR/src/install/$1"
}

case "$MODE" in
  --deps-only)
    run_step 10-deps.sh
    clear_traps
    exit 0
    ;;
  --ge-proton-only)
    run_step 20-ge-proton.sh
    clear_traps
    exit 0
    ;;
  --prefix-only)
    pre_flight
    run_step 10-deps.sh
    run_step 20-ge-proton.sh
    run_step 25-install-to-location.sh
    run_step 30-prefix.sh
    exit 0
    ;;
  --uninstall)
    clear_traps
    source "$SCRIPT_DIR/src/runtime/uninstall-select.sh"
    ;;
  --run-installer)
    run_step 40-fusion-installer.sh
    clear_traps
    exit 0
    ;;
esac

log_step "Step 1/14: System dependencies"
run_step 10-deps.sh
echo ""

log_step "Step 2/14: Preflight checks"
run_step 05-preflight.sh
echo ""

log_step "Step 3/14: GE-Proton"
run_step 20-ge-proton.sh
echo ""

log_step "Step 4/14: Install to system"
run_step 25-install-to-location.sh
echo ""

log_step "Step 5/14: Proton prefix"
run_step 30-prefix.sh
echo ""

log_step "Step 6/14: WebView2"
run_step 35-webview2.sh
echo ""

log_step "Step 7/14: Config"
run_step 37-config.sh
echo ""

log_step "Step 8/14: Protocol handlers"
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
echo ""

clear_traps

log_pass "Fusion 360 installation complete."
