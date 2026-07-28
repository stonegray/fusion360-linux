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
FUSION_DATA_DIR="${F360_DATA_DIR:-$HOME/.local/share/fusion360-linux}"
ICON_TARGET="$FUSION_DATA_DIR/icons/fusion360.png"

# Find the Fusion icon in the Wine prefix (extracted by Fusion's installer)
FUSION_ICO=$(find "$PFX_DIR" -maxdepth 5 -name "Fusion360.ico" 2>/dev/null | head -1)
if [[ -z "$FUSION_ICO" ]]; then
  # Try extracting from Fusion360.exe directly
  local fusion_exe
  fusion_exe=$(find "$PFX_DIR" -name Fusion360.exe -type f 2>/dev/null | head -1)
  if [[ -n "$fusion_exe" ]] && command -v wrestool &>/dev/null; then
    mkdir -p "$FUSION_DATA_DIR/icons"
    wrestool -x -t 14 "$fusion_exe" -o "$FUSION_DATA_DIR/icons/" 2>/dev/null || true
    FUSION_ICO=$(find "$FUSION_DATA_DIR/icons" -name "*.ico" 2>/dev/null | head -1)
  fi
fi

if [[ -n "$FUSION_ICO" ]]; then
  mkdir -p "$(dirname "$ICON_TARGET")"
  # Convert .ico to .png for use as MIME icon
  if command -v convert &>/dev/null; then
    convert "$FUSION_ICO" -resize 128x128 "$ICON_TARGET" 2>/dev/null || true
  elif command -v ffmpeg &>/dev/null; then
    ffmpeg -i "$FUSION_ICO" -vf scale=128:128 "$ICON_TARGET" -y 2>/dev/null || true
  fi

  if [[ -f "$ICON_TARGET" ]]; then
    mkdir -p "$HICOLOR_DIR/128x128/mimetypes"
    cp "$ICON_TARGET" "$HICOLOR_DIR/128x128/mimetypes/application-vnd.autodesk.fusion360.png"
    # Also create symlinks at other standard sizes
    for size in 16 22 24 32 48 64 256; do
      mkdir -p "$HICOLOR_DIR/${size}x${size}/mimetypes"
      ln -sf "$ICON_TARGET" "$HICOLOR_DIR/${size}x${size}/mimetypes/application-vnd.autodesk.fusion360.png" 2>/dev/null || true
    done
    echo "  [11/12] Fusion 360 MIME icon installed from $FUSION_ICO"
  else
    echo "  [11/12] Warning: could not convert Fusion icon to PNG — skipping MIME icon."
  fi
else
  echo "  [11/12] Warning: Fusion icon not found in prefix — skipping MIME icon."
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
