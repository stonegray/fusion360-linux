# install-scripts/30-prefix.sh — Initialize Proton prefix + winetricks
proton=$(find "$COMPAT_DIR" -name proton -type f 2>/dev/null | head -1 || true)
if [[ -z "$proton" ]]; then
  echo "  [3/7] GE-Proton not found. Run install.sh first."
  exit 1
fi

if [[ -f "$PFX_DIR/pfx/user.reg" ]]; then
  echo "  [3/7] Proton prefix already initialized."
else
  mkdir -p "$PFX_DIR"
  echo "  [3/7] Initializing Proton prefix (wineboot)..."
  STEAM_COMPAT_DATA_PATH="$PFX_DIR" \
  STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam" \
  "$proton" run wineboot -u 2>/dev/null || true
  echo "  [3/7] Prefix initialized."
fi

if command -v winetricks &>/dev/null; then
  if [[ ! -f "$PFX_DIR/pfx/drive_c/windows/system32/vcruntime140.dll" ]]; then
    echo "  [3/7] Installing VC++ runtimes via winetricks..."
    STEAM_COMPAT_DATA_PATH="$PFX_DIR" \
    STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam" \
    WINEPREFIX="$PFX_DIR/pfx" \
    winetricks -q vcrun2022 2>/dev/null || true
    echo "  [3/7] VC++ runtimes done."
  else
    echo "  [3/7] VC++ runtimes already present."
  fi
else
  echo "  [3/7] winetricks not available — skipping VC++ runtime install."
fi

echo "  [3/7] Done."
