#!/usr/bin/env bash
# fusion-browser.sh: Fusion 360 browser bridge — writes URL requests
# for the listener to process.  Called by Fusion via the BROWSER env var.
set -euo pipefail

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/fusion360-linux/config"
REQUEST_DIR="${BRIDGE_BROWSER_REQUEST_DIR:-/tmp/fusion360-browser-requests}"
LOG_FILE="${BRIDGE_BROWSER_LOG:-/tmp/fusion-browser-bridge.log}"

if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
fi

mkdir -p "$REQUEST_DIR"
chmod 0700 "$REQUEST_DIR"

log_message() {
  local msg="$*"
  printf "%s\n" "$msg" >> "$LOG_FILE"
}

log_message "============================================================"
log_message "timestamp=$(date -Is)"
log_message "script=$0"
log_message "pid=$$"
log_message "ppid=$PPID"
log_message "pwd=$PWD"
log_message "argc=$#"

argument_index=0
for argument in "$@"; do
  printf 'argv[%d]=%q\n' "$argument_index" "$argument" >> "$LOG_FILE"
  log_message "argv[${argument_index}]_len=${#argument}"
  log_message "argv[${argument_index}]_first200=${argument:0:200}"
  argument_index=$((argument_index + 1))
done

# Classify the URL for easier debugging
for argument in "$@"; do
  case "$argument" in
    *authorize*|*logout*|*token*|*code*)
      log_message "--- AUTH URL DETECTED ---"
      log_message "url_type=auth"
      log_message "url=$argument"
      ;;
    adskidmgr://*|adsk://*)
      log_message "--- CALLBACK URL DETECTED ---"
      log_message "url_type=callback"
      log_message "url=$argument"
      ;;
  esac
done

log_message "--- env dump ---"
log_message "KDE_SESSION_VERSION=${KDE_SESSION_VERSION:-}"
log_message "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-}"
log_message "DISPLAY=${DISPLAY:-}"
log_message "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-}"
log_message "DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-}"
log_message "XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-}"
log_message "XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-}"
log_message "============================================================"

if [[ $# -lt 1 ]]; then
  echo "no url argument received" >> "$LOG_FILE"
  echo "============================================================" >> "$LOG_FILE"
  echo >> "$LOG_FILE"
  exit 0
fi

request_name="$(date +%s.%N).$$"
partial_file="$REQUEST_DIR/$request_name.partial"
request_file="$REQUEST_DIR/$request_name.request"

printf "%s\n" "$1" > "$partial_file"
mv "$partial_file" "$request_file"

{
  echo "wrote_request=$request_file"
  echo "============================================================"
  echo
} >> "$LOG_FILE" 2>&1

exit 0
