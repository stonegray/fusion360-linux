# src/install/35-webview2.sh — Install WebView2 into Proton prefix
proton=$(find "$COMPAT_DIR" -name proton -type f 2>/dev/null | head -1 || true)
[[ -n "$proton" ]] || { log_info " GE-Proton not found"; return 1; }

target="$PFX_DIR/pfx/drive_c/Program Files (x86)/Microsoft/EdgeWebView"
if [[ -d "$target" ]]; then
  log_info " already installed"
return 0
fi

bootstrap="/tmp/MicrosoftEdgeWebview2Setup.exe"
if [[ ! -f "$bootstrap" ]]; then
  log_info " downloading..."
  wget -q -O "$bootstrap" "https://go.microsoft.com/fwlink/p/?LinkId=2124703"
fi

log_info " installing (silent)..."
STEAM_COMPAT_DATA_PATH="$PFX_DIR" \
STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam" \
"$proton" run "$bootstrap" /silent /install 2>/dev/null || true

if [[ -d "$target" ]]; then
  log_info " done"
else
  log_info " may not have completed (can re-run)"
fi
