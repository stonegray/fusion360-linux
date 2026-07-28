# src/install/45-filetypes.sh — Register Fusion 360 file type associations
MIME_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/mime"
MIME_PACKAGE="$MIME_DIR/packages/fusion360.xml"

echo "  [9/10] Registering Fusion 360 file type associations..."

if [[ ! -f "$MIME_PACKAGE" ]]; then
  echo "  [9/10] MIME definitions not found at $MIME_PACKAGE"
  echo "  [9/10] Run install step 3 first to copy MIME XML."
  return 1
fi

# Update MIME database so file managers know .f3d/.step/.stl etc.
if command -v update-mime-database &>/dev/null; then
  update-mime-database "$MIME_DIR" 2>/dev/null || true
  echo "  [9/10] MIME database updated — file managers should recognize Fusion formats."
else
  echo "  [9/10] update-mime-database not found — MIME types installed but not indexed."
fi

# Register Fusion 360 as default for its native formats
if command -v xdg-mime &>/dev/null; then
  xdg-mime default autodesk-fusion360.desktop application/vnd.autodesk.fusion360 2>/dev/null || true
  echo "  [9/10] Fusion 360 set as default for .f3d/.f3z files."
fi

# Refresh desktop database
if command -v update-desktop-database &>/dev/null; then
  APPS_DIR="${F360_APPS_DIR:-$HOME/.local/share/applications/fusion360-linux}"
  if [[ -d "$APPS_DIR" ]]; then
    update-desktop-database "$APPS_DIR" 2>/dev/null || true
  fi
fi

# Refresh KDE menu if running
if command -v kbuildsycoca6 &>/dev/null; then
  kbuildsycoca6 2>/dev/null || true
elif command -v kbuildsycoca5 &>/dev/null; then
  kbuildsycoca5 2>/dev/null || true
fi

echo "  [9/10] Done."
