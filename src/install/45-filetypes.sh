# src/install/45-filetypes.sh — Register Fusion 360 file type associations
MIME_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/mime"
MIME_PACKAGE="$MIME_DIR/packages/fusion360.xml"

echo "  [11/12] Registering Fusion 360 file type associations..."

if [[ ! -f "$MIME_PACKAGE" ]]; then
  echo "  [11/12] MIME definitions not found at $MIME_PACKAGE"
  echo "  [11/12] Run install step 3 first to copy MIME XML."
  return 1
fi

# Update MIME database so file managers know .f3d/.step/.stl etc.
if command -v update-mime-database &>/dev/null; then
  update-mime-database "$MIME_DIR" 2>/dev/null || true
  echo "  [11/12] MIME database updated — file managers should recognize Fusion formats."
else
  echo "  [11/12] update-mime-database not found — MIME types installed but not indexed."
fi
## Install MIME type icons so file managers show the Fusion icon for .f3d files
HICOLOR_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ICON_SRC_DIR="$SCRIPT_DIR/data/icons/hicolor"
if [[ -d "$ICON_SRC_DIR" ]]; then
  for size_dir in "$ICON_SRC_DIR"/*; do
    size=$(basename "$size_dir")
    icon_file="$size_dir/mimetypes/application-vnd.autodesk.fusion360.png"
    if [[ -f "$icon_file" ]]; then
      mkdir -p "$HICOLOR_DIR/$size/mimetypes"
      cp "$icon_file" "$HICOLOR_DIR/$size/mimetypes/"
    fi
  done
  echo "  [11/12] MIME type icons installed."
else
  echo "  [11/12] MIME type icons not found at $ICON_SRC_DIR — skipping."
fi

# Register Fusion 360 as default for its native formats
if command -v xdg-mime &>/dev/null; then
  xdg-mime default autodesk-fusion360.desktop application/vnd.autodesk.fusion360 2>/dev/null || true
  echo "  [11/12] Fusion 360 set as default for .f3d/.f3z files."
  fi

# Re-assert protocol handlers — Wine/Fusion installer may have registered its own
if command -v xdg-mime &>/dev/null; then
  xdg-mime default fusion360-callback-handler.desktop x-scheme-handler/adsk 2>/dev/null || true
  xdg-mime default fusion360-callback-handler.desktop x-scheme-handler/adskidmgr 2>/dev/null || true
  echo "  [11/12] Protocol handlers (adsk://, adskidmgr://) re-registered."
fi

# Regenerate global desktop database to flush stale Wine entries
if command -v update-desktop-database &>/dev/null; then
  update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
  echo "  [11/12] Global desktop database refreshed."
fi

# Refresh desktop database for our app directory
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

# ── Register NLauncher.exe in Wine prefix ─────────────────────────
# This lets Windows ShellExecute (inside the Wine prefix) open .f3d
# files and fusion360:// protocol URLs via NLauncher.exe, which
# communicates with the running Fusion instance without starting a
# second copy.
local system_reg="$PFX_DIR/pfx/system.reg"
if [[ -f "$system_reg" ]]; then
  local nlauncher
  nlauncher=$(find "$PFX_DIR" -name NLauncher.exe -type f 2>/dev/null | head -1 || true)
  if [[ -n "$nlauncher" ]]; then
    local nlauncher_dos; nlauncher_dos="Z:${nlauncher//\//\\}"
    local cmdline="\"$nlauncher_dos\" \"%1\""
    if grep -q 'NLauncher\.exe.*%1' "$system_reg" 2>/dev/null; then
      echo "  [11/12] Wine prefix already has NLauncher.exe registry entries."
    else
      printf '\n[Software\\Classes\\.f3d] 1785266656\n#time=1dd1ebee782a462\n@="Fusion360.AssocDocument"\n' >> "$system_reg"
      printf '[Software\\Classes\\Fusion360.AssocDocument\\shell\\open\\command] 1785266656\n#time=1dd1ebee782a462\n@=%s\n' "$cmdline" >> "$system_reg"
      printf '[Software\\Classes\\fusion360] 1785265986\n#time=1dd1ebee782a462\n"URL Protocol"=""\n@="URL:Fusion360 Protocol"\n' >> "$system_reg"
      printf '[Software\\Classes\\fusion360\\shell\\open\\command] 1785266657\n#time=1dd1ebee782a462\n@=%s\n' "$cmdline" >> "$system_reg"
      echo "  [11/12] Wine prefix registered NLauncher.exe for .f3d and fusion360://."
    fi
  else
    echo "  [11/12] Warning: NLauncher.exe not found — skipping Wine prefix registration."
  fi
fi

echo "  [11/12] Done."
