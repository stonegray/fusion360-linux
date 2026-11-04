#!/usr/bin/env bash
# fusion-browser-listener.sh: Fusion 360 browser bridge Linux-side listener.
set -euo pipefail

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/fusion360-linux/config"

BROWSER_REQUEST_DIR="/tmp/fusion360-browser-requests"
BROWSER_PROCESSED_DIR="/tmp/fusion360-browser-processed"
CALLBACK_REQUEST_DIR="/tmp/fusion360-callback-requests"
CALLBACK_PROCESSED_DIR="/tmp/fusion360-callback-processed"
LOG_FILE="/tmp/fusion-browser-listener.log"

if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
fi

mkdir -p "$BROWSER_REQUEST_DIR"
mkdir -p "$BROWSER_PROCESSED_DIR"
mkdir -p "$CALLBACK_REQUEST_DIR"
mkdir -p "$CALLBACK_PROCESSED_DIR"

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

# Environment for browser launches.
#
# This used to run browsers under `env -i` with a hand-picked list of
# variables. That breaks the normal hand-off to an already-running browser:
# the new process cannot find the running instance's profile (fastlane /
# D-Bus / MOZ_* state are all stripped), so it exits 0 without opening
# anything, and the listener records it as success.
#
# The desktop-default handler is invoked with the caller's environment as-is.
# Only proven-missing values are filled in, never blanked. Set
# FUSION_BROWSER_STRICT_ENV=1 to get the old scrubbed behaviour back.
_browser_env() {
  local uid; uid="$(id -u)"
  local xauth="${XAUTHORITY:-}"
  if [[ -z "$xauth" || ! -f "$xauth" ]]; then
    local cand
    for cand in "$XDG_RUNTIME_DIR"/xauth_* "/run/user/$uid"/xauth_* "$HOME/.Xauthority"; do
      [[ -f "$cand" ]] && { xauth="$cand"; break; }
    done
  fi
  local dbus="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$uid/bus}"

  printf "HOME=%s\n" "$HOME"
  printf "USER=%s\n" "${USER:-$(id -un)}"
  printf "DISPLAY=%s\n" "${DISPLAY:-:0}"
  printf "WAYLAND_DISPLAY=%s\n" "${WAYLAND_DISPLAY:-}"
  printf "XAUTHORITY=%s\n" "$xauth"
  printf "DBUS_SESSION_BUS_ADDRESS=%s\n" "$dbus"
  printf "XDG_CURRENT_DESKTOP=%s\n" "${XDG_CURRENT_DESKTOP:-}"
  printf "XDG_SESSION_TYPE=%s\n" "${XDG_SESSION_TYPE:-}"
  printf "XDG_RUNTIME_DIR=%s\n" "${XDG_RUNTIME_DIR:-/run/user/$uid}"
  printf "LANG=%s\n" "${LANG:-en_US.UTF-8}"
  printf "PATH=%s\n" "${PATH:-/usr/local/bin:/usr/bin:/bin}"
}

# Launch one candidate. Returns 0 only when the attempt plausibly worked.
_try_open() {
  local label="$1" bin="$2" url="$3"
  {
    echo "--- attempt: $label ---"
    echo "bin=$bin"
  } >> "$LOG_FILE" 2>&1

  local rc=0
  if [[ -n "${FUSION_BROWSER_STRICT_ENV:-}" ]]; then
    env -i $(_browser_env) "$bin" "$url" >> "$LOG_FILE" 2>&1 &
  else
    "$bin" "$url" >> "$LOG_FILE" 2>&1 &
  fi
  local pid=$!

  # A browser handing the URL to an already-running instance exits quickly.
  # Give it time to do so; a fresh launch stays up and is equally fine.
  local waited=0
  while (( waited < 16 )) && kill -0 "$pid" 2>/dev/null; do
    sleep 0.5
    waited=$((waited + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    log_message "  $label OK (pid=$pid, still running)"
    return 0
  fi
  wait "$pid" 2>/dev/null; rc=$?
  if [[ $rc -eq 0 ]]; then
    log_message "  $label OK (exit 0)"
    return 0
  fi
  log_message "  $label FAILED (exit $rc)"
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

  # Fallback chain, most-preferred first.
  #
  # xdg-open leads deliberately: it asks the desktop which browser is
  # registered for http(s), so the URL lands in the user's *default* browser
  # with its real environment, D-Bus session and profile. Launching a
  # browser binary directly is the fragile path — a scrubbed environment can
  # make it fail to reach a running instance (or fail outright) and still
  # exit 0.
  # 1 — Desktop default handler
  if command -v xdg-open &>/dev/null; then
    _try_open "xdg-open" "xdg-open" "$url" && { mv "$request_file" "$processed_file"; return 0; }
  fi

  # 2 — KDE Plasma native openers
  if command -v kde-open6 &>/dev/null; then
    _try_open "kde-open6" "kde-open6" "$url" && { mv "$request_file" "$processed_file"; return 0; }
  fi
  if command -v kde-open5 &>/dev/null; then
    _try_open "kde-open5" "kde-open5" "$url" && { mv "$request_file" "$processed_file"; return 0; }
  fi

  # 3 — Explicitly configured browser, if the user set CHROME / FUSION_CHROME
  if [[ -n "${CHROME:-}" ]] && [[ -x "$CHROME" ]]; then
    _try_open "CHROME" "$CHROME" "$url" && { mv "$request_file" "$processed_file"; return 0; }
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
  export WINEDLLOVERRIDES="bcp47langs=;icuuc,icuin,icudt=n,b"
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