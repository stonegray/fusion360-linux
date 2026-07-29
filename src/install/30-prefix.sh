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
  PROTON_NO_SECCOMP=1 \
  WINEDLLOVERRIDES="regedit.exe,msiexec.exe=" \
  "$proton" run wineboot -u 2>/dev/null || true
  log_info " Prefix initialized."
fi

if command -v winetricks &>/dev/null; then
  if [[ ! -f "$PFX_DIR/pfx/drive_c/windows/system32/vcruntime140.dll" ]]; then
    log_info " Installing VC++ runtimes (winetricks)..."
    STEAM_COMPAT_DATA_PATH="$PFX_DIR" \
    STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam" \
    PROTON_NO_SECCOMP=1 \
    WINEDLLOVERRIDES="regedit.exe,msiexec.exe=" \
    winetricks -q vcrun2022 dotnet48 winhttp 2>/dev/null || log_info " Warning: some winetricks verbs failed (prefix may still work without cloud features)"
  else
    log_info " VC++ runtimes already present."
  fi
else
  log_info " winetricks not available — skipping VC++ runtime install."
fi
log_info " Configuring Wine version and AppDefaults..."

# Derive Wine binary from Proton path (proton run doesn't persist reg changes)
local wine_bin
wine_bin="$(dirname "$proton")/files/bin/wine"
if [[ ! -x "$wine_bin" ]]; then
  log_info " Warning: Wine binary not found at $wine_bin — skipping registry config."
else
  WINEPREFIX="$PFX_DIR/pfx" "$wine_bin" reg add "HKCU\\Software\\Wine" /v Version /t REG_SZ /d win10 /f 2>/dev/null || log_info " Warning: could not set global Windows version"
  WINEPREFIX="$PFX_DIR/pfx" "$wine_bin" reg add "HKCU\\Software\\Wine\\AppDefaults\\msedgewebview2.exe" /v Version /t REG_SZ /d win8 /f 2>/dev/null || log_info " Warning: could not set msedgewebview2.exe version override"
  WINEPREFIX="$PFX_DIR/pfx" "$wine_bin" reg add "HKCU\\Software\\Wine\\DllOverrides" /v "adpclientservice.exe" /t REG_SZ /d native /f 2>/dev/null || log_info " Warning: could not set adpclientservice override"
fi
