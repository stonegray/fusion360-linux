# src/install/40-fusion-installer.sh — Download and run Fusion installer
proton=$(find_proton "$COMPAT_DIR")
if [[ -z "$proton" ]]; then
  log_info " GE-Proton not found. Run install.sh first."
return 1
fi

# ── Streamer log path (truncated before install to detect fresh completion) ─
F360_LOG="$PFX_DIR/pfx/drive_c/users/steamuser/AppData/Local/Autodesk/autodesk.webdeploy.streamer.log"
rm -f "$F360_LOG"

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

cat <<EOF
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
SECONDS=0
STEAM_COMPAT_DATA_PATH="$PFX_DIR" \
STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam" \
PROTON_NO_SECCOMP=1 \
"$proton" run "$INSTALLER_PATH" 2>/dev/null &
INSTALLER_PID=$!

sleep 3
if ! kill -0 "$INSTALLER_PID" 2>/dev/null; then
  log_fail " Fusion installer exited immediately."
  log_info " Possible causes:"
  log_info "  - DLL overrides blocking a required component"
  log_info "  - Corrupted or incompatible installer EXE"
  log_info "  - GE-Proton version incompatibility"
  return 1
fi

log_info " Attaching to installer PID $INSTALLER_PID..."

MAX_WAIT=$((2 * 3600))
while (( SECONDS < MAX_WAIT )); do
  sleep 10
  ELAPSED=$SECONDS
  if ! kill -0 "$INSTALLER_PID" 2>/dev/null; then
    if (( ELAPSED < 240 )); then
      log_fail " Fusion installer exited unexpectedly (${ELAPSED}s)."
      return 1
    fi
    break
  fi
  if [[ -f "$F360_LOG" ]] && grep -q "Configure app complete\|VersionExists" "$F360_LOG" 2>/dev/null; then
    break
  fi
done

if (( SECONDS >= MAX_WAIT )); then
  log_warn " Installer did not complete within 2 hours — continuing anyway."
fi
log_info " Killing Fusion installer processes..."
kill_fusion_processes || true
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
Actions=NewDocument;ServiceUtility;

[Desktop Action NewDocument]
Name=New Document
Icon=fusion360
Exec=$F360_DATA_DIR/launch-fusion.sh

[Desktop Action ServiceUtility]
Name=Service Utility
Icon=fusion360
Exec=$F360_DATA_DIR/launch-fusion.sh --service-util
EOF
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$F360_APPS_DIR" 2>/dev/null || true
  command -v kbuildsycoca6 &>/dev/null && kbuildsycoca6 2>/dev/null || true
  command -v kbuildsycoca5 &>/dev/null && kbuildsycoca5 2>/dev/null || true
  log_info " Desktop entry installed."
else
  log_info " Fusion360.exe not found yet. Install may still be in progress."
  log_info " Run ./setup-fusion.sh once Fusion360.exe exists."
fi
