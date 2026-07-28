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
  local keys=(
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
  local vals=(
    "$GE_PROTON"
    "$HOME/.fusion360-proton2"
    "$HOME/.local/share/Steam"
    "$fusion_root"
    "$F360_DATA_DIR/runtime-scripts/fusion-browser.sh"
    "$F360_DATA_DIR/runtime-scripts/fusion-browser-listener.sh"
    "$F360_DATA_DIR/runtime-scripts/fusion-callback-handler.sh"
    "${BROWSER:-/usr/bin/firefox}"
    "$F360_DATA_DIR/runtime-scripts/fusion-gray-overlay-event-killer.sh"
    "$F360_DATA_DIR/runtime-scripts/kill-wine-proton-fusion-nuclear.sh"
    "auto"
    "auto"
    "144"
    "150"
    "0"
    "0"
    "1"
    "1"
    "1"
    "1"
    "0"
    "1"
    "1"
    "1"
    "1"
    "1"
    "25"
  )
  local i val
  for i in "${!keys[@]}"; do
    val=$(printf '%q' "${vals[$i]}")
    # bash 5.0+ printf %q outputs $'...' which older bash can't parse
    if [[ "$val" == \$* ]]; then
      val="'${vals[$i]}'"
    fi
    printf '%s=%s\n' "${keys[$i]}" "$val"
  done
} > "$CONFIG_FILE"
echo "  [config]  written"
