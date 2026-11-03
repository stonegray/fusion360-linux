# ── Load share/ modules ──────────────────────────────────────
# Resolve share/ directory relative to this file's location
_share_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../share" 2>/dev/null && pwd)" || true
if [[ -z "$_share_dir" ]]; then
  _share_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../../share" 2>/dev/null && pwd)" || true
fi
if [[ -d "$_share_dir" ]]; then
  source "$_share_dir/load.sh"
fi
unset _share_dir
#
# This file now contains only 3 launcher-context-specific functions that
# don't belong in the general-purpose share/ library:
#
#   configure_with_file_browsers()  — runs the Python config UI
#   show_selection_summary()        — displays launch config summary
#   apply_launch_environment()      — exports env vars for Fusion launch
#
# All reusable logic has been moved to share/*.fn modules loaded above.
#

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
  FUSION_NATIVE_D3DCOMPILER="${FUSION_NATIVE_D3DCOMPILER:-1}" \
  FUSION_ENABLE_REDRAW_HELPER="${FUSION_ENABLE_REDRAW_HELPER:-0}" \
  FUSION_OVERLAY_SIZE_TOLERANCE_PERCENT="$FUSION_OVERLAY_SIZE_TOLERANCE_PERCENT" \
  python3 "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/launcher-config-user-interface.py" "$CONFIG_FILE" "$user_interface_mode"

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
    #
    # Wine compatibility flags:
    # --disable-accelerated-2d-canvas  — 2D canvas on CPU, reduces D3D11 calls
    # --disable-direct-composition    — avoid Wine's broken DirectComposition path
    # --disable-features=VizDisplayCompositor — older compositor, fewer D3D11 draws
    # --disable-gpu-vsync             — remove D3D11 VSync sync overhead
    # --renderer-process-limit=2      — fewer D3D11 devices under DXVK
    webview_arguments+=("--ignore-gpu-blocklist")
    webview_arguments+=("--enable-gpu-rasterization")
    webview_arguments+=("--enable-zero-copy")
    webview_arguments+=("--use-angle=d3d11")
    webview_arguments+=("--disable-accelerated-2d-canvas")
    webview_arguments+=("--disable-direct-composition")
    webview_arguments+=("--disable-features=VizDisplayCompositor")
    webview_arguments+=("--disable-gpu-vsync")
    webview_arguments+=("--renderer-process-limit=2")
  fi
  if is_enabled "$FUSION_WEBVIEW_DISABLE_GPU"; then
    webview_arguments+=("--disable-gpu")
  fi

  if [[ ${#webview_arguments[@]} -gt 0 ]]; then
    export WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS="${webview_arguments[*]}"
  else
    unset WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS
  fi

  # DXVK tuning for UI rendering — reduces swapchain latency and
  # sets optimal shader compiler threads (half of logical cores)
  local dxvk_cfg="dxgi.syncInterval=0"
  dxvk_cfg="${dxvk_cfg};dxvk.tearFree=1"
  dxvk_cfg="${dxvk_cfg};dxgi.numBackBuffers=3"
  dxvk_cfg="${dxvk_cfg};dxvk.numCompilerThreads=$(( $(nproc 2>/dev/null || echo 4) / 2 ))"
  export DXVK_CONFIG="$dxvk_cfg"


  # WINEDLLOVERRIDES: bcp47langs= prevents Autodesk Identity Manager crash;
  # winhttp=b skips IE proxy detection (saves ~10s startup under Wine).
  local dll_overrides="bcp47langs="
  if ! is_enabled "$FUSION_FIX_BCP47LANGS"; then
    dll_overrides=""
  fi
  if is_enabled "${FUSION_FIX_WINHTTP_PROXY:-1}"; then
    dll_overrides="${dll_overrides:+$dll_overrides;}winhttp=b"
  fi
  # ICU 77: Fusion bundles a real icuuc.dll/icuin.dll (ICU 77, needed by the
  # embedded webview/node.exe); Wine's 32KB stub aborts on icu_77 symbols.
  # Prefer the native copies installed in the prefix system32.
  if is_enabled "${FUSION_FIX_ICU77:-1}"; then
    dll_overrides="${dll_overrides:+$dll_overrides;}icuuc,icuin,icudt=n,b"
  fi
  if is_enabled "${FUSION_NATIVE_D3DCOMPILER:-1}"; then
    dll_overrides="${dll_overrides:+$dll_overrides;}d3dcompiler_47=n"
  fi
  # Native file dialogs: route Fusion's Open dialog to kdialog instead of
  # Wine's Win32 widget dialog. Requires the shim installed app-local next to
  # Fusion360.exe (comdlg32 is a KnownDLL, so a plain override cannot reach
  # it — see install_native_dialog_shim).
  if is_enabled "${FUSION_NATIVE_DIALOGS:-1}"; then
    if [[ -f "$(native_dialog_shim_dir)/comdlg32.dll" ]]; then
      dll_overrides="${dll_overrides:+$dll_overrides;}comdlg32=n"
    fi
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
  export BROWSER
  export BROWSER_LISTENER
  export CALLBACK_HANDLER
  export CHROME
  export FUSION_WINE_DPI
  export FUSION_WINE_SCALE_PERCENT
  export FUSION_WINE_DPI_FALLBACK
  export FUSION_WINE_SCALE_FALLBACK_PERCENT
  export FUSION_PROTON_USE_WINED3D
  export FUSION_PROTON_USE_XALIA
  export FUSION_DXVK_ASYNC
  export FUSION_NO_AT_BRIDGE
  export FUSION_FIX_BCP47LANGS
  export FUSION_WEBVIEW_NO_SANDBOX
  export FUSION_WEBVIEW_DISABLE_GPU
  export FUSION_USE_INTEL_VK_ICD
  export FUSION_ENABLE_OVERLAY_KILLER
  export FUSION_OVERLAY_SIZE_TOLERANCE_PERCENT
  export FUSION_ENABLE_TOOLWINDOW_FIXER
  export FUSION_DARK_MODE
  export PROTON_NO_SECCOMP
  export PROTON_USE_WINED3D
  export PROTON_USE_XALIA
  export DXVK_ASYNC
  export STAGING_WRITECOPY
  export PROTON_HEAP_DELAY_FREE
  export WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS
  export STEAM_COMPAT_DATA_PATH
  export STEAM_COMPAT_CLIENT_INSTALL_PATH
  export PROTON
}

REDRAW_HELPER_PID=""

prepare_native_shader_compiler() {
  is_enabled "${FUSION_NATIVE_D3DCOMPILER:-1}" || return 0
  local compiler="$FUSION_DIR/d3dcompiler_v2/d3dcompiler_47.dll"
  local target="$STEAM_COMPAT_DATA_PATH/pfx/drive_c/windows/system32/d3dcompiler_47.dll"
  [[ -f "$compiler" ]] || { echo "Native shader compiler missing: $compiler" >&2; return 1; }
  cmp -s "$compiler" "$target" && return 0

  local backup_dir="$STEAM_COMPAT_DATA_PATH/shader-compiler-backups"
  local backup temporary
  mkdir -p "$backup_dir"
  if [[ -e "$target" ]]; then
    backup="$(mktemp "$backup_dir/d3dcompiler_47-XXXXXX.dll")" || return 1
    cp -pL "$target" "$backup" || return 1
    echo "launch-fusion.sh: previous shader compiler backed up to $backup"
  fi
  temporary="$(mktemp "${target}.XXXXXX")" || return 1
  if ! cp "$compiler" "$temporary" || ! mv -f "$temporary" "$target"; then
    unlink "$temporary" 2>/dev/null || true
    return 1
  fi
  echo "launch-fusion.sh: installed Fusion's native shader compiler"
}

# Directory holding the app-local comdlg32 shim, next to Fusion360.exe.
native_dialog_shim_dir() {
  printf '%s\n' "$FUSION_DIR"
}

# Install the native file-dialog shim app-local and make it loadable.
#
# comdlg32 is a KnownDLL: Wine resolves it from the known-DLL section and
# ignores both the app directory and the system32 copy. So this must (a) drop
# the shim beside Fusion360.exe and (b) remove the KnownDLL entry, otherwise
# WINEDLLOVERRIDES="comdlg32=n" cannot reach it at all (verified: with the
# entry present the override is silently ignored).
prepare_native_dialog_shim() {
  is_enabled "${FUSION_NATIVE_DIALOGS:-1}" || return 0

  local source="$RUNTIME_DIR/../native-dialogs/comdlg32.dll"
  local target
  target="$(native_dialog_shim_dir)/comdlg32.dll"

  [[ -f "$source" ]] || { echo "launch-fusion.sh warning: native dialog shim not found at $source" >&2; return 0; }
  command -v kdialog >/dev/null 2>&1 || { echo "launch-fusion.sh warning: kdialog not installed; keeping Windows file dialogs" >&2; return 0; }

  if ! cmp -s "$source" "$target" 2>/dev/null; then
    local temporary
    temporary="$(mktemp "${target}.XXXXXX")" || return 1
    if cp "$source" "$temporary" && chmod 644 "$temporary" && mv -f "$temporary" "$target"; then
      echo "launch-fusion.sh: installed native file-dialog shim"
    else
      unlink "$temporary" 2>/dev/null || true
      echo "launch-fusion.sh warning: could not install native file-dialog shim" >&2
      return 0
    fi
  fi

  # Drop the KnownDLL entry so the app-local copy is consulted.
  local wine_bin
  wine_bin="$(proton_wine_bin "$PROTON")"
  if [[ -x "$wine_bin" ]]; then
    WINEPREFIX="$STEAM_COMPAT_DATA_PATH/pfx" "$wine_bin" reg delete \
      'HKLM\System\CurrentControlSet\Control\Session Manager\KnownDLLs' \
      /v comdlg32 /f &>/dev/null || true
  fi
}

start_redraw_helper() {
  is_enabled "${FUSION_ENABLE_REDRAW_HELPER:-0}" || return 0
  [[ -n "${DISPLAY:-}" ]] || return 0
  if ! command -v python3 >/dev/null 2>&1 || [[ ! -f "$RUNTIME_DIR/fusion-redraw-helper.py" ]]; then
    echo "launch-fusion.sh warning: redraw helper requires Python 3 and fusion-redraw-helper.py" >&2
    return 0
  fi
  python3 "$RUNTIME_DIR/fusion-redraw-helper.py" \
    --prefix "$STEAM_COMPAT_DATA_PATH/pfx" --parent-pid "$$" &
  REDRAW_HELPER_PID=$!
  echo "launch-fusion.sh: redraw helper started with PID $REDRAW_HELPER_PID"
}
