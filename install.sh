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
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "ERROR: Another install is already running (lock at $LOCK_DIR)." >&2
  exit 1
fi
trap 'rm -rf "$LOCK_DIR"' EXIT INT TERM INT TERM

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
    clear_traps
    exit 0
    ;;
  --uninstall)
    clear_traps
    source "$SCRIPT_DIR/src/runtime/uninstall-select.sh"
    exit 0
    ;;
  --run-installer)
    run_step 40-fusion-installer.sh
    clear_traps
    exit 0
    ;;
esac

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     Fusion360 Linux Installer                               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo "── Step 1/8: System dependencies ──"
pre_flight
run_step 10-deps.sh
echo ""

echo "── Step 2/8: GE-Proton ──"
run_step 20-ge-proton.sh
echo ""

echo "── Step 3/8: Install to system ──"
run_step 25-install-to-location.sh
echo ""

echo "── Step 4/8: Proton prefix ──"
run_step 30-prefix.sh
echo ""

echo "── Step 5/8: WebView2 ──"
run_step 35-webview2.sh
echo ""

echo "── Step 6/8: Config ──"
run_step 37-config.sh
echo ""

echo "── Step 7/8: Protocol handlers ──"
"$SCRIPT_DIR/src/runtime/register-protocols.sh"
echo ""

echo "── Step 8/8: Fusion Installer ──"
run_step 40-fusion-installer.sh
echo ""

clear_traps

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     Install complete. Run:  ./launch-fusion.sh              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
