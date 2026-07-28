#!/usr/bin/env bash
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
  done < <(xdotool search --class steam_proton 2>/dev/null || true)

  check_parent_still_exists
}

close_gray_overlays

if command -v stdbuf >/dev/null 2>&1; then
  XPROP_COMMAND=(stdbuf -oL xprop -root -spy _NET_CLIENT_LIST)
else
  XPROP_COMMAND=(xprop -root -spy _NET_CLIENT_LIST)
fi

"${XPROP_COMMAND[@]}" 2>/dev/null | while IFS= read -r _event_line; do
  sleep 0.05
  close_gray_overlays
done