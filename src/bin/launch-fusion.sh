#!/usr/bin/env bash
# launch-fusion.sh: Launch Fusion 360 through Proton with browser bridge support.
set -euo pipefail
# ── Root guard ─────────────────────────────────────────────────────────
if [[ $EUID -eq 0 ]]; then
  echo "ERROR: Do not run launch-fusion.sh as root. Run as a normal user." >&2
  exit 1
fi

# ── Quick health check ────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# Detect runtime directory — supports both installed ($SCRIPT_DIR/runtime-scripts/)
# and dev repo ($SCRIPT_DIR/../runtime/) layouts
if [[ -d "$SCRIPT_DIR/runtime-scripts" ]]; then
  RUNTIME_DIR="$SCRIPT_DIR/runtime-scripts"
else
  RUNTIME_DIR="$(cd "$SCRIPT_DIR/../runtime" 2>/dev/null && pwd)"
fi

if [[ -x "$RUNTIME_DIR/health-check.sh" ]]; then
  if ! "$RUNTIME_DIR/health-check.sh" &>/dev/null; then
    echo "launch-fusion.sh warning: health check failed. Run ./setup-fusion.sh to fix." >&2
  fi
fi

fail() {
  echo "launch-fusion.sh failed: $*" >&2
  exit 1
}

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fusion360-linux"
CONFIG_FILE="$CONFIG_DIR/config"

PROTON="${PROTON:-$HOME/.local/share/Steam/compatibilitytools.d/GE-Proton10-32/proton}"
STEAM_COMPAT_DATA_PATH="${STEAM_COMPAT_DATA_PATH:-$HOME/.fusion360-proton2}"
STEAM_COMPAT_CLIENT_INSTALL_PATH="${STEAM_COMPAT_CLIENT_INSTALL_PATH:-$HOME/.local/share/Steam}"
FUSION_ROOT="${FUSION_ROOT:-$STEAM_COMPAT_DATA_PATH/pfx/drive_c/users/steamuser/AppData/Local/Autodesk/webdeploy/production}"
BROWSER="${BROWSER:-$RUNTIME_DIR/fusion-browser.sh}"
BROWSER_LISTENER="${BROWSER_LISTENER:-$RUNTIME_DIR/fusion-browser-listener.sh}"
CALLBACK_HANDLER="${CALLBACK_HANDLER:-$RUNTIME_DIR/fusion-callback-handler.sh}"
# Auto-detect browser: google-chrome > chromium-browser > chromium > firefox
_detected_chrome=""
for _c in /usr/bin/google-chrome /usr/bin/chromium-browser /usr/bin/chromium /usr/sbin/firefox; do
  [[ -x "$_c" ]] && { _detected_chrome="$_c"; break; }
done
CHROME="${CHROME:-$_detected_chrome}"
unset _detected_chrome _c
FUSION_OVERLAY_KILLER="${FUSION_OVERLAY_KILLER:-$RUNTIME_DIR/fusion-gray-overlay-event-killer.sh}"
FUSION_TOOLWINDOW_FIXER="${FUSION_TOOLWINDOW_FIXER:-${STEAM_COMPAT_DATA_PATH:-$HOME/.fusion360-proton2}/pfx/drive_c/fusion-toolwindow-fixer.exe}"
FUSION_WINE_RESTART_SCRIPT="${FUSION_WINE_RESTART_SCRIPT:-$RUNTIME_DIR/kill-wine-proton-fusion-nuclear.sh}"

FUSION_WINE_DPI="${FUSION_WINE_DPI:-auto}"
FUSION_WINE_SCALE_PERCENT="${FUSION_WINE_SCALE_PERCENT:-auto}"
FUSION_WINE_DPI_FALLBACK="${FUSION_WINE_DPI_FALLBACK:-144}"
FUSION_WINE_SCALE_FALLBACK_PERCENT="${FUSION_WINE_SCALE_FALLBACK_PERCENT:-150}"
FUSION_DPI_LOG_FILE="/tmp/fusion360-dpi.log"

FUSION_PROTON_USE_WINED3D="${FUSION_PROTON_USE_WINED3D:-0}"
FUSION_PROTON_USE_XALIA="${FUSION_PROTON_USE_XALIA:-0}"
FUSION_DXVK_ASYNC="${FUSION_DXVK_ASYNC:-1}"
FUSION_NO_AT_BRIDGE="${FUSION_NO_AT_BRIDGE:-1}"
FUSION_FIX_BCP47LANGS="${FUSION_FIX_BCP47LANGS:-1}"
FUSION_WEBVIEW_NO_SANDBOX="${FUSION_WEBVIEW_NO_SANDBOX:-1}"
FUSION_WEBVIEW_DISABLE_GPU="${FUSION_WEBVIEW_DISABLE_GPU:-0}"
FUSION_USE_INTEL_VK_ICD="${FUSION_USE_INTEL_VK_ICD:-1}"
FUSION_ENABLE_OVERLAY_KILLER="${FUSION_ENABLE_OVERLAY_KILLER:-1}"
FUSION_ENABLE_TOOLWINDOW_FIXER="${FUSION_ENABLE_TOOLWINDOW_FIXER:-1}"
FUSION_OVERLAY_SIZE_TOLERANCE_PERCENT="${FUSION_OVERLAY_SIZE_TOLERANCE_PERCENT:-25}"

BRIDGE_BROWSER_REQUEST_DIR="/tmp/fusion360-browser-requests"
BRIDGE_BROWSER_PROCESSED_DIR="/tmp/fusion360-browser-processed"
BRIDGE_CALLBACK_REQUEST_DIR="/tmp/fusion360-callback-requests"
BRIDGE_CALLBACK_PROCESSED_DIR="/tmp/fusion360-callback-processed"
BRIDGE_LISTENER_PID=""
OVERLAY_KILLER_PID=""

source "$RUNTIME_DIR/launcher-functions.sh"
load_config

if [[ "${1:-}" == "--config" || "${1:-}" == "--configure" ]]; then
  configure_with_file_browsers hold || exit 1
  exit 0
fi

missing_selection=0
[[ -x "$PROTON" ]] || missing_selection=1
[[ -x "$BROWSER" ]] || missing_selection=1
[[ -x "$BROWSER_LISTENER" ]] || missing_selection=1
[[ -x "$CALLBACK_HANDLER" ]] || missing_selection=1
[[ -x "$CHROME" ]] || missing_selection=1
[[ -d "$FUSION_ROOT" ]] || missing_selection=1
if is_enabled "$FUSION_ENABLE_OVERLAY_KILLER"; then
  [[ -x "$FUSION_OVERLAY_KILLER" ]] || missing_selection=1
fi

# Silent config: if config is incomplete, run Python hidden to save defaults
if [[ $missing_selection -eq 1 ]]; then
  if [[ -n "${DISPLAY:-}" && -z "${FUSION_SKIP_UI:-}" ]]; then
    configure_with_file_browsers silent || exit 1
  fi
elif [[ -z "${FUSION_SKIP_UI:-}" ]]; then
  # Config complete, skip UI entirely
  :
fi

apply_launch_environment

[[ -x "$PROTON" ]] || fail "Proton was not found or is not executable: $PROTON. Run $0 --configure to select it."
[[ -x "$BROWSER" ]] || fail "Browser bridge was not found or is not executable: $BROWSER. Run $0 --configure to select it."
[[ -x "$BROWSER_LISTENER" ]] || fail "Browser listener was not found or is not executable: $BROWSER_LISTENER"
[[ -x "$CALLBACK_HANDLER" ]] || fail "Callback handler was not found or is not executable: $CALLBACK_HANDLER"
[[ -x "$CHROME" ]] || fail "Chrome was not found or is not executable: $CHROME. Run $0 --configure to select it."
[[ -d "$FUSION_ROOT" ]] || fail "Fusion production directory was not found: $FUSION_ROOT. Run $0 --configure to select it."

FUSION_EXE="$(find "$FUSION_ROOT" -maxdepth 2 -name Fusion360.exe -print | sort | tail -n 1)"
[[ -n "$FUSION_EXE" ]] || fail "Fusion360.exe was not found under $FUSION_ROOT"

FUSION_DIR="$(dirname "$FUSION_EXE")"
PRODUCTION_CONFIG="$FUSION_DIR/Applications/Fusion/Fusion360App/ApplicationOptions.production.json"
SERVER_CONFIG="$FUSION_DIR/Fusion 360.server.config"

if [[ -f "$PRODUCTION_CONFIG" ]]; then
  cp "$PRODUCTION_CONFIG" "$SERVER_CONFIG"
else
  echo "launch-fusion.sh warning: production config was not found: $PRODUCTION_CONFIG" >&2
fi

# Convert file arguments to Wine paths for Proton
FUSION_ARGS=()
if [[ $# -gt 0 ]] && [[ "${1:0:1}" != "-" ]]; then
  for arg in "$@"; do
    if [[ -f "$arg" || -d "$arg" ]]; then
      FUSION_ARGS+=("Z:$(realpath "$arg")")
    else
      FUSION_ARGS+=("$arg")
    fi
  done
fi

trap cleanup EXIT INT TERM

apply_fusion_wine_dpi
install_callback_protocol_handlers
register_wine_browser_bridge
start_browser_listener
start_overlay_killer
start_toolwindow_fixer

if (( ${#FUSION_ARGS[@]} > 0 )); then
  "$PROTON" run "$FUSION_EXE" "${FUSION_ARGS[@]}"
else
  "$PROTON" run "$FUSION_EXE" "$@"
fi
fusion_status=$?

[[ $fusion_status -eq 0 ]] || fail "Fusion exited or crashed with status $fusion_status"
exit 0