# src/install/45-filetypes.sh — Register Fusion 360 file type associations
MIME_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/mime"
MIME_PACKAGE="$MIME_DIR/packages/fusion360.xml"

log_info " Registering Fusion 360 file type associations..."

if [[ ! -f "$MIME_PACKAGE" ]]; then
  log_info " MIME definitions not found at $MIME_PACKAGE"
  log_info " Run install step 3 first to copy MIME XML."
  return 1
fi

# Update MIME database so file managers know .f3d/.step/.stl etc.
if command -v update-mime-database &>/dev/null; then
  update-mime-database "$MIME_DIR" 2>/dev/null || true
  log_info " MIME database updated — file managers should recognize Fusion formats."
else
  log_info " update-mime-database not found — MIME types installed but not indexed."
fi
# ── Install MIME type icon for .f3d files ───────────────────────
# Extracts Fusion's icon from the Wine prefix and installs it at
# standard sizes in the hicolor theme so file managers show a
# Fusion icon for .f3d files instead of a generic one.
_install_fusion_mime_icon() {
  local sizes="16 22 24 32 48 64 128 256"
  local hicolor="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor"
  local icondir="${F360_DATA_DIR:-$HOME/.local/share/fusion360-linux}/icons"
  local master="$icondir/fusion360.png"
  local ico="" ok=false d s

  # Find Fusion360.ico in the prefix or extract from Fusion360.exe
  ico=$(find "$PFX_DIR" -maxdepth 5 -name "Fusion360.ico" 2>/dev/null | head -1)
  if [[ -z "$ico" ]]; then
    local exe; exe=$(find "$PFX_DIR" -name Fusion360.exe -type f 2>/dev/null | head -1) || true
    if [[ -n "$exe" ]] && command -v wrestool &>/dev/null; then
      mkdir -p "$icondir"
      wrestool -x -t 14 "$exe" -o "$icondir/" 2>/dev/null || true
      ico=$(find "$icondir" -maxdepth 1 -name "*.ico" 2>/dev/null | head -1)
    fi
  fi
  [[ -z "$ico" ]] && { log_info " Warning: Fusion icon not found — skipping MIME icon."; return; }

  # Convert .ico → master PNG (try ImageMagick first, then ffmpeg)
  if command -v convert &>/dev/null; then
    mkdir -p "$icondir"
    convert "${ico}[7]" "$master" 2>/dev/null || \
    convert "${ico}[6]" "$master" 2>/dev/null || \
    convert "$ico" -flatten "$master" 2>/dev/null || true
    [[ -f "$master" ]] && ok=true
  fi
  if ! $ok && command -v ffmpeg &>/dev/null; then
    mkdir -p "$icondir"
    ffmpeg -i "$ico" "$master" -y 2>/dev/null || true
    [[ -f "$master" ]] && ok=true
  fi
  if ! $ok; then
    log_info " Warning: could not convert icon to PNG — skipping MIME icon."
    return
  fi

  # Install resized PNGs into the hicolor MIME theme
  for s in $sizes; do
    d="$hicolor/${s}x${s}/mimetypes"
    mkdir -p "$d"
    convert "$master" -resize "${s}x${s}" "$d/application-vnd.autodesk.fusion360.png" 2>/dev/null || true
  done

  # Ensure hicolor index.theme lists our mimetypes directories
  # (without Directories= the icon cache ignores them entirely)
  local idx="$hicolor/index.theme"
  if [[ ! -f "$idx" ]] || ! grep -q 'mimetypes' "$idx" 2>/dev/null; then
    local dirs="" sd
    for sd in $sizes; do dirs="${dirs}${sd}x${sd}/mimetypes,"; done
    mkdir -p "$hicolor"
    {
      echo "[Icon Theme]"
      echo "Name=Hicolor"
      echo "Comment=Fusion 360 MIME icons"
      echo "Directories=${dirs%,}"
      for sd in $sizes; do
        echo ""
        echo "[${sd}x${sd}/mimetypes]"
        echo "Size=${sd}"
        echo "Context=MimeTypes"
        echo "Type=Fixed"
      done
    } > "$idx"
  fi

  # Refresh icon caches so file managers pick up the new icons immediately
  command -v gtk-update-icon-cache &>/dev/null && gtk-update-icon-cache -f "$hicolor" 2>/dev/null || true
  if command -v kbuildsycoca6 &>/dev/null; then
    kbuildsycoca6 --noincremental 2>/dev/null || true
  elif command -v kbuildsycoca5 &>/dev/null; then
    kbuildsycoca5 --noincremental 2>/dev/null || true
  fi

  rm -f "$icondir"/*.ico 2>/dev/null || true
  log_info " Fusion 360 MIME icons installed."
}
_install_fusion_mime_icon

# Register Fusion 360 as default for its native formats
if command -v xdg-mime &>/dev/null; then
  xdg-mime default autodesk-fusion360.desktop application/vnd.autodesk.fusion360 2>/dev/null || true
  log_info " Fusion 360 set as default for .f3d/.f3z files."
  fi

# Re-assert protocol handlers — Wine/Fusion installer may have registered its own
if command -v xdg-mime &>/dev/null; then
  xdg-mime default fusion360-callback-handler.desktop x-scheme-handler/adsk 2>/dev/null || true
  xdg-mime default fusion360-callback-handler.desktop x-scheme-handler/adskidmgr 2>/dev/null || true
  log_info " Protocol handlers (adsk://, adskidmgr://) re-registered."
fi

# Regenerate global desktop database to flush stale Wine entries
if command -v update-desktop-database &>/dev/null; then
  update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
  log_info " Global desktop database refreshed."
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
      log_info " Wine prefix already has NLauncher.exe registry entries."
    else
      printf '\n[Software\\Classes\\.f3d] 1785266656\n#time=1dd1ebee782a462\n@="Fusion360.AssocDocument"\n' >> "$system_reg"
      printf '[Software\\Classes\\Fusion360.AssocDocument\\shell\\open\\command] 1785266656\n#time=1dd1ebee782a462\n@=%s\n' "$cmdline" >> "$system_reg"
      printf '[Software\\Classes\\fusion360] 1785265986\n#time=1dd1ebee782a462\n"URL Protocol"=""\n@="URL:Fusion360 Protocol"\n' >> "$system_reg"
      printf '[Software\\Classes\\fusion360\\shell\\open\\command] 1785266657\n#time=1dd1ebee782a462\n@=%s\n' "$cmdline" >> "$system_reg"
      log_info " Wine prefix registered NLauncher.exe for .f3d and fusion360://."
    fi
  else
    log_info " Warning: NLauncher.exe not found — skipping Wine prefix registration."
  fi
fi

# ── Set Wine shell folders to real Linux home directories ────────
# Makes Fusion's file open/save dialog open the user's real Documents
# and Desktop folders instead of the Wine prefix's virtual C: drive.
local user_reg="$PFX_DIR/pfx/user.reg"
if [[ -f "$user_reg" ]] && ! grep -q '^"Personal"="Z:' "$user_reg" 2>/dev/null; then
  # Remove any existing Personal/Desktop/Downloads entries
  sed -i '/^"Personal"=/d; /^"Desktop"=/d; /^"Downloads"=/d' "$user_reg" 2>/dev/null || true
  # Append correct entries — use short pattern match because full
  # Windows path escaping is unreliable across sed versions
  sed -i \
    -e '/User Shell Folders\]/a ""' \
    -e '/User Shell Folders\]/a "Personal"="Z:\\'"$HOME"'\\Documents"' \
    -e '/User Shell Folders\]/a "Desktop"="Z:\\'"$HOME"'\\Desktop"' \
    -e '/User Shell Folders\]/a "Downloads"="Z:\\'"$HOME"'\\Downloads"' \
    "$user_reg" 2>/dev/null || true
  log_info " Wine shell folders set to $HOME/Documents, $HOME/Desktop, $HOME/Downloads."
fi
mkdir -p "$PFX_DIR/pfx/drive_c"
local twf_src="$SCRIPT_DIR/src/toolwindow-fixer/fusion-toolwindow-fixer.c"
local twf_prebuilt="$SCRIPT_DIR/src/toolwindow-fixer/fusion-toolwindow-fixer.exe"
local twf_target="$PFX_DIR/pfx/drive_c/fusion-toolwindow-fixer.exe"
local built_ok=false

# Try compiling from source if the cross-compiler is available
if command -v x86_64-w64-mingw32-gcc &>/dev/null && [[ -f "$twf_src" ]]; then
  log_info " Building toolwindow fixer from source..."
  if x86_64-w64-mingw32-gcc -Os -s -o "$twf_target" "$twf_src" -luser32 2>&1; then
    log_info " Toolwindow fixer built from source."
    built_ok=true
  else
    log_info " Warning: source build failed, falling back to pre-built binary."
  fi
fi

# Fall back to pre-built binary
if [[ "$built_ok" != true ]] && [[ -f "$twf_prebuilt" ]]; then
  cp "$twf_prebuilt" "$twf_target"
  log_info " Toolwindow fixer installed (pre-built binary)."
  built_ok=true
fi

if [[ "$built_ok" != true ]]; then
  log_info " Warning: toolwindow fixer not found — skipping."
fi

log_info " Done."
