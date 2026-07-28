#!/usr/bin/env bash
# install.sh — Install Fusion360 on Linux.
# Thin wrapper over install-scripts/*.sh (numbered steps).
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:-}"
INSTALLER_PATH_OVERRIDE=""

if [[ "${1:-}" == "--installer-path" ]]; then
  INSTALLER_PATH_OVERRIDE="${2:-}"
  [[ -n "$INSTALLER_PATH_OVERRIDE" ]] || { echo "Usage: ./install.sh --installer-path /path/to/exe"; exit 1; }
  MODE="--run-installer"
fi

source "$SCRIPT_DIR/install-scripts/00-common.sh"
setup_traps

run_step() {
  source "$SCRIPT_DIR/install-scripts/$1"
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
    run_step 30-prefix.sh
    clear_traps
    exit 0
    ;;
  --uninstall)
    clear_traps
    source "$SCRIPT_DIR/runtime-scripts/uninstall-select.sh"
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
echo ""

pre_flight

echo "── Step 1/5: System dependencies ──"
run_step 10-deps.sh
echo ""

echo "── Step 2/5: GE-Proton ──"
run_step 20-ge-proton.sh
echo ""

echo "── Step 3/5: Proton prefix + winetricks ──"
run_step 30-prefix.sh
echo ""

echo "── Step 4/5: Configuration (WebView2, handlers, desktop) ──"
if [[ -f "$SCRIPT_DIR/setup-fusion.sh" ]]; then
  "$SCRIPT_DIR/setup-fusion.sh"
else
  echo "  [4/5] setup-fusion.sh not found"
fi
echo ""

echo "── Step 5/5: Fusion Installer ──"
run_step 40-fusion-installer.sh
echo ""

clear_traps

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     Install complete. Run:  ./launch-fusion.sh              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
