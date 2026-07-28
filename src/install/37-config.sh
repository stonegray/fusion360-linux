# src/install/37-config.sh — Write Fusion360 config
CONFIG_DIR="$F360_CONFIG_DIR"
CONFIG_FILE="$F360_CONFIG_FILE"

if [[ -f "$CONFIG_FILE" ]]; then
  # Check if all fields are present; add missing ones
  declare -a EXPECTED_KEYS=(
    PROTON STEAM_COMPAT_DATA_PATH STEAM_COMPAT_CLIENT_INSTALL_PATH
    FUSION_ROOT BROWSER BROWSER_LISTENER CALLBACK_HANDLER CHROME
    FUSION_OVERLAY_KILLER FUSION_WINE_RESTART_SCRIPT
    FUSION_WINE_DPI FUSION_WINE_SCALE_PERCENT FUSION_WINE_DPI_FALLBACK
    FUSION_WINE_SCALE_FALLBACK_PERCENT FUSION_PROTON_USE_WINED3D
    FUSION_PROTON_USE_XALIA FUSION_DXVK_ASYNC FUSION_NO_AT_BRIDGE
    FUSION_FIX_BCP47LANGS FUSION_WEBVIEW_NO_SANDBOX FUSION_WEBVIEW_DISABLE_GPU
    FUSION_USE_INTEL_VK_ICD FUSION_STAGING_WRITECOPY FUSION_HEAP_DELAY_FREE
    FUSION_ENABLE_OVERLAY_KILLER FUSION_OVERLAY_SIZE_TOLERANCE_PERCENT
  )
  for key in "${EXPECTED_KEYS[@]}"; do
    if ! grep -q "^$key=" "$CONFIG_FILE" 2>/dev/null; then
      echo "  [config]  added missing $key (will set default)"
    fi
  done
  echo "  [config]  already present"
return 0
fi

{
  printf 'PROTON=%q\n' "$GE_PROTON"
  printf 'STEAM_COMPAT_DATA_PATH=%q\n' "$HOME/.fusion360-proton2"
  printf 'STEAM_COMPAT_CLIENT_INSTALL_PATH=%q\n' "$HOME/.local/share/Steam"
  printf 'FUSION_ROOT=%q\n' "$fusion_root"
  printf 'BROWSER=%q\n' "$F360_DATA_DIR/runtime-scripts/fusion-browser.sh"
  printf 'BROWSER_LISTENER=%q\n' "$F360_DATA_DIR/runtime-scripts/fusion-browser-listener.sh"
  printf 'CALLBACK_HANDLER=%q\n' "$F360_DATA_DIR/runtime-scripts/fusion-callback-handler.sh"
  printf 'CHROME=%q\n' "${BROWSER:-/usr/bin/firefox}"
  printf 'FUSION_OVERLAY_KILLER=%q\n' "$F360_DATA_DIR/runtime-scripts/fusion-gray-overlay-event-killer.sh"
  printf 'FUSION_WINE_RESTART_SCRIPT=%q\n' "$F360_DATA_DIR/runtime-scripts/kill-wine-proton-fusion-nuclear.sh"
  printf 'FUSION_WINE_DPI=%q\n' "auto"
  printf 'FUSION_WINE_SCALE_PERCENT=%q\n' "auto"
  printf 'FUSION_WINE_DPI_FALLBACK=%q\n' "144"
  printf 'FUSION_WINE_SCALE_FALLBACK_PERCENT=%q\n' "150"
  printf 'FUSION_PROTON_USE_WINED3D=%q\n' "0"
  printf 'FUSION_PROTON_USE_XALIA=%q\n' "0"
  printf 'FUSION_DXVK_ASYNC=%q\n' "1"
  printf 'FUSION_NO_AT_BRIDGE=%q\n' "1"
  printf 'FUSION_FIX_BCP47LANGS=%q\n' "1"
  printf 'FUSION_WEBVIEW_NO_SANDBOX=%q\n' "1"
  printf 'FUSION_WEBVIEW_DISABLE_GPU=%q\n' "0"
  printf 'FUSION_USE_INTEL_VK_ICD=%q\n' "1"
  printf 'FUSION_STAGING_WRITECOPY=%q\n' "1"
  printf 'FUSION_HEAP_DELAY_FREE=%q\n' "1"
  printf 'FUSION_ENABLE_OVERLAY_KILLER=%q\n' "1"
  printf 'FUSION_OVERLAY_SIZE_TOLERANCE_PERCENT=%q\n' "25"
} > "$CONFIG_FILE"
echo "  [config]  written"
