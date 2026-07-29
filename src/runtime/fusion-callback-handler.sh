#!/usr/bin/env bash
# fusion-callback-handler.sh: Fusion 360 Autodesk callback request writer.
set -euo pipefail

CALLBACK_DIR="/tmp/fusion360-callback-requests"
LOG_FILE="/tmp/fusion-callback-handler.log"

mkdir -p "$CALLBACK_DIR"
chmod 0700 "$CALLBACK_DIR"

{
  echo "============================================================"
  echo "timestamp=$(date -Is)"
  echo "script=$0"
  echo "pid=$$"
  echo "ppid=$PPID"
  echo "pwd=$PWD"
  echo "argc=$#"

  argument_index=0
  for argument in "$@"; do
    printf 'argv[%d]=%q\n' "$argument_index" "$argument"
    echo "argv[${argument_index}]_len=${#argument}"
    echo "argv[${argument_index}]_first200=${argument:0:200}"
    echo "argv[${argument_index}]_last200=${argument: -200}"
    argument_index=$((argument_index + 1))
  done

  echo "--- env dump ---"
  echo "KDE_SESSION_VERSION=$KDE_SESSION_VERSION"
  echo "WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
  echo "DISPLAY=$DISPLAY"
  echo "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
  echo "DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS"
  echo "============================================================"
  echo
} >> "$LOG_FILE" 2>&1


if [[ $# -lt 1 ]]; then
  echo "no callback url received" >> "$LOG_FILE"
  echo "============================================================" >> "$LOG_FILE"
  echo >> "$LOG_FILE"
  exit 0
fi

request_name="$(date +%s.%N).$$"
partial_file="$CALLBACK_DIR/$request_name.partial"
request_file="$CALLBACK_DIR/$request_name.request"

printf "%s\n" "$1" > "$partial_file"
mv "$partial_file" "$request_file"

{
  echo "wrote_callback_request=$request_file"
  echo "============================================================"
  echo
} >> "$LOG_FILE" 2>&1

exit 0