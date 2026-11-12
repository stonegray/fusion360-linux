#!/usr/bin/env bash
set -euo pipefail 2>/dev/null || set -euo

# Load share/ modules for interval constants
_share_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../share" 2>/dev/null && pwd)" || true
if [[ -z "$_share_dir" ]]; then
  _share_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../../share" 2>/dev/null && pwd)" || true
fi
if [[ -d "$_share_dir" ]]; then
  source "$_share_dir/load.sh"
fi
unset _share_dir
# fusion-gray-overlay-event-killer-parent-exit.sh:
# Event-driven closer for Fusion 360's broken Wine grey modal overlay.
#
# It waits for X11 client-list changes, closes only the grey overlay candidate,
# and exits once the tracked Fusion parent window no longer exists.
#
# Overlay match:
#   WM_NAME contains "Fusion360"
#   _NET_WM_WINDOW_TYPE contains "_NET_WM_WINDOW_TYPE_DIALOG"
#   _NET_WM_WINDOW_OPACITY exists
#   _WINE_HWND_EXSTYLE contains "524416"
#   WM_TRANSIENT_FOR points to a parent window
#   overlay size is close to that parent window size
#
# Usage:
#   ./fusion-gray-overlay-event-killer-parent-exit.sh
#
# Optional:
#   FUSION_OVERLAY_SIZE_TOLERANCE_PERCENT=25 ./fusion-gray-overlay-event-killer-parent-exit.sh
#   FUSION_OVERLAY_PARENT_WINDOW_ID=0x123456 ./fusion-gray-overlay-event-killer-parent-exit.sh

LOG_FILE="${FUSION_OVERLAY_LOG_FILE:-/tmp/fusion360-gray-overlay-event-killer.log}"
SIZE_TOLERANCE_PERCENT="${FUSION_OVERLAY_SIZE_TOLERANCE_PERCENT:-25}"
PARENT_WINDOW_ID="${FUSION_OVERLAY_PARENT_WINDOW_ID:-}"

echo "fusion-gray-overlay-event-killer-parent-exit started at $(date -Is)" >> "$LOG_FILE"
# This daemon uses X11-specific tools (xdotool, xprop, xwininfo) to
# detect and close Fusion 360's grey modal overlay windows.  On Wayland
# these tools are not available; exit gracefully with a log message.
if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
  echo "$(date -Is) Wayland detected — overlay killer requires X11, exiting." >> "$LOG_FILE"
  exit 0
fi

for _tool in xdotool xprop xwininfo; do
  if ! command -v "$_tool" >/dev/null 2>&1; then
    echo "$(date -Is) WARNING: $_tool not found - grey overlays will not be closed and dialogs will not accept mouse clicks. Install it (e.g. sudo apt install xdotool x11-utils)." >> "$LOG_FILE"
  fi
done
unset _tool

window_exists() {
  xprop -id "$1" WM_NAME >/dev/null 2>&1
}

get_window_width() {
  xwininfo -id "$1" 2>/dev/null | awk '/Width:/ {print $2; exit}'
}

get_window_height() {
  xwininfo -id "$1" 2>/dev/null | awk '/Height:/ {print $2; exit}'
}

get_transient_parent_id() {
  xprop -id "$1" WM_TRANSIENT_FOR 2>/dev/null | grep -o '0x[0-9a-fA-F]\+' | tail -n 1
}

numbers_are_close() {
  local a="$1"
  local b="$2"
  local tolerance_percent="$3"
  local difference
  local allowed_difference

  [[ "$a" =~ ^[0-9]+$ ]] || return 1
  [[ "$b" =~ ^[0-9]+$ ]] || return 1

  if (( a > b )); then
    difference=$((a - b))
  else
    difference=$((b - a))
  fi

  allowed_difference=$((b * tolerance_percent / 100))
  (( allowed_difference < 8 )) && allowed_difference=8

  (( difference <= allowed_difference ))
}

is_same_size_as_parent() {
  local window_id="$1"
  local parent_id
  local window_width
  local window_height
  local parent_width
  local parent_height

  parent_id="$(get_transient_parent_id "$window_id")"
  [[ -n "$parent_id" ]] || return 1
  window_exists "$parent_id" || return 1

  window_width="$(get_window_width "$window_id")"
  window_height="$(get_window_height "$window_id")"
  parent_width="$(get_window_width "$parent_id")"
  parent_height="$(get_window_height "$parent_id")"

  [[ "$window_width" =~ ^[0-9]+$ ]] || return 1
  [[ "$window_height" =~ ^[0-9]+$ ]] || return 1
  [[ "$parent_width" =~ ^[0-9]+$ ]] || return 1
  [[ "$parent_height" =~ ^[0-9]+$ ]] || return 1

  numbers_are_close "$window_width" "$parent_width" "$SIZE_TOLERANCE_PERCENT" || return 1
  numbers_are_close "$window_height" "$parent_height" "$SIZE_TOLERANCE_PERCENT" || return 1

  return 0
}

remember_parent_from_overlay() {
  local window_id="$1"
  local parent_id

  parent_id="$(get_transient_parent_id "$window_id")"
  [[ -n "$parent_id" ]] || return 1
  window_exists "$parent_id" || return 1

  if [[ -z "$PARENT_WINDOW_ID" ]]; then
    PARENT_WINDOW_ID="$parent_id"
    echo "$(date -Is) tracking Fusion parent window_id=$PARENT_WINDOW_ID" >> "$LOG_FILE"
  fi

  return 0
}

check_parent_still_exists() {
  if [[ -z "$PARENT_WINDOW_ID" ]]; then
    return 0
  fi

  if window_exists "$PARENT_WINDOW_ID"; then
    return 0
  fi

  echo "$(date -Is) tracked Fusion parent disappeared, exiting parent_window_id=$PARENT_WINDOW_ID" >> "$LOG_FILE"
  exit 0
}

is_overlay_window() {
  local window_id="$1"
  local window_name
  local window_type
  local window_opacity
  local wine_exstyle

  window_name="$(xprop -id "$window_id" WM_NAME 2>/dev/null || true)"
  window_type="$(xprop -id "$window_id" _NET_WM_WINDOW_TYPE 2>/dev/null || true)"
  window_opacity="$(xprop -id "$window_id" _NET_WM_WINDOW_OPACITY 2>/dev/null || true)"
  wine_exstyle="$(xprop -id "$window_id" _WINE_HWND_EXSTYLE 2>/dev/null || true)"

  echo "$window_name" | grep -q '"Fusion360"' || return 1
  echo "$window_type" | grep -q "_NET_WM_WINDOW_TYPE_DIALOG" || return 1
  echo "$window_opacity" | grep -q "_NET_WM_WINDOW_OPACITY" || return 1
  echo "$wine_exstyle" | grep -q "524416" || return 1
  is_same_size_as_parent "$window_id" || return 1

  return 0
}

close_gray_overlays() {
  local window_id

  check_parent_still_exists

  while read -r window_id; do
    [[ -n "$window_id" ]] || continue

    if is_overlay_window "$window_id"; then
      remember_parent_from_overlay "$window_id"
      echo "$(date -Is) closing grey overlay window_id=$window_id parent_window_id=$PARENT_WINDOW_ID" >> "$LOG_FILE"
      xdotool windowclose "$window_id" 2>/dev/null || true
    fi
  done < <(xdotool search --onlyvisible --class steam_proton 2>/dev/null || true)

  check_parent_still_exists
}

# Fusion's modal dialogs (e.g. "Move to") are mapped as top-level NORMAL windows
# with skip-taskbar and no WM_TRANSIENT_FOR, so the WM can stack them *below* the
# main Fusion window. The main window is disabled while the modal is open, which
# looks like a hang. Raise any such dialog that sits below *its own* main window.
#
# Every Proton app shares the steam_proton class, so ownership is established
# with _NET_WM_PID (Wine sets it to the owning process): a dialog is only
# considered if a main Fusion window from the same process exists, and it is
# only compared with that process's main windows. Windows without the property
# are ignored.
raise_buried_dialogs() {
  local stacking window_id props pid pos main_pos i
  local -a stack dialogs=()
  local -A main_top=() dialog_pid=()

  stacking="$(xprop -root _NET_CLIENT_LIST_STACKING 2>/dev/null)" || return 0
  read -r -a stack <<< "$(grep -o '0x[0-9a-fA-F]\+' <<< "$stacking" | tr '\n' ' ')"

  # Position in stacking order (bottom -> top); xdotool gives decimal ids.
  stack_pos() {
    local want; want="$(printf '0x%x' "$1")"
    for i in "${!stack[@]}"; do
      [[ "$(printf '0x%x' "${stack[$i]}")" == "$want" ]] && { echo "$i"; return; }
    done
    echo -1
  }

  while read -r window_id; do
    [[ -n "$window_id" ]] || continue
    props="$(xprop -id "$window_id" WM_NAME _NET_WM_WINDOW_TYPE _NET_WM_STATE WM_TRANSIENT_FOR _NET_WM_PID 2>/dev/null)" || continue
    grep -q '_NET_WM_WINDOW_TYPE_NORMAL' <<< "$props" || continue
    pid="$(sed -n 's/^_NET_WM_PID(CARDINAL) = \([0-9][0-9]*\)$/\1/p' <<< "$props")"
    [[ -n "$pid" ]] || continue
    if grep -q '^WM_NAME([^)]*) = ".* - Autodesk Fusion' <<< "$props"; then
      pos="$(stack_pos "$window_id")"
      if (( pos > ${main_top[$pid]:--1} )); then main_top[$pid]=$pos; fi
    elif grep -q '_NET_WM_STATE_SKIP_TASKBAR' <<< "$props" \
         && grep -q 'WM_TRANSIENT_FOR:  not found' <<< "$props"; then
      dialogs+=("$window_id")
      dialog_pid[$window_id]=$pid
    fi
  done < <(xdotool search --onlyvisible --class steam_proton 2>/dev/null || true)

  (( ${#main_top[@]} && ${#dialogs[@]} )) || return 0

  for window_id in "${dialogs[@]}"; do
    pid="${dialog_pid[$window_id]}"
    main_pos="${main_top[$pid]:-}"
    [[ -n "$main_pos" ]] || continue          # not a Fusion process's dialog
    pos="$(stack_pos "$window_id")"
    (( pos >= 0 && pos < main_pos )) || continue
    echo "$(date -Is) raising buried dialog window_id=$window_id pid=$pid name=$(xdotool getwindowname "$window_id" 2>/dev/null)" >> "$LOG_FILE"
    xdotool windowraise "$window_id" 2>/dev/null || true
    xdotool windowactivate "$window_id" 2>/dev/null || true
  done
  return 0
}

close_gray_overlays
raise_buried_dialogs

if command -v stdbuf >/dev/null 2>&1; then
  XPROP_COMMAND=(stdbuf -oL xprop -root -spy _NET_CLIENT_LIST)
else
  XPROP_COMMAND=(xprop -root -spy _NET_CLIENT_LIST)
fi

# React to client-list changes, but also re-check every second: Wine can map the
# overlay before it sets opacity/size, so the single event-triggered check races.
"${XPROP_COMMAND[@]}" 2>/dev/null | while true; do
  _rc=0
  IFS= read -r -t 1 _event_line || _rc=$?
  (( _rc == 0 || _rc > 128 )) || break   # 1 = EOF (xprop died)
  (( _rc == 0 )) && sleep "$OVERLAY_KILLER_POLL_INTERVAL"
  close_gray_overlays
  raise_buried_dialogs
done