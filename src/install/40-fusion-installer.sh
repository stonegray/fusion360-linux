# src/install/40-fusion-installer.sh — Download and run Fusion installer
proton=$(find "$COMPAT_DIR" -name proton -type f 2>/dev/null | head -1 || true)
if [[ -z "$proton" ]]; then
  log_info " GE-Proton not found. Run install.sh first."
return 1
fi

# ── Check if installer already completed ──────────────────────────────
F360_INSTALL_FLAG="$F360_DATA_DIR/flags/fusion-installed"
if [[ -f "$F360_INSTALL_FLAG" ]]; then
  log_info " Fusion installer already completed (flag: $F360_INSTALL_FLAG). Skipping."
  # Still install desktop entry if missing
  fusion_exe=$(find "$PFX_DIR" -name Fusion360.exe -type f 2>/dev/null | head -1 || true)
  if [[ -n "$fusion_exe" ]] && [[ ! -f "$F360_APPS_DIR/autodesk-fusion360.desktop" ]]; then
    log_info " Installing desktop entry..."
    mkdir -p "$F360_APPS_DIR"
    cat > "$F360_APPS_DIR/autodesk-fusion360.desktop" <<EOF
[Desktop Entry]
Name=Autodesk Fusion 360
Comment=Fusion 360 CAD/CAM/CAE tool
Exec=$F360_DATA_DIR/launch-fusion.sh %F
Icon=fusion360
Type=Application
Categories=Graphics;Science;Engineering;
MimeType=application/vnd.autodesk.fusion360;model/step;model/iges;model/stl;model/3mf;image/vnd.dxf;model/x-obj;model/x-acis-sat;model/x-fbx;application/x-inventor-assembly;application/x-inventor-part;model/x-rhino-3dm;application/x-solidworks-part;application/x-solidworks-assembly;model/x-parasolid;
StartupNotify=true
StartupWMClass=fusion360.exe
EOF
    update-desktop-database "$F360_APPS_DIR" 2>/dev/null || true
    if command -v kbuildsycoca6 &>/dev/null; then
      kbuildsycoca6 2>/dev/null || true
    elif command -v kbuildsycoca5 &>/dev/null; then
      kbuildsycoca5 2>/dev/null || true
    fi
  fi
  return 0
fi
# ── Fallback: check streamer log (for pre-flag installs) ─────────
F360_LOG="$PFX_DIR/pfx/drive_c/users/steamuser/AppData/Local/Autodesk/autodesk.webdeploy.streamer.log"
if [[ -f "$F360_LOG" ]] && grep -q "Configure app complete" "$F360_LOG" 2>/dev/null; then
  log_info " Fusion installer already completed (from log)."
  mkdir -p "$(dirname "$F360_INSTALL_FLAG")"
  touch "$F360_INSTALL_FLAG"
  return 0
fi

# ── Check for leftover processes, prompt to kill ──────────────────────
user_id=$(id -u)
running=0
for pattern in wineserver wine proton xalia streamer \
  Fusion360 FusionClientDownloader AdskIdentity adexmtsv \
  steam.exe node.exe fusion-gray-overlay; do
  if pgrep -u "$user_id" -f "$pattern" &>/dev/null; then
    running=1
    break
  fi
done

if (( running )); then
  log_info " Wine/Proton processes from a previous run detected."
  echo -n "  [5/5] Kill them? [Y/n] "
  read -r response
  case "$response" in
    n|N|no|No)
      log_info " Aborted."
return 1
      ;;
  esac
  kill_installer
fi

# ── Find or download installer ────────────────────────────────────────
if [[ -n "${INSTALLER_PATH_OVERRIDE:-}" ]]; then
  if [[ -f "$INSTALLER_PATH_OVERRIDE" ]]; then
    INSTALLER_PATH="$INSTALLER_PATH_OVERRIDE"
  else
    log_info " Specified path not found: $INSTALLER_PATH_OVERRIDE"
return 1
  fi
fi

if [[ -z "${INSTALLER_PATH:-}" ]]; then
  mkdir -p "$HOME/Downloads/fusion360-linux-install"
  find_installer || true
fi

if [[ -z "${INSTALLER_PATH:-}" ]]; then
  log_info " Downloading Fusion installer..."
  wget --timeout=30 -O "$HOME/Downloads/fusion360-linux-install/FusionClientDownloader.exe" \
    "https://dl.appstreaming.autodesk.com/production/installers/Fusion%20Client%20Downloader.exe" || {

  ┌─ Manual download ────────────────────────────────────────────┐
  │                                                                │
  │  Download FusionClientDownloader.exe manually from:             │
  │    https://dl.appstreaming.autodesk.com/production/installers/  │
  │      Fusion%20Client%20Downloader.exe                          │
  │                                                                │
  │  Then run:                                                     │
  │    ./install.sh --installer-path /path/to/FusionClientDownloader.exe
  │                                                                │
  └────────────────────────────────────────────────────────────────┘
EOF
return 1
  }
  find_installer || true
  if [[ -z "$INSTALLER_PATH" ]]; then
    log_info " Download failed. Try manually with --installer-path."
return 1
  fi
fi

# ── Launch installer ──────────────────────────────────────────────────
log_info " Found: $INSTALLER_PATH"
log_info " Launching Fusion installer through Proton..."
echo ""
echo "  ┌─ IMPORTANT ────────────────────────────────────────────┐"
echo "  │ This is a fully automated installer.  This script will │"
echo "  │ monitor the Fusion install progress and take control   │"
echo "  │ before completion; don't be alarmed if it disappears   │"
echo "  │ around 80%.                                             │"
echo "  └────────────────────────────────────────────────────────┘"
echo ""

mkdir -p "$PFX_DIR"
STEAM_COMPAT_DATA_PATH="$PFX_DIR" \
STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam" \
"$proton" run "$INSTALLER_PATH" 2>/dev/null || true

echo ""
log_info " Waiting for install to finish..."
log_info " The script will detect when it's done and close the installer"
log_info " automatically."
WAIT_COUNT=0
while true; do
  sleep 10
  WAIT_COUNT=$((WAIT_COUNT + 1))
  FUSION_PID=$(pgrep -u "$(id -u)" -f "Fusion360\.exe" 2>/dev/null | head -1 || true)
  F360_EXE=$(find "$PFX_DIR" -name Fusion360.exe -type f 2>/dev/null | head -1 || true)
  LOG_DONE=0
  [[ -f "$F360_LOG" ]] && grep -q "Configure app complete" "$F360_LOG" 2>/dev/null && LOG_DONE=1
  if [[ $LOG_DONE -eq 1 && ( -n "$FUSION_PID" || -n "$F360_EXE" ) ]]; then
    if [[ -n "$FUSION_PID" ]]; then
      log_info " Install complete and Fusion360.exe running (PID $FUSION_PID)."
      log_info " Letting it initialize for 5 seconds..."
      sleep 5
    else
      log_info " Install complete — Fusion360.exe found on disk."
    fi
    break
  fi
  if [[ -n "$FUSION_PID" ]]; then
    log_info " Fusion360.exe started, waiting for install to finalize..."
  fi
  if (( WAIT_COUNT % 6 == 0 )); then
    log_info " Still waiting... (installer window may still be open, $((WAIT_COUNT * 10 / 60)) min elapsed)"
  fi
done

if [[ -n "$FUSION_PID" ]]; then
  log_info " Killing Fusion360 after first-run setup..."
  source "$SCRIPT_DIR/src/runtime/launcher-functions.sh"
  kill_fusion_processes
  kill "$FUSION_PID" 2>/dev/null || true
  sleep 1
  kill -9 "$FUSION_PID" 2>/dev/null || true
else
  log_info " Fusion360 already exited — cleaning up remaining processes..."
  kill_installer
fi
log_info " Done. Auth will complete on next launch."

# ── Check result ──────────────────────────────────────────────────────
echo ""
log_info " Checking for Fusion360.exe..."
fusion_exe=$(find "$PFX_DIR" -name Fusion360.exe -type f 2>/dev/null | head -1 || true)
if [[ -n "$fusion_exe" ]]; then
  log_info " Fusion360.exe found — install succeeded."
  log_info " Installing desktop entry..."
  mkdir -p "$F360_APPS_DIR"
  cat > "$F360_APPS_DIR/autodesk-fusion360.desktop" <<EOF
[Desktop Entry]
Name=Autodesk Fusion 360
Comment=Fusion 360 CAD/CAM/CAE tool
Exec=$F360_DATA_DIR/launch-fusion.sh %F
Icon=fusion360
Type=Application
Categories=Graphics;Science;Engineering;
MimeType=application/vnd.autodesk.fusion360;model/step;model/iges;model/stl;model/3mf;image/vnd.dxf;model/x-obj;model/x-acis-sat;model/x-fbx;application/x-inventor-assembly;application/x-inventor-part;model/x-rhino-3dm;application/x-solidworks-part;application/x-solidworks-assembly;model/x-parasolid;
StartupNotify=true
StartupWMClass=fusion360.exe
EOF
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$F360_APPS_DIR" 2>/dev/null || true
  command -v kbuildsycoca6 &>/dev/null && kbuildsycoca6 2>/dev/null || true
  command -v kbuildsycoca5 &>/dev/null && kbuildsycoca5 2>/dev/null || true
  log_info " Desktop entry installed."
  mkdir -p "$(dirname "$F360_INSTALL_FLAG")"
  touch "$F360_INSTALL_FLAG"
  log_info " Install flag written to $F360_INSTALL_FLAG."
else
  log_info " Fusion360.exe not found yet. Install may still be in progress."
  log_info " Run ./setup-fusion.sh once Fusion360.exe exists."
fi
