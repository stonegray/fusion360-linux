is_enabled() {
  case "${1:-}" in
    1|yes|true|on|enabled|y|Y|TRUE|True|ON|On)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

load_config() {
  [[ -f "$CONFIG_FILE" ]] || return 0
  source "$CONFIG_FILE"

  local _run_dir
  _run_dir=$(cd "${SCRIPT_DIR:+$SCRIPT_DIR/../runtime}" 2>/dev/null && pwd) || true
  BROWSER_LISTENER="${BROWSER_LISTENER:-${_run_dir:+$_run_dir/fusion-browser-listener.sh}}"
  CALLBACK_HANDLER="${CALLBACK_HANDLER:-${_run_dir:+$_run_dir/fusion-callback-handler.sh}}"
  FUSION_OVERLAY_KILLER="${FUSION_OVERLAY_KILLER:-${_run_dir:+$_run_dir/fusion-gray-overlay-event-killer.sh}}"
  FUSION_WINE_RESTART_SCRIPT="${FUSION_WINE_RESTART_SCRIPT:-${_run_dir:+$_run_dir/kill-wine-proton-fusion-nuclear.sh}}"
  FUSION_TOOLWINDOW_FIXER="${FUSION_TOOLWINDOW_FIXER:-${STEAM_COMPAT_DATA_PATH:-$HOME/.fusion360-proton2}/pfx/drive_c/fusion-toolwindow-fixer.exe}"

  FUSION_WINE_DPI="${FUSION_WINE_DPI:-auto}"
  FUSION_WINE_SCALE_PERCENT="${FUSION_WINE_SCALE_PERCENT:-auto}"
  FUSION_WINE_DPI_FALLBACK="${FUSION_WINE_DPI_FALLBACK:-144}"
  FUSION_WINE_SCALE_FALLBACK_PERCENT="${FUSION_WINE_SCALE_FALLBACK_PERCENT:-150}"

  FUSION_PROTON_USE_WINED3D="${FUSION_PROTON_USE_WINED3D:-0}"
  FUSION_PROTON_USE_XALIA="${FUSION_PROTON_USE_XALIA:-0}"
  FUSION_DXVK_ASYNC="${FUSION_DXVK_ASYNC:-1}"
  FUSION_NO_AT_BRIDGE="${FUSION_NO_AT_BRIDGE:-1}"
  FUSION_FIX_BCP47LANGS="${FUSION_FIX_BCP47LANGS:-1}"
  FUSION_WEBVIEW_NO_SANDBOX="${FUSION_WEBVIEW_NO_SANDBOX:-1}"
  FUSION_WEBVIEW_DISABLE_GPU="${FUSION_WEBVIEW_DISABLE_GPU:-0}"
  FUSION_USE_INTEL_VK_ICD="${FUSION_USE_INTEL_VK_ICD:-1}"
  FUSION_STAGING_WRITECOPY="${FUSION_STAGING_WRITECOPY:-0}"
  FUSION_HEAP_DELAY_FREE="${FUSION_HEAP_DELAY_FREE:-0}"
  FUSION_ENABLE_OVERLAY_KILLER="${FUSION_ENABLE_OVERLAY_KILLER:-1}"
  FUSION_ENABLE_TOOLWINDOW_FIXER="${FUSION_ENABLE_TOOLWINDOW_FIXER:-1}"
}

save_config() {
  mkdir -p "$CONFIG_DIR"

  {
    local keys=(
      PROTON STEAM_COMPAT_DATA_PATH STEAM_COMPAT_CLIENT_INSTALL_PATH
      FUSION_ROOT BROWSER BROWSER_LISTENER CALLBACK_HANDLER CHROME
      FUSION_TOOLWINDOW_FIXER
      FUSION_ENABLE_TOOLWINDOW_FIXER
      FUSION_OVERLAY_KILLER FUSION_WINE_RESTART_SCRIPT
      FUSION_WINE_DPI FUSION_WINE_SCALE_PERCENT FUSION_WINE_DPI_FALLBACK
      FUSION_WINE_SCALE_FALLBACK_PERCENT FUSION_PROTON_USE_WINED3D
      FUSION_PROTON_USE_XALIA FUSION_DXVK_ASYNC FUSION_NO_AT_BRIDGE
      FUSION_FIX_BCP47LANGS FUSION_WEBVIEW_NO_SANDBOX FUSION_WEBVIEW_DISABLE_GPU
      FUSION_USE_INTEL_VK_ICD FUSION_STAGING_WRITECOPY FUSION_HEAP_DELAY_FREE
      FUSION_ENABLE_OVERLAY_KILLER FUSION_OVERLAY_SIZE_TOLERANCE_PERCENT
    )
    for key in "${keys[@]}"; do
      local val
      val=$(printf "%q" "${!key}")
      # bash 5.0+ printf %q outputs $'...' which older bash can't parse
      if [[ "$val" == \$* ]]; then
        # Fall back to single-quote wrapping
        val="'${!key}'"
      fi
      printf '%s=%s\n' "$key" "$val"
    done
  } > "$CONFIG_FILE"
}

# ── Process killing ──────────────────────────────────────────
kill_fusion_processes() {
  local user; user=$(id -u)
  local pids=()
  local pid

  # Method 1: pgrep by cmdline patterns
  for pattern in wineserver wine proton xalia streamer \
    Fusion360 FusionClientDownloader AdskIdentity adexmtsv \
    steam.exe node.exe fusion-gray-overlay; do
    while IFS= read -r pid; do
      pids+=("$pid")
    done < <(pgrep -u "$user" -f "$pattern" 2>/dev/null || true)
  done

  # Method 2: scan /proc/PID/exe for wine/proton binaries
  local exe
  for proc in /proc/[0-9]*/exe; do
    exe=$(readlink "$proc" 2>/dev/null || true)
    [[ -z "$exe" ]] && continue
    if [[ "$exe" == *wine* ]] || [[ "$exe" == *proton* ]]; then
      pid=${proc%/exe}
      pid=${pid#/proc/}
      pids+=("$pid")
    fi
  done

  # Deduplicate
  local unique=()
  for pid in "${pids[@]}"; do
    [[ -z "$pid" ]] && continue
    case " ${unique[*]} " in *" $pid "*) continue ;; esac
    unique+=("$pid")
  done

  if (( ${#unique[@]} == 0 )); then
    return 0
  fi

  log_info " Killing ${#unique[@]} Wine/Proton process(es)..."

  # Graceful TERM first
  for pid in "${unique[@]}"; do
    kill "$pid" 2>/dev/null || true
  done

  sleep 2

  # Hard KILL for survivors
  for pid in "${unique[@]}"; do
    kill -9 "$pid" 2>/dev/null || true
  done

  sleep 1

  # Verify
  local survivors=0
  for proc in /proc/[0-9]*/exe; do
    exe=$(readlink "$proc" 2>/dev/null || true)
    [[ -z "$exe" ]] && continue
    if [[ "$exe" == *wine* ]] || [[ "$exe" == *proton* ]]; then
      pid=${proc%/exe}
      pid=${pid#/proc/}
      log_info "   SURVIVED: PID $pid ($exe)"
      survivors=$((survivors + 1))
    fi
  done

  if (( survivors == 0 )); then
    return 0
  else
    return 1
  fi
}

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

clear_bridge_temp_files() {
  mkdir -p "$BRIDGE_BROWSER_REQUEST_DIR"
  mkdir -p "$BRIDGE_BROWSER_PROCESSED_DIR"
  mkdir -p "$BRIDGE_CALLBACK_REQUEST_DIR"
  mkdir -p "$BRIDGE_CALLBACK_PROCESSED_DIR"

  find "$BRIDGE_BROWSER_REQUEST_DIR" -type f \( -name "*.request" -o -name "*.partial" \) -delete 2>/dev/null || true
  find "$BRIDGE_BROWSER_PROCESSED_DIR" -type f \( -name "*.request" -o -name "*.partial" \) -delete 2>/dev/null || true
  find "$BRIDGE_CALLBACK_REQUEST_DIR" -type f \( -name "*.request" -o -name "*.partial" \) -delete 2>/dev/null || true
  find "$BRIDGE_CALLBACK_PROCESSED_DIR" -type f \( -name "*.request" -o -name "*.partial" \) -delete 2>/dev/null || true
}

read_gsettings_number() {
  local schema_name="$1"
  local key_name="$2"
  local raw_value

  command -v gsettings >/dev/null 2>&1 || return 1

  raw_value="$(gsettings get "$schema_name" "$key_name" 2>/dev/null)" || return 1
  printf "%s\n" "$raw_value" | grep -Eo '[0-9]+([.][0-9]+)?' | tail -n 1
}

read_kde_forced_dpi() {
  # KDE Plasma stores forced font DPI in kdeglobals
  command -v kreadconfig5 >/dev/null 2>&1 || return 1
  local dpi
  dpi="$(kreadconfig5 --file "$HOME/.config/kdeglobals" --group "General" --key "forceFontDPI" 2>/dev/null)" || return 1
  [[ "$dpi" =~ ^[0-9]+$ ]] && [[ "$dpi" -gt 0 ]] || return 1
  printf "%s" "$dpi"
}

# Check all KDE outputs via kscreen-doctor and return the highest scale factor as DPI
read_kde_primary_scale() {
  command -v kscreen-doctor &>/dev/null || return 1
  local scale
  scale=$(kscreen-doctor -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -i 'Scale:' | awk '{print $NF}' | sort -r | head -1)
  [[ -n "$scale" ]] || return 1
  # Only return if actual scaling is active (> 1.0)
  awk -v value="$scale" 'BEGIN { exit !(value > 1.0) }' || return 1
  scale_to_dpi "$scale"
}

# Detect GNOME text scaling factor via gsettings
read_gnome_text_scaling() {
  command -v gsettings &>/dev/null || return 1
  local scale
  scale=$(gsettings get org.gnome.desktop.interface text-scaling-factor 2>/dev/null || true)
  [[ -n "$scale" ]] || return 1
  # GNOME default is 1.0 (no scaling)
  awk -v value="$scale" 'BEGIN { exit !(value > 0 && value != 1) }' || return 1
  scale_to_dpi "$scale"
}

scale_to_dpi() {
  local scale_value="$1"

  awk -v scale_value="$scale_value" 'BEGIN { printf "%d", (96 * scale_value) + 0.5 }'
}

percent_to_dpi() {
  local percent_value="$1"

  awk -v percent_value="$percent_value" 'BEGIN { printf "%d", (96 * percent_value / 100) + 0.5 }'
}

resolve_fusion_wine_dpi() {
  local kde_forced_dpi
  local cinnamon_scaling_factor
  local cinnamon_text_scaling_factor

  if printf "%s\n" "$FUSION_WINE_SCALE_PERCENT" | grep -Eq '^[0-9]+$'; then
    percent_to_dpi "$FUSION_WINE_SCALE_PERCENT"
    return 0
  fi

  if printf "%s\n" "$FUSION_WINE_DPI" | grep -Eq '^[0-9]+$'; then
    printf "%s" "$FUSION_WINE_DPI"
    return 0
  fi

  # KDE Plasma: check forced font DPI
  kde_forced_dpi="$(read_kde_forced_dpi || true)"
  if [[ -n "$kde_forced_dpi" ]]; then
    printf "%s" "$kde_forced_dpi"
    return 0
  fi

  # KDE Plasma: primary monitor scale factor
  local kde_primary_dpi
  kde_primary_dpi="$(read_kde_primary_scale || true)"
  if [[ -n "$kde_primary_dpi" ]] && [[ "$kde_primary_dpi" =~ ^[0-9]+$ ]]; then
    printf "%s" "$kde_primary_dpi"
    return 0
  fi

  # GNOME: text scaling factor
  local gnome_text_dpi
  gnome_text_dpi="$(read_gnome_text_scaling || true)"
  if [[ -n "$gnome_text_dpi" ]] && [[ "$gnome_text_dpi" =~ ^[0-9]+$ ]]; then
    printf "%s" "$gnome_text_dpi"
    return 0
  fi

  # Cinnamon: check text scaling factor
  cinnamon_text_scaling_factor="$(read_gsettings_number org.cinnamon.desktop.interface text-scaling-factor || true)"
  cinnamon_scaling_factor="$(read_gsettings_number org.cinnamon.desktop.interface scaling-factor || true)"

  if [[ -n "$cinnamon_text_scaling_factor" ]]; then
    if awk -v value="$cinnamon_text_scaling_factor" 'BEGIN { exit !(value > 0 && value != 1) }'; then
      scale_to_dpi "$cinnamon_text_scaling_factor"
      return 0
    fi
  fi

  if [[ -n "$cinnamon_scaling_factor" ]]; then
    if awk -v value="$cinnamon_scaling_factor" 'BEGIN { exit !(value > 1) }'; then
      scale_to_dpi "$cinnamon_scaling_factor"
      return 0
    fi
  fi

  # Xft.dpi from xrdb (set by KDE font DPI, GNOME, or .Xresources)
  if command -v xrdb &>/dev/null; then
    local xft_dpi
    xft_dpi=$(xrdb -query 2>/dev/null | grep '^Xft\.dpi:' | awk '{print $2}' || true)
    if [[ -n "$xft_dpi" ]] && [[ "$xft_dpi" =~ ^[0-9]+$ ]] && [[ "$xft_dpi" -gt 0 ]]; then
      printf "%s" "$xft_dpi"
      return 0
    fi
  fi

  if printf "%s\n" "$FUSION_WINE_SCALE_FALLBACK_PERCENT" | grep -Eq '^[0-9]+$'; then
    percent_to_dpi "$FUSION_WINE_SCALE_FALLBACK_PERCENT"
    return 0
  fi

  printf "%s" "$FUSION_WINE_DPI_FALLBACK"
}

apply_fusion_wine_dpi() {
  local dpi_value
  local win8_dpi_scaling

  dpi_value="$(resolve_fusion_wine_dpi)"
  [[ "$dpi_value" =~ ^[0-9]+$ ]] || { echo "warning: invalid DPI value '$dpi_value'" >&2; return 1; }
  [[ "$dpi_value" -eq 96 ]] && win8_dpi_scaling=0 || win8_dpi_scaling=1

  {
    echo "timestamp=$(date -Is)"
    echo "FUSION_WINE_DPI=$FUSION_WINE_DPI"
    echo "FUSION_WINE_SCALE_PERCENT=$FUSION_WINE_SCALE_PERCENT"
    echo "FUSION_WINE_DPI_FALLBACK=$FUSION_WINE_DPI_FALLBACK"
    echo "FUSION_WINE_SCALE_FALLBACK_PERCENT=$FUSION_WINE_SCALE_FALLBACK_PERCENT"
    echo "resolved_dpi=$dpi_value"
    echo "win8_dpi_scaling=$win8_dpi_scaling"
    echo "cinnamon_scaling_factor=$(read_gsettings_number org.cinnamon.desktop.interface scaling-factor || true)"
    echo "cinnamon_text_scaling_factor=$(read_gsettings_number org.cinnamon.desktop.interface text-scaling-factor || true)"
    echo "kde_forced_dpi=$(read_kde_forced_dpi || true)"
  } > "$FUSION_DPI_LOG_FILE"

  local wine_bin
  wine_bin="$(dirname "$PROTON")/files/bin/wine"
  [[ -x "$wine_bin" ]] || { echo "launch-fusion.sh warning: wine binary not found at $wine_bin" >&2; return 1; }

  local pfx="$STEAM_COMPAT_DATA_PATH/pfx"

  WINEPREFIX="$pfx" "$wine_bin" reg add 'HKCU\Software\Wine\Fonts' /v LogPixels /t REG_DWORD /d "$dpi_value" /f >> "$FUSION_DPI_LOG_FILE" 2>&1 || {
    echo "launch-fusion.sh warning: failed to set Wine Fonts LogPixels. See $FUSION_DPI_LOG_FILE" >&2
  }

  WINEPREFIX="$pfx" "$wine_bin" reg add 'HKCU\Control Panel\Desktop' /v LogPixels /t REG_DWORD /d "$dpi_value" /f >> "$FUSION_DPI_LOG_FILE" 2>&1 || {
    echo "launch-fusion.sh warning: failed to set Desktop LogPixels. See $FUSION_DPI_LOG_FILE" >&2
  }

  WINEPREFIX="$pfx" "$wine_bin" reg add 'HKCU\Control Panel\Desktop' /v Win8DpiScaling /t REG_DWORD /d "$win8_dpi_scaling" /f >> "$FUSION_DPI_LOG_FILE" 2>&1 || {
    echo "launch-fusion.sh warning: failed to set Win8DpiScaling. See $FUSION_DPI_LOG_FILE" >&2
  }

  {
    echo
    echo "---- registry check after write ----"
    WINEPREFIX="$pfx" "$wine_bin" reg query 'HKCU\Software\Wine\Fonts' /v LogPixels 2>&1 || true
    WINEPREFIX="$pfx" "$wine_bin" reg query 'HKCU\Control Panel\Desktop' /v LogPixels 2>&1 || true
    WINEPREFIX="$pfx" "$wine_bin" reg query 'HKCU\Control Panel\Desktop' /v Win8DpiScaling 2>&1 || true
  } >> "$FUSION_DPI_LOG_FILE"
}

install_callback_protocol_handlers() {
  local applications_dir
  local desktop_file

  applications_dir="${F360_APPS_DIR:-$HOME/.local/share/applications/fusion360-linux}"
  desktop_file="$applications_dir/fusion360-callback-handler.desktop"

  if [[ -f "$desktop_file" ]] && grep -q "$CALLBACK_HANDLER" "$desktop_file" 2>/dev/null; then
    return 0
  fi

  mkdir -p "$applications_dir"
  cat > "$desktop_file" <<EOF_DESKTOP
[Desktop Entry]
Name=Fusion 360 Autodesk Callback Handler
Exec=$CALLBACK_HANDLER %u
Type=Application
NoDisplay=true
MimeType=x-scheme-handler/adsk;x-scheme-handler/adskidmgr;
EOF_DESKTOP

  xdg-mime default fusion360-callback-handler.desktop x-scheme-handler/adsk 2>/dev/null || true
  xdg-mime default fusion360-callback-handler.desktop x-scheme-handler/adskidmgr 2>/dev/null || true
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$applications_dir" >/dev/null 2>&1 || true
}

register_wine_browser_bridge() {
  local wine_bin
  wine_bin="$(dirname "$PROTON")/files/bin/wine"
  [[ -x "$wine_bin" ]] || { echo "launch-fusion.sh warning: wine binary not found at $wine_bin" >&2; return 1; }
  local pfx="$STEAM_COMPAT_DATA_PATH/pfx"
  WINEPREFIX="$pfx" "$wine_bin" reg add 'HKCU\Software\Wine\WineBrowser' /v Browsers /t REG_SZ /d "$BROWSER" /f >/tmp/fusion360-winebrowser-register.log 2>&1 || {
    echo "launch-fusion.sh warning: failed to register WineBrowser. See /tmp/fusion360-winebrowser-register.log" >&2
  }
}

start_browser_listener() {
  [[ -x "$BROWSER_LISTENER" ]] || fail "Browser listener was not found or is not executable: $BROWSER_LISTENER"

  clear_bridge_temp_files

  "$BROWSER_LISTENER" &
  BRIDGE_LISTENER_PID="$!"

  echo "launch-fusion.sh: browser listener started with PID $BRIDGE_LISTENER_PID"
}

start_overlay_killer() {
  is_enabled "$FUSION_ENABLE_OVERLAY_KILLER" || return 0

  if [[ ! -x "$FUSION_OVERLAY_KILLER" ]]; then
    echo "launch-fusion.sh warning: overlay killer is enabled but not executable: $FUSION_OVERLAY_KILLER" >&2
    return 0
  fi

  FUSION_OVERLAY_SIZE_TOLERANCE_PERCENT="$FUSION_OVERLAY_SIZE_TOLERANCE_PERCENT" "$FUSION_OVERLAY_KILLER" &
  OVERLAY_KILLER_PID="$!"
  echo "launch-fusion.sh: overlay killer started with PID $OVERLAY_KILLER_PID"
}

TOOLWINDOW_FIXER_PID=""

# ── Toolwindow fixer ─────────────────────────────────────────────────
# Background daemon that adds WS_EX_APPWINDOW to Fusion's docked
# toolwindow popups so Wine's X11 driver makes them "managed" instead
# of override-redirect.  Fixes the "always on top" z-order bug.
start_toolwindow_fixer() {
  is_enabled "$FUSION_ENABLE_TOOLWINDOW_FIXER" || return 0

  if [[ ! -x "$FUSION_TOOLWINDOW_FIXER" ]]; then
    echo "launch-fusion.sh warning: toolwindow fixer is enabled but not executable: $FUSION_TOOLWINDOW_FIXER" >&2
    return 0
  fi

  # Find the Wine binary from the GE-Proton installation
  local wine_bin
  wine_bin="$(dirname "$PROTON")/files/bin/wine"
  if [[ ! -x "$wine_bin" ]]; then
    echo "launch-fusion.sh warning: wine binary not found at $wine_bin" >&2
    return 0
  fi

  WINEPREFIX="${STEAM_COMPAT_DATA_PATH:-${PFX_DIR:-$HOME/.fusion360-proton2}}/pfx" \
  "$wine_bin" "$FUSION_TOOLWINDOW_FIXER" &
  TOOLWINDOW_FIXER_PID="$!"

  echo "launch-fusion.sh: toolwindow fixer started with PID $TOOLWINDOW_FIXER_PID"
}

cleanup() {
  if [[ -n "$OVERLAY_KILLER_PID" ]]; then
    if kill -0 "$OVERLAY_KILLER_PID" 2>/dev/null; then
      kill "$OVERLAY_KILLER_PID" 2>/dev/null || true
      wait "$OVERLAY_KILLER_PID" 2>/dev/null || true
    fi
  fi

  if [[ -n "$BRIDGE_LISTENER_PID" ]]; then
    if kill -0 "$BRIDGE_LISTENER_PID" 2>/dev/null; then
      kill "$BRIDGE_LISTENER_PID" 2>/dev/null || true
      wait "$BRIDGE_LISTENER_PID" 2>/dev/null || true
    fi
  fi


  if [[ -n "$TOOLWINDOW_FIXER_PID" ]]; then
    if kill -0 "$TOOLWINDOW_FIXER_PID" 2>/dev/null; then
      kill "$TOOLWINDOW_FIXER_PID" 2>/dev/null || true
      wait "$TOOLWINDOW_FIXER_PID" 2>/dev/null || true
    fi
  fi
  clear_bridge_temp_files
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
  export STEAM_COMPAT_DATA_PATH
  export STEAM_COMPAT_CLIENT_INSTALL_PATH
}
