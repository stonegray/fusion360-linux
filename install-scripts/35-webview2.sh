# install-scripts/35-webview2.sh — Install WebView2 into Proton prefix
proton=$(find "$COMPAT_DIR" -name proton -type f 2>/dev/null | head -1 || true)
[[ -n "$proton" ]] || { echo "  [webview2] GE-Proton not found"; exit 1; }

target="$PFX_DIR/pfx/drive_c/Program Files (x86)/Microsoft/EdgeWebView"
if [[ -d "$target" ]]; then
  echo "  [webview2] already installed"
  exit 0
fi

bootstrap="/tmp/MicrosoftEdgeWebview2Setup.exe"
if [[ ! -f "$bootstrap" ]]; then
  echo "  [webview2] downloading..."
  wget -q -O "$bootstrap" "https://go.microsoft.com/fwlink/p/?LinkId=2124703"
fi

echo "  [webview2] installing (silent)..."
STEAM_COMPAT_DATA_PATH="$PFX_DIR" \
STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam" \
"$proton" run "$bootstrap" /silent /install 2>/dev/null || true

if [[ -d "$target" ]]; then
  echo "  [webview2] done"
else
  echo "  [webview2] may not have completed (can re-run)"
fi
