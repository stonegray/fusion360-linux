#!/usr/bin/env bash
# runtime-scripts/health-check.sh — Quick health check before launching Fusion.
# Exits 0 if everything looks good, 1 otherwise.

PFX_DIR="$HOME/.fusion360-proton2"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fusion360-linux"
CONFIG_FILE="$CONFIG_DIR/config"

all_ok=1

check() {
  if "$@" &>/dev/null; then
    echo "  [ok] $1"
  else
    echo "  [!!] $1"
    all_ok=0
  fi
}

echo "Fusion360 health check:"

check "Proton prefix exists"    test -d "$PFX_DIR/pfx"
check "Fusion360.exe found"     find "$PFX_DIR" -name Fusion360.exe -type f -print -quit 2>/dev/null | grep -q .
check "WebView2 installed"      test -d "$PFX_DIR/pfx/drive_c/Program Files (x86)/Microsoft/EdgeWebView"
check "Config file exists"      test -f "$CONFIG_FILE"
check "GE-Proton available"     find "$HOME/.local/share/Steam/compatibilitytools.d/" -name proton -type f -print -quit 2>/dev/null | grep -q .
check "Desktop entry"           test -f "$HOME/.local/share/applications/autodesk-fusion360.desktop"
check "Callback handler"        test -f "$HOME/.local/share/applications/fusion360-callback-handler.desktop"

if (( all_ok )); then
  echo "All checks passed."
  exit 0
else
  echo "Some checks failed. Run setup-fusion.sh to fix."
  exit 1
fi
