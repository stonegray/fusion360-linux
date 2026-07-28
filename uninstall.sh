#!/usr/bin/env bash
# uninstall.sh — Clean removal of Fusion360 Linux setup
# Removes Proton prefix, config, desktop files, icons, and bridge temp files.
# Does NOT remove GE-Proton from compatibilitytools.d (other apps may use it).

set -euo pipefail

# ── Root guard ─────────────────────────────────────────────────────────
if [[ $EUID -eq 0 ]]; then
  cat >&2 <<EOF
ERROR: Do not run uninstall.sh as root.
  It removes files from your home directory. Run as a normal user.
  (If you need to remove root-owned files, re-clone and run as user.)
EOF
  exit 1
fi

RED='\033[0;31m'
NC='\033[0m'

echo "=== Fusion360 Linux — Uninstall ==="
echo ""
echo -e "${RED}WARNING: This will remove all Fusion360 local data.${NC}"
echo "  - Proton prefix (~/.fusion360-proton2) — contains Fusion360 itself"
echo "  - Config files (~/.config/fusion360-linux)"
echo "  - Desktop entries and protocol handlers"
echo "  - Application icons"
echo "  - Bridge temporary files (/tmp/fusion360-*)"
echo ""
echo "  GE-Proton in ~/.local/share/Steam/compatibilitytools.d/ will NOT be removed."
echo ""

read -r -p "Remove all Fusion360 files? [y/N] " response
case "$response" in
  [yY]|[yY][eE][sS])
    ;;
  *)
    echo "Aborted."
    exit 0
    ;;
esac

echo ""
echo "Removing..."

# 1. Proton prefix (the entire ~6.7GB Fusion360 installation)
if [[ -d "$HOME/.fusion360-proton2" ]]; then
  echo "  Removing Proton prefix..."
  rm -rf "$HOME/.fusion360-proton2"
  echo "    Removed: ~/.fusion360-proton2"
else
  echo "  [SKIP] ~/.fusion360-proton2 not found."
fi

# 2. Config
if [[ -d "$HOME/.config/fusion360-linux" ]]; then
  echo "  Removing config files..."
  rm -rf "$HOME/.config/fusion360-linux"
  echo "    Removed: ~/.config/fusion360-linux"
else
  echo "  [SKIP] ~/.config/fusion360-linux not found."
fi

# 3. Protocol handler desktop file
if [[ -f "$HOME/.local/share/applications/fusion360-linux/fusion360-callback-handler.desktop" ]]; then
  echo "  Removing callback handler desktop entry..."
  rm -f "$HOME/.local/share/applications/fusion360-linux/fusion360-callback-handler.desktop"
  echo "    Removed: fusion360-callback-handler.desktop"
else
  echo "  [SKIP] fusion360-callback-handler.desktop not found."
fi

# 4. Main desktop entry
if [[ -f "$HOME/.local/share/applications/fusion360-linux/autodesk-fusion360.desktop" ]]; then
  echo "  Removing Autodesk Fusion 360 desktop entry..."
  rm -f "$HOME/.local/share/applications/fusion360-linux/autodesk-fusion360.desktop"
  echo "    Removed: autodesk-fusion360.desktop"
else
  echo "  [SKIP] autodesk-fusion360.desktop not found."
fi

# 5. Icons
found_icons=0
for icon in "$HOME"/.local/share/icons/hicolor/*/apps/fusion360.png; do
  if [[ -f "$icon" ]]; then
    rm -f "$icon"
    echo "    Removed icon: $icon"
    found_icons=1
  fi
done
if [[ $found_icons -eq 0 ]]; then
  echo "  [SKIP] No fusion360 icons found."
fi

# 6. Bridge temp files
if compgen -G '/tmp/fusion360-*' > /dev/null 2>&1; then
  rm -rf /tmp/fusion360-*
  echo "    Removed: bridge temp files."
else
  echo "    No bridge temp files to remove."
fi

# 7. Refresh KDE menu if available
if command -v kbuildsycoca6 &>/dev/null; then
  kbuildsycoca6 2>/dev/null || true
elif command -v kbuildsycoca5 &>/dev/null; then
  kbuildsycoca5 2>/dev/null || true
fi

echo ""
echo "============================================================"
echo "Uninstall complete."
echo ""
echo "GE-Proton in ~/.local/share/Steam/compatibilitytools.d/ was left in place."
echo "Remove it manually if no other applications need it:"
echo "  rm -rf ~/.local/share/Steam/compatibilitytools.d/GE-Proton*/"
echo "============================================================"
