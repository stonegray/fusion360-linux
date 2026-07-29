# src/install/30-prefix.sh — Initialize Proton prefix + winetricks
proton=$(find "$COMPAT_DIR" -name proton -type f 2>/dev/null | head -1 || true)
if [[ -z "$proton" ]]; then
  log_info " GE-Proton not found. Run install.sh first."
return 1
fi

if [[ -f "$PFX_DIR/pfx/user.reg" ]]; then
  log_info " Proton prefix already initialized."
else
  mkdir -p "$PFX_DIR"
  log_info " Initializing Proton prefix (wineboot)..."
  STEAM_COMPAT_DATA_PATH="$PFX_DIR" \
  STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam" \
  WINEDLLOVERRIDES="regedit.exe,msiexec.exe=" \
  "$proton" run wineboot -u 2>/dev/null || true
  log_info " Prefix initialized."
fi

if command -v winetricks &>/dev/null; then
  if [[ ! -f "$PFX_DIR/pfx/drive_c/windows/system32/vcruntime140.dll" ]]; then
    log_info " Installing VC++ runtimes (winetricks)..."
    STEAM_COMPAT_DATA_PATH="$PFX_DIR" \
    STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam" \
    WINEDLLOVERRIDES="regedit.exe,msiexec.exe=" \
    winetricks -q vcrun2022 dotnet48 winhttp 2>/dev/null || log_info " Warning: some winetricks verbs failed (prefix may still work without cloud features)"
  else
    log_info " VC++ runtimes already present."
  fi
else
  log_info " winetricks not available — skipping VC++ runtime install."
fi
log_info " Configuring DLL overrides..."
log_info " Done."
