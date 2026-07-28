# install-scripts/40-fusion-installer.sh — Download and run Fusion installer
proton=$(find "$COMPAT_DIR" -name proton -type f 2>/dev/null | head -1 || true)
if [[ -z "$proton" ]]; then
  echo "  [5/5] GE-Proton not found. Run install.sh first."
  exit 1
fi

# ── Check for a running installer ─────────────────────────────────────
if installer_is_running; then
  echo "  [5/5] A previous Fusion installer appears to be running."
  echo -n "  [5/5] Kill it and restart? [Y/n] "
  read -r response
  case "$response" in
    n|N|no|No)
      echo "  [5/5] Aborted."
      exit 1
      ;;
    *)
      kill_installer
      sleep 1
      ;;
  esac
fi

# ── Find or download installer ────────────────────────────────────────
if [[ -n "${INSTALLER_PATH_OVERRIDE:-}" ]]; then
  if [[ -f "$INSTALLER_PATH_OVERRIDE" ]]; then
    INSTALLER_PATH="$INSTALLER_PATH_OVERRIDE"
  else
    echo "  [5/5] Specified path not found: $INSTALLER_PATH_OVERRIDE"
    exit 1
  fi
fi

if [[ -z "${INSTALLER_PATH:-}" ]]; then
  mkdir -p "$HOME/Downloads/fusion360-linux-install"
  find_installer || true
fi

if [[ -z "${INSTALLER_PATH:-}" ]]; then
  echo "  [5/5] Downloading Fusion installer..."
  wget -O "$HOME/Downloads/fusion360-linux-install/FusionClientDownloader.exe" \
    "https://dl.appstreaming.autodesk.com/production/installers/Fusion%20Client%20Downloader.exe" || {
    cat >&2 <<EOF

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
    exit 1
  }
  find_installer || true
  if [[ -z "$INSTALLER_PATH" ]]; then
    echo "  [5/5] Download failed. Try manually with --installer-path."
    exit 1
  fi
fi

# ── Launch installer in background (track PID for cleanup) ────────────
echo "  [5/5] Found: $INSTALLER_PATH"
echo "  [5/5] Launching Fusion installer through Proton..."
echo "  [5/5] A Windows installer window will appear. Click through it."
echo ""
echo "  ┌─ IMPORTANT ────────────────────────────────────────────┐"
echo "  │ Complete the installer in the window that appears.     │"
echo "  │ When it shows \"Finish\", the installation is done.      │"
echo "  └────────────────────────────────────────────────────────┘"
echo ""

mkdir -p "$PFX_DIR"
source "$SCRIPT_DIR/helpers/run_scrollbox.sh"
run_scrollbox --pid INSTALLER_PID 10 \
  "STEAM_COMPAT_DATA_PATH='$PFX_DIR' \
   STEAM_COMPAT_CLIENT_INSTALL_PATH='$HOME/.local/share/Steam' \
   '$proton' run '$INSTALLER_PATH' 2>&1" || true

# ── Check result ──────────────────────────────────────────────────────
echo ""
echo "  [5/5] Installer exited. Checking for Fusion360.exe..."
fusion_exe=$(find "$PFX_DIR" -name Fusion360.exe -type f 2>/dev/null | head -1 || true)
if [[ -n "$fusion_exe" ]]; then
  echo "  [5/5] Fusion360.exe found — install succeeded."
else
  echo "  [5/5] Fusion360.exe not found yet. The installer may still be running"
  echo "  [5/5] or it may need to finish downloading components."
  echo "  [5/5] Run ./setup-fusion.sh once Fusion360.exe exists."
fi
