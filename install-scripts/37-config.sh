# install-scripts/37-config.sh — Write Fusion360 config
CONFIG_DIR="$F360_CONFIG_DIR"
CONFIG_FILE="$F360_CONFIG_FILE"

if [[ -f "$CONFIG_FILE" ]]; then
  echo "  [config]  already present"
return 0
fi

mkdir -p "$CONFIG_DIR"

# Detect paths
GE_PROTON=$(find "$COMPAT_DIR" -name proton -type f 2>/dev/null | head -1 || true)
FUSION_EXE=$(find "$PFX_DIR" -name Fusion360.exe -type f 2>/dev/null | head -1 || true)
BROWSER=$(command -v google-chrome chromium-browser chromium firefox 2>/dev/null | head -1 || true)

local fusion_root=""
if [[ -n "$FUSION_EXE" ]]; then
  fusion_root="$(dirname "$(dirname "$FUSION_EXE")")"
else
  fusion_root="$PFX_DIR/pfx/drive_c/users/steamuser/AppData/Local/Autodesk/webdeploy/production"
fi

cat > "$CONFIG_FILE" <<EOF
PROTON=$GE_PROTON
STEAM_COMPAT_DATA_PATH=$HOME/.fusion360-proton2
STEAM_COMPAT_CLIENT_INSTALL_PATH=$HOME/.local/share/Steam
FUSION_ROOT=$fusion_root
BROWSER=$SCRIPT_DIR/runtime-scripts/fusion-browser.sh
BROWSER_LISTENER=$SCRIPT_DIR/runtime-scripts/fusion-browser-listener.sh
CALLBACK_HANDLER=$SCRIPT_DIR/runtime-scripts/fusion-callback-handler.sh
CHROME=${BROWSER:-/usr/bin/firefox}
FUSION_OVERLAY_KILLER=$SCRIPT_DIR/runtime-scripts/fusion-gray-overlay-event-killer.sh
FUSION_WINE_RESTART_SCRIPT=$SCRIPT_DIR/runtime-scripts/kill-wine-proton-fusion-nuclear.sh
FUSION_WINE_DPI=auto
FUSION_WINE_SCALE_PERCENT=auto
FUSION_WINE_DPI_FALLBACK=144
FUSION_WINE_SCALE_FALLBACK_PERCENT=150
FUSION_PROTON_USE_WINED3D=0
FUSION_PROTON_USE_XALIA=0
FUSION_DXVK_ASYNC=1
FUSION_NO_AT_BRIDGE=1
FUSION_FIX_BCP47LANGS=1
FUSION_WEBVIEW_NO_SANDBOX=1
FUSION_WEBVIEW_DISABLE_GPU=0
FUSION_USE_INTEL_VK_ICD=1
FUSION_ENABLE_OVERLAY_KILLER=1
FUSION_OVERLAY_SIZE_TOLERANCE_PERCENT=25
EOF
echo "  [config]  written"
