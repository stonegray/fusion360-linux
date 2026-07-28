#!/usr/bin/env bash
# status.sh — Diagnostic tool for Fusion360 on Linux prerequisites
# Prints [PASS] or [FAIL] for each check. Exits 0 if all pass, 1 otherwise.

set -euo pipefail

# ── Root guard ─────────────────────────────────────────────────────────
if [[ $EUID -eq 0 ]]; then
  echo "ERROR: Do not run status.sh as root. Run as a normal user." >&2
  exit 1
fi

PASS=0
FAIL=0

check() {
  local label="$1"
  shift
  if "$@" &>/dev/null; then
    echo "  [PASS] $label"
    PASS=$((PASS + 1))
  else
    echo "  [FAIL] $label"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Fusion360 Linux — Status Check ==="
echo ""

# Distro
distro_name="$(source /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || echo "unknown")"
echo "  System: $distro_name"

# Display server
echo "  Display: ${DISPLAY:-${WAYLAND_DISPLAY:-none}}"
echo ""

echo "--- Prerequisites ---"

# 1. GE-Proton
check "GE-Proton installed" \
  find "$HOME/.local/share/Steam/compatibilitytools.d/" -name proton -type f -print -quit | grep -q .

# 2. Proton prefix
check "Proton prefix exists" \
  test -d "$HOME/.fusion360-proton2/pfx"

# 3. Fusion360.exe
check "Fusion360.exe found" \
  find "$HOME/.fusion360-proton2" -name Fusion360.exe -type f -print -quit | grep -q .

# 4. WebView2 installed
PFX="$HOME/.fusion360-proton2/pfx"
check "WebView2 runtime installed" \
  test -d "$PFX/drive_c/Program Files (x86)/Microsoft/EdgeWebView"

# 5. Config file
check "Config file exists" \
  test -f "${XDG_CONFIG_HOME:-$HOME/.config}/fusion360-linux/config"

# 6. Protocol handlers
check "adsk:// protocol handler registered" \
  xdg-mime query default x-scheme-handler/adsk 2>/dev/null | grep -qi "fusion360-callback-handler"

# 7. Desktop entry
check "Desktop entry installed" \
  test -f "$HOME/.local/share/applications/autodesk-fusion360.desktop"

# 8. Icons installed
check "Application icons installed" \
  test -f "$HOME/.local/share/icons/hicolor/256x256/apps/fusion360.png"

# 9. Bridge temp directories
check "Bridge temp directories exist" \
  test -d "/tmp/fusion360-browser-requests"

# 10. Disk space
available_kb=$(df --output=avail "$HOME" 2>/dev/null | tail -n1)
available_gb=$((available_kb / 1024 / 1024))
echo "  [INFO]  Disk space available: ${available_gb}GB on $HOME"

echo ""
echo "--- Summary ---"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo ""

if [[ $FAIL -eq 0 ]]; then
  echo "All checks passed. Fusion360 should be ready to launch."
  exit 0
else
  echo "Some checks failed. Run install.sh and/or setup-fusion.sh to fix."
  exit 1
fi
