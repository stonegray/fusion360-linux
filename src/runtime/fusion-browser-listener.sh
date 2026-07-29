#!/usr/bin/env bash
# fusion-browser-listener.sh: Fusion 360 browser bridge Linux-side listener.
set -euo pipefail

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/fusion360-linux/config"

BROWSER_REQUEST_DIR="${BRIDGE_BROWSER_REQUEST_DIR:-/tmp/fusion360-browser-requests}"
BROWSER_PROCESSED_DIR="${BRIDGE_BROWSER_PROCESSED_DIR:-/tmp/fusion360-browser-processed}"
CALLBACK_REQUEST_DIR="${BRIDGE_CALLBACK_REQUEST_DIR:-/tmp/fusion360-callback-requests}"
CALLBACK_PROCESSED_DIR="${BRIDGE_CALLBACK_PROCESSED_DIR:-/tmp/fusion360-callback-processed}"
LOG_FILE="${BRIDGE_LISTENER_LOG:-/tmp/fusion-browser-listener.log}"

if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
fi

mkdir -p "$BROWSER_REQUEST_DIR"
chmod 0700 "$BROWSER_REQUEST_DIR"
mkdir -p "$BROWSER_PROCESSED_DIR"
chmod 0700 "$BROWSER_PROCESSED_DIR"
mkdir -p "$CALLBACK_REQUEST_DIR"
chmod 0700 "$CALLBACK_REQUEST_DIR"
mkdir -p "$CALLBACK_PROCESSED_DIR"
chmod 0700 "$CALLBACK_PROCESSED_DIR"

log_message() {
  printf "%s\n" "$*" >> "$LOG_FILE"
}

find_fusion_executable() {
  find "$FUSION_ROOT" -maxdepth 2 -name Fusion360.exe -print 2>/dev/null | sort | tail -n 1
}

find_identity_manager_executable() {
  local fusion_executable
  local fusion_directory
  local identity_manager_executable

  fusion_executable="$(find_fusion_executable)"
  [[ -n "$fusion_executable" ]] || return 1

  fusion_directory="$(dirname "$fusion_executable")"

  identity_manager_executable="$(find "$fusion_directory" -maxdepth 4 -iname "AdskIdentityManager.exe" -print 2>/dev/null | sort | head -n 1)"

  if [[ -z "$identity_manager_executable" ]]; then
    identity_manager_executable="$(find "$STEAM_COMPAT_DATA_PATH/pfx/drive_c" -iname "AdskIdentityManager.exe" -print 2>/dev/null | sort | head -n 1)"
  fi

  [[ -n "$identity_manager_executable" ]] || return 1
  printf "%s" "$identity_manager_executable"
}

# Build a clean environment for browser launches — preserves only what
# browsers actually need under Wayland/X11, strips the rest.
_browser_env() {
  printf "HOME=%s\n" "$HOME"
  printf "USER=%s\n" "${USER:-$(id -un)}"
  printf "DISPLAY=%s\n" "${DISPLAY:-:0}"
  printf "WAYLAND_DISPLAY=%s\n" "${WAYLAND_DISPLAY:-}"
  printf "XAUTHORITY=%s\n" "${XAUTHORITY:-$HOME/.Xauthority}"
  printf "DBUS_SESSION_BUS_ADDRESS=%s\n" "${DBUS_SESSION_BUS_ADDRESS:-}"
  printf "XDG_CURRENT_DESKTOP=%s\n" "${XDG_CURRENT_DESKTOP:-}"
  printf "XDG_SESSION_TYPE=%s\n" "${XDG_SESSION_TYPE:-}"
  printf "XDG_RUNTIME_DIR=%s\n" "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  printf "LANG=%s\n" "${LANG:-en_US.UTF-8}"
  printf "PATH=%s\n" "/usr/local/bin:/usr/bin:/bin"
  printf "LIBGL_ALWAYS_SOFTWARE=%s\n" "${LIBGL_ALWAYS_SOFTWARE:-}"
}

_try_open() {
  local label="$1" bin="$2" url="$3"
  {
    echo "--- attempt: $label ---"
    echo "bin=$bin"
  } >> "$LOG_FILE" 2>&1
  env -i $(_browser_env) "$bin" "$url" >> "$LOG_FILE" 2>&1 &
  local pid=$!
  disown 2>/dev/null || true
  sleep 0.5
  if kill -0 "$pid" 2>/dev/null; then
    log_message "  $label OK (pid=$pid)"
    return 0
  fi
  wait "$pid" 2>/dev/null || true
  log_message "  $label FAILED"
  return 1
}

open_browser_url() {
  local request_file="$1"
  local url
  local processed_file

  url="$(cat "$request_file")"
  processed_file="$BROWSER_PROCESSED_DIR/$(basename "$request_file")"

  {
    echo "============================================================"
    echo "timestamp=$(date -Is)"
    echo "type=browser"
    echo "request_file=$request_file"
    echo "url_len=${#url}"
    printf 'url=%q\n' "$url"
    echo "url_first300=${url:0:300}"
    echo "url_last300=${url: -300}"
  } >> "$LOG_FILE" 2>&1

  cd "$HOME" || { log_message "ERROR: cd $HOME failed"; mv "$request_file" "$processed_file"; return 1; }

  # Stratified fallback chain — each attempt must stay alive >0.5s
  # 1 — Configured CHROME (fastest path)
  if [[ -n "${CHROME:-}" ]] && [[ -x "$CHROME" ]]; then
    _try_open "CHROME" "$CHROME" "$url" && { mv "$request_file" "$processed_file"; return 0; }
  fi

  # 2 — KDE Plasma native openers (most reliable on KDE)
  # 2a — kde-open6 (KDE Plasma 6)
  if command -v kde-open6 &>/dev/null; then
    _try_open "kde-open6" "kde-open6" "$url" && { mv "$request_file" "$processed_file"; return 0; }
  fi
  # 2b — kde-open5 (KDE Plasma 5, or compat shim)
  if command -v kde-open5 &>/dev/null; then
    _try_open "kde-open5" "kde-open5" "$url" && { mv "$request_file" "$processed_file"; return 0; }
  fi

  # 3 — xdg-open (last resort on KDE, broken under Wayland; universal elsewhere)
  if command -v xdg-open &>/dev/null; then
    _try_open "xdg-open" "xdg-open" "$url" && { mv "$request_file" "$processed_file"; return 0; }
  fi

  # 4 — Known browser binaries (last resort)
  local known=( google-chrome google-chrome-stable chromium-browser chromium firefox firefox-esr )
  local browser
  for browser in "${known[@]}"; do
    local path; path="$(command -v "$browser" 2>/dev/null || true)"
    [[ -n "$path" ]] && [[ -x "$path" ]] || continue
    _try_open "$browser" "$path" "$url" && { mv "$request_file" "$processed_file"; return 0; }
  done

  # ── All attempts exhausted ───────────────────────────────────────
  {
    echo "--- ALL BROWSER ATTEMPTS FAILED ---"
    echo "url=$url"
    echo "CHROME=${CHROME:-}"
    echo "xdg-open=$(command -v xdg-open 2>/dev/null || echo 'not found')"
    echo "firefox=$(command -v firefox 2>/dev/null || echo 'not found')"
    echo "PATH=$PATH"
  } >> "$LOG_FILE" 2>&1
  log_message "ERROR: no browser could open the URL"
  mv "$request_file" "$processed_file"
  return 1
}
send_callback_to_identity_manager() {
  local request_file="$1"
  local callback_url
  local processed_file
  local identity_manager_executable
  local callback_status

  callback_url="$(cat "$request_file")"
  processed_file="$CALLBACK_PROCESSED_DIR/$(basename "$request_file")"

  {
    echo "============================================================"
    echo "timestamp=$(date -Is)"
    echo "type=callback"
    echo "request_file=$request_file"
    printf 'callback_url=%q\n' "$callback_url"
  } >> "$LOG_FILE" 2>&1

  identity_manager_executable="$(find_identity_manager_executable)"

  if [[ -z "$identity_manager_executable" ]]; then
    echo "identity_manager_executable=NOT_FOUND" >> "$LOG_FILE"
    echo "============================================================" >> "$LOG_FILE"
    echo >> "$LOG_FILE"
    mv "$request_file" "$processed_file"
    return 1
  fi

  {
    echo "identity_manager_executable=$identity_manager_executable"
  } >> "$LOG_FILE" 2>&1

  export PROTON_USE_WINED3D=0
  export PROTON_USE_XALIA=0
  export DXVK_ASYNC=1
  export NO_AT_BRIDGE=1
  export WINEDLLOVERRIDES="bcp47langs="
  export WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS="--no-sandbox"
  export STEAM_COMPAT_DATA_PATH
  export STEAM_COMPAT_CLIENT_INSTALL_PATH

  "$PROTON" run "$identity_manager_executable" "$callback_url" >> "$LOG_FILE" 2>&1
  callback_status=$?

  {
    echo "callback_status=$callback_status"
    echo "processed_file=$processed_file"
    echo "============================================================"
    echo
  } >> "$LOG_FILE" 2>&1

  mv "$request_file" "$processed_file"
}

process_browser_requests() {
  local request_file

  for request_file in "$BROWSER_REQUEST_DIR"/*.request; do
    [[ -e "$request_file" ]] || continue
    open_browser_url "$request_file"
  done
}

process_callback_requests() {
  local request_file

  for request_file in "$CALLBACK_REQUEST_DIR"/*.request; do
    [[ -e "$request_file" ]] || continue
    send_callback_to_identity_manager "$request_file"
  done
}

log_message "fusion-browser-listener.sh started at $(date -Is)"
log_message "watching $BROWSER_REQUEST_DIR"
log_message "watching $CALLBACK_REQUEST_DIR"

while true; do
  process_browser_requests
  process_callback_requests
  sleep 0.2
done