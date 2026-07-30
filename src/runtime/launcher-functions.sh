# ── Load share/ modules ──────────────────────────────────────
# Resolve share/ directory relative to this file's location
_share_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../share" 2>/dev/null && pwd)" || true
if [[ -z "$_share_dir" ]]; then
  _share_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../share" 2>/dev/null && pwd)"
fi
if [[ -d "$_share_dir" ]]; then
  source "$_share_dir/load.sh"
fi
unset _share_dir

configure_with_file_browsers() {
  local user_interface_mode="${1:-hold}"

  command -v python3 >/dev/null 2>&1 || fail "python3 is required for the setup window."

  PROTON="$PROTON" \
  STEAM_COMPAT_DATA_PATH="$STEAM_COMPAT_DATA_PATH" \
  STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM_COMPAT_CLIENT_INSTALL_PATH" \
  FUSION_ROOT="$FUSION_ROOT" \
  BROWSER="$BROWSER" \
  BROWSER_LISTENER="$BROWSER_LISTENER" \
  CALLBACK_HANDLER="$CALLBACK_HANDLER" \
  CHROME="$CHROME" \
  FUSION_OVERLAY_KILLER="$FUSION_OVERLAY_KILLER" \
  FUSION_WINE_RESTART_SCRIPT="$FUSION_WINE_RESTART_SCRIPT" \
  FUSION_WINE_DPI="$FUSION_WINE_DPI" \
  FUSION_WINE_SCALE_PERCENT="$FUSION_WINE_SCALE_PERCENT" \
  FUSION_WINE_DPI_FALLBACK="$FUSION_WINE_DPI_FALLBACK" \
  FUSION_WINE_SCALE_FALLBACK_PERCENT="$FUSION_WINE_SCALE_FALLBACK_PERCENT" \
  FUSION_PROTON_USE_WINED3D="$FUSION_PROTON_USE_WINED3D" \
  FUSION_PROTON_USE_XALIA="$FUSION_PROTON_USE_XALIA" \
  FUSION_DXVK_ASYNC="$FUSION_DXVK_ASYNC" \
  FUSION_NO_AT_BRIDGE="$FUSION_NO_AT_BRIDGE" \
  FUSION_FIX_BCP47LANGS="$FUSION_FIX_BCP47LANGS" \
  FUSION_WEBVIEW_NO_SANDBOX="$FUSION_WEBVIEW_NO_SANDBOX" \
  FUSION_WEBVIEW_DISABLE_GPU="$FUSION_WEBVIEW_DISABLE_GPU" \
  FUSION_USE_INTEL_VK_ICD="$FUSION_USE_INTEL_VK_ICD" \
  FUSION_ENABLE_OVERLAY_KILLER="$FUSION_ENABLE_OVERLAY_KILLER" \
  FUSION_OVERLAY_SIZE_TOLERANCE_PERCENT="$FUSION_OVERLAY_SIZE_TOLERANCE_PERCENT" \
  python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/launcher-config-user-interface.py" "$CONFIG_FILE" "$user_interface_mode"

  local config_user_interface_status=$?
  [[ $config_user_interface_status -eq 0 ]] || return "$config_user_interface_status"

  load_config
}

show_selection_summary() {
  cat <<EOF_SUMMARY
Fusion 360 launch selections:
  Proton executable: $PROTON
  Proton prefix: $STEAM_COMPAT_DATA_PATH
  Steam install directory: $STEAM_COMPAT_CLIENT_INSTALL_PATH
  Fusion production directory: $FUSION_ROOT
  Browser bridge script: $BROWSER
  Browser listener script: $BROWSER_LISTENER
  Callback handler script: $CALLBACK_HANDLER
  Chrome executable: $CHROME
  Wine scale percent: $FUSION_WINE_SCALE_PERCENT
  Wine scale fallback percent: $FUSION_WINE_SCALE_FALLBACK_PERCENT
  Wine DPI legacy value: $FUSION_WINE_DPI
  Wine DPI fallback: $FUSION_WINE_DPI_FALLBACK
  Grey overlay killer: $FUSION_OVERLAY_KILLER
  Grey overlay killer enabled: $FUSION_ENABLE_OVERLAY_KILLER
  Wine restart script: $FUSION_WINE_RESTART_SCRIPT
EOF_SUMMARY
}

apply_launch_environment() {
  export PROTON_USE_WINED3D="$FUSION_PROTON_USE_WINED3D"
  export PROTON_USE_XALIA="$FUSION_PROTON_USE_XALIA"


  # Disable seccomp for all Proton child processes — prevents SIGSYS
  # kill of msedgewebview2.exe on Mojo named platform channel pipe.
  export PROTON_NO_SECCOMP=1
  if is_enabled "$FUSION_DXVK_ASYNC"; then
    export DXVK_ASYNC=1
  else
    unset DXVK_ASYNC
  fi

  if is_enabled "$FUSION_STAGING_WRITECOPY"; then
    export STAGING_WRITECOPY=1
  else
    unset STAGING_WRITECOPY
  fi

  if is_enabled "$FUSION_HEAP_DELAY_FREE"; then
    export PROTON_HEAP_DELAY_FREE=1
  else
    unset PROTON_HEAP_DELAY_FREE
  fi
  local webview_arguments=()
  if is_enabled "$FUSION_WEBVIEW_NO_SANDBOX"; then
    webview_arguments+=("--no-sandbox")
  fi
  if ! is_enabled "$FUSION_WEBVIEW_DISABLE_GPU"; then
    # GPU acceleration flags for WebView2 — without these, the Edge
    # renderer may fall back to software rasterization under Wine,
    # causing slow UI panel rendering.  --use-angle=d3d11 forces the
    # D3D11 backend through ANGLE, which DXVK then translates to
    # Vulkan (same fast path as the 3D viewport).
    webview_arguments+=("--ignore-gpu-blocklist")
    webview_arguments+=("--enable-gpu-rasterization")
    webview_arguments+=("--enable-zero-copy")
    webview_arguments+=("--use-angle=d3d11")
  fi
  if is_enabled "$FUSION_WEBVIEW_DISABLE_GPU"; then
    webview_arguments+=("--disable-gpu")
    webview_arguments+=("--disable-features=VizDisplayCompositor")
  fi

  if [[ ${#webview_arguments[@]} -gt 0 ]]; then
    export WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS="${webview_arguments[*]}"
  else
    unset WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS
  fi

  # DXVK tuning for UI rendering — reduces swapchain latency and
  # sets optimal shader compiler threads (half of logical cores)
  local dxvk_cfg="dxgi.syncInterval=0"
  dxvk_cfg="${dxvk_cfg},dxvk.tearFree=1"
  dxvk_cfg="${dxvk_cfg},dxgi.numBackBuffers=3"
  dxvk_cfg="${dxvk_cfg},dxvk.numCompilerThreads=$(( $(nproc 2>/dev/null || echo 4) / 2 ))"
  export DXVK_CONFIG="$dxvk_cfg"


  # WINEDLLOVERRIDES: bcp47langs= prevents Autodesk Identity Manager crash;
  # winhttp=b skips IE proxy detection (saves ~10s startup under Wine).
  local dll_overrides="bcp47langs="
  if ! is_enabled "$FUSION_FIX_BCP47LANGS"; then
    dll_overrides=""
  fi
  if is_enabled "${FUSION_FIX_WINHTTP_PROXY:-1}"; then
    dll_overrides="${dll_overrides:+$dll_overrides,}winhttp=b"
  fi
  if [[ -n "$dll_overrides" ]]; then
    export WINEDLLOVERRIDES="$dll_overrides"
  else
    unset WINEDLLOVERRIDES
  fi

  if is_enabled "$FUSION_USE_INTEL_VK_ICD"; then
    # Ubuntu/KDE Neon: intel_icd.json (64-bit). Fedora: intel_icd.x86_64.json + .i686.json
    if [[ -f /usr/share/vulkan/icd.d/intel_icd.x86_64.json && -f /usr/share/vulkan/icd.d/intel_icd.i686.json ]]; then
      export VK_ICD_FILENAMES="/usr/share/vulkan/icd.d/intel_icd.x86_64.json:/usr/share/vulkan/icd.d/intel_icd.i686.json"
    elif [[ -f /usr/share/vulkan/icd.d/intel_icd.json ]]; then
      export VK_ICD_FILENAMES="/usr/share/vulkan/icd.d/intel_icd.json"
      # 32-bit ICD may be at /usr/lib/i386-linux-gnu/GL/vulkan/icd.d/intel_icd.i686.json if installed
    else
      echo "launch-fusion.sh warning: Intel Vulkan ICD flag is enabled, but no Intel ICD file was found." >&2
    fi
  fi

  export BROWSER="${BROWSER:-xdg-open}"
  export BROWSER_LISTENER
  export CALLBACK_HANDLER
  export CHROME
  export FUSION_WINE_DPI
  export FUSION_WINE_SCALE_PERCENT
  export FUSION_WINE_DPI_FALLBACK
  export FUSION_WINE_SCALE_FALLBACK_PERCENT
  export STEAM_COMPAT_DATA_PATH
  export STEAM_COMPAT_CLIENT_INSTALL_PATH
}
