# src/install/37-config.sh — Write Fusion360 config
CONFIG_DIR="$F360_CONFIG_DIR"
CONFIG_FILE="$F360_CONFIG_FILE"

GE_PROTON=$(find_proton "$COMPAT_DIR")
FUSION_EXE=$(find "$PFX_DIR" -name Fusion360.exe -type f 2>/dev/null | head -1 || true)
fusion_root=""
if [[ -n "$FUSION_EXE" ]]; then
  fusion_root="$(dirname "$(dirname "$FUSION_EXE")")"
else
  fusion_root="$PFX_DIR/pfx/drive_c/users/steamuser/AppData/Local/Autodesk/webdeploy/production"
fi

declare -a CONFIG_KEYS=(
  PROTON STEAM_COMPAT_DATA_PATH STEAM_COMPAT_CLIENT_INSTALL_PATH
  FUSION_ROOT BROWSER BROWSER_LISTENER CALLBACK_HANDLER CHROME
  FUSION_OVERLAY_KILLER FUSION_WINE_RESTART_SCRIPT
  FUSION_TOOLWINDOW_FIXER
  FUSION_WINE_DPI FUSION_WINE_SCALE_PERCENT FUSION_WINE_DPI_FALLBACK
  FUSION_WINE_SCALE_FALLBACK_PERCENT FUSION_PROTON_USE_WINED3D
  FUSION_PROTON_USE_XALIA FUSION_DXVK_ASYNC FUSION_NO_AT_BRIDGE
  FUSION_FIX_BCP47LANGS FUSION_WEBVIEW_NO_SANDBOX FUSION_WEBVIEW_DISABLE_GPU
  FUSION_USE_INTEL_VK_ICD FUSION_STAGING_WRITECOPY FUSION_HEAP_DELAY_FREE
  FUSION_ENABLE_OVERLAY_KILLER FUSION_ENABLE_TOOLWINDOW_FIXER
  FUSION_OVERLAY_SIZE_TOLERANCE_PERCENT
)

declare -a CONFIG_VALS=(
  "$GE_PROTON" "$PFX_DIR" "$HOME/.local/share/Steam"
  "$fusion_root" "$F360_DATA_DIR/runtime-scripts/fusion-browser.sh"
  "$F360_DATA_DIR/runtime-scripts/fusion-browser-listener.sh"
  "$F360_DATA_DIR/runtime-scripts/fusion-callback-handler.sh"
  "${BROWSER:-/usr/bin/firefox}"
  "$F360_DATA_DIR/runtime-scripts/fusion-gray-overlay-event-killer.sh"
  "$F360_DATA_DIR/runtime-scripts/kill-wine-proton-fusion-nuclear.sh"
  "$PFX_DIR/pfx/drive_c/fusion-toolwindow-fixer.exe"
  "auto" "auto" "144" "150"
  "0" "0" "1" "1" "1" "1" "0" "1" "1" "1" "1" "1" "1" "25"
)


if [[ -f "$CONFIG_FILE" ]]; then
  local wrote=0
  for i in "${!CONFIG_KEYS[@]}"; do
    if ! grep -q "^${CONFIG_KEYS[$i]}=" "$CONFIG_FILE" 2>/dev/null; then
      printf '%s=%s\n' "${CONFIG_KEYS[$i]}" "$(config_quote "${CONFIG_VALS[$i]}")" >> "$CONFIG_FILE"
      log_info "  added missing ${CONFIG_KEYS[$i]}"
      wrote=1
    fi
  done
  if [[ $wrote -eq 0 ]]; then
    log_info "  already present, nothing to add"
  fi
  chmod 600 "$CONFIG_FILE"
  return 0
fi

mkdir -p "$CONFIG_DIR"
for i in "${!CONFIG_KEYS[@]}"; do
  printf '%s=%s\n' "${CONFIG_KEYS[$i]}" "$(config_quote "${CONFIG_VALS[$i]}")"
done > "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"
log_info "  written"
