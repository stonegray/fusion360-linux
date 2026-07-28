# src/install/40-fusion-installer.sh — Download and run Fusion installer
proton=$(find "$COMPAT_DIR" -name proton -type f 2>/dev/null | head -1 || true)
if [[ -z "$proton" ]]; then
  echo "  [5/5] GE-Proton not found. Run install.sh first."
return 1
fi

# ── Check if installer already completed ──────────────────────────────
F360_LOG="$PFX_DIR/pfx/drive_c/users/steamuser/AppData/Local/Autodesk/autodesk.webdeploy.streamer.log"
if [[ -f "$F360_LOG" ]] && grep -q "Configure app complete" "$F360_LOG" 2>/dev/null; then
  echo "  [5/5] Fusion installer already completed. Skipping."
  # Still check for Fusion.exe for desktop entry
  fusion_exe=$(find "$PFX_DIR" -name Fusion360.exe -type f 2>/dev/null | head -1 || true)
  if [[ -n "$fusion_exe" ]]; then
    echo "  [5/5] Fusion360.exe found."
    echo "  [5/5] Installing desktop entry..."
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
    echo "  [5/5] Desktop entry installed."
  fi
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
  echo "  [5/5] Wine/Proton processes from a previous run detected."
  echo -n "  [5/5] Kill them? [Y/n] "
  read -r response
  case "$response" in
    n|N|no|No)
      echo "  [5/5] Aborted."
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
    echo "  [5/5] Specified path not found: $INSTALLER_PATH_OVERRIDE"
return 1
  fi
fi

if [[ -z "${INSTALLER_PATH:-}" ]]; then
  mkdir -p "$HOME/Downloads/fusion360-linux-install"
  find_installer || true
fi

if [[ -z "${INSTALLER_PATH:-}" ]]; then
  echo "  [5/5] Downloading Fusion installer..."
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
    echo "  [5/5] Download failed. Try manually with --installer-path."
return 1
  fi
fi

# ── Launch installer ──────────────────────────────────────────────────
echo "  [5/7] Found: $INSTALLER_PATH"
echo "  [5/7] Launching Fusion installer through Proton..."
echo "  [5/7] A Windows installer window will appear. Click through it."
echo ""
echo "  ┌─ IMPORTANT ────────────────────────────────────────────┐"
echo "  │ Complete the installer in the window that appears.     │"
echo "  │ When it shows \"Finish\", the installation is done.      │"
echo "  └────────────────────────────────────────────────────────┘"
echo ""

mkdir -p "$PFX_DIR"
STEAM_COMPAT_DATA_PATH="$PFX_DIR" \
STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam" \
"$proton" run "$INSTALLER_PATH" 2>/dev/null || true

# ── Wait for Fusion360.exe + installer completion ─────────────────
echo ""
echo "  [installer] Waiting for install to finish..."
echo "  [installer] Complete the installer in the window that appeared."
echo "  [installer] The script will detect when it's done automatically."
F360_LOG="$PFX_DIR/pfx/drive_c/users/steamuser/AppData/Local/Autodesk/autodesk.webdeploy.streamer.log"
FUSION_PID=""
F360_EXE=""
for i in $(seq 1 30); do
  sleep 10
  FUSION_PID=$(pgrep -u "$(id -u)" -f "Fusion360\.exe" 2>/dev/null | head -1 || true)
  F360_EXE=$(find "$PFX_DIR" -name Fusion360.exe -type f 2>/dev/null | head -1 || true)
  LOG_DONE=0
  [[ -f "$F360_LOG" ]] && grep -q "Configure app complete" "$F360_LOG" 2>/dev/null && LOG_DONE=1
  if [[ $LOG_DONE -eq 1 && ( -n "$FUSION_PID" || -n "$F360_EXE" ) ]]; then
    if [[ -n "$FUSION_PID" ]]; then
      echo "  [installer] Install complete and Fusion360.exe running (PID $FUSION_PID)."
      echo "  [installer] Letting it initialize for 5 seconds..."
      sleep 5
    else
      echo "  [installer] Install complete — Fusion360.exe found on disk."
    fi
    break
  fi
  if [[ -n "$FUSION_PID" ]]; then
    echo "  [installer] Fusion360.exe started, waiting for install to finalize..."
  fi
  if [[ $i -eq 15 ]]; then
    echo "  [installer] Still waiting... (installer window may still be open)"
  fi
done

if [[ $LOG_DONE -eq 1 && ( -n "$FUSION_PID" || -n "$F360_EXE" ) ]]; then
  if [[ -n "$FUSION_PID" ]]; then
    echo "  [installer] Killing Fusion360 after first-run setup..."
    source "$SCRIPT_DIR/src/runtime/launcher-functions.sh"
    kill_fusion_processes
    kill "$FUSION_PID" 2>/dev/null || true
    sleep 1
    kill -9 "$FUSION_PID" 2>/dev/null || true
  else
    echo "  [installer] Fusion360 already exited — cleaning up remaining processes..."
    kill_installer
  fi
  echo "  [installer] Done. Auth will complete on next launch."
else
  echo "  [installer] Install did not complete within 5 minutes."
  echo "  [installer] Complete the installer manually, then run: ./launch-fusion.sh"
  kill_installer
fi

# ── Check result ──────────────────────────────────────────────────────
echo ""
echo "  [10/12] Checking for Fusion360.exe..."
fusion_exe=$(find "$PFX_DIR" -name Fusion360.exe -type f 2>/dev/null | head -1 || true)
if [[ -n "$fusion_exe" ]]; then
  echo "  [10/12] Fusion360.exe found — install succeeded."
  echo "  [10/12] Installing desktop entry..."
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
  echo "  [10/12] Desktop entry installed."
else
  echo "  [10/12] Fusion360.exe not found yet. Install may still be in progress."
  echo "  [10/12] Run ./setup-fusion.sh once Fusion360.exe exists."
fi
