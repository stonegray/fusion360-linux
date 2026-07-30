# src/install/99-uninstall.sh — Interactive selective uninstall
# Sourced by install.sh --uninstall
set -euo pipefail 2>/dev/null || set -euo
: "${HOME:?HOME must be set to run selective uninstall}"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     Fusion360 Linux — Selective Uninstall                   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ── Scan for components ────────────────────────────────────────────
components=()
comp_names=()
comp_sizes=()

add_comp() {
  local name="$1" path="$2"
  # Handle glob paths — collect ALL matches
  if [[ "$path" == *\** ]]; then
    local matches=()
    while IFS= read -r -d '' match; do
      matches+=("$match")
    done < <(compgen -G "$path" 2>/dev/null || true)
    (( ${#matches[@]} == 0 )) && return 0
    for match in "${matches[@]}"; do
      local size
      size=$(du -sh "$match" 2>/dev/null | cut -f1)
      components+=("$match")
      comp_names+=("$name")
      comp_sizes+=("$size")
    done
    return 0
  fi
  if [[ -e "$path" ]]; then
    local size
    size=$(du -sh "$path" 2>/dev/null | cut -f1)
    components+=("$path")
    comp_names+=("$name")
    comp_sizes+=("$size")
  fi
}

add_comp "Proton prefix (Fusion install)" "$PFX_DIR"

for g in "$HOME/.local/share/Steam/compatibilitytools.d"/GE-Proton*; do
  [[ -d "$g" ]] || continue
  add_comp "GE-Proton ($(basename "$g"))" "$g"
done
add_comp "Config files" "$HOME/.config/fusion360-linux"
add_comp "Callback handler desktop entry" \
  "$HOME/.local/share/applications/fusion360-linux/fusion360-callback-handler.desktop"
add_comp "Fusion 360 desktop entry" \
  "$HOME/.local/share/applications/fusion360-linux/autodesk-fusion360.desktop"

found_icons=0
for icon in "$HOME"/.local/share/icons/hicolor/*/apps/fusion360.png; do
  [[ -f "$icon" ]] && found_icons=1
done
if (( found_icons )); then
  add_comp "Application icons" "$HOME/.local/share/icons/hicolor/*/apps/fusion360.png"
fi
add_comp "MIME type definitions" "${XDG_DATA_HOME:-$HOME/.local/share}/mime/packages/fusion360.xml"
add_comp "Bridge temp files" "/tmp/fusion360-*"

if (( ${#components[@]} == 0 )); then
  echo "  No Fusion360 components found. Nothing to uninstall."
  exit 0
fi

# ── Show menu ──────────────────────────────────────────────────────
echo "  Found ${#components[@]} component(s):"
echo ""
for ((i=0; i<${#components[@]}; i++)); do
  printf "  [%d] %-45s %s\n" "$((i+1))" "${comp_names[i]}" "${comp_sizes[i]}"
done
echo ""
printf '%s' "  Enter numbers to remove (space-separated, or 'all'): "
read -r -t 120 selection

# ── Parse selection ────────────────────────────────────────────────
selected=()
if [[ "$selection" == "all" ]]; then
  for ((i=0; i<${#components[@]}; i++)); do
    selected+=("$i")
  done
else
  set -f
  for num in $selection; do
    [[ "$num" =~ ^[0-9]+$ ]] || continue
    idx=$((num - 1))
    if (( idx >= 0 && idx < ${#components[@]} )); then
      selected+=("$idx")
    fi
  done
  set +f
fi

if (( ${#selected[@]} == 0 )); then
  echo "  Nothing selected. Aborted."
  exit 0
fi

# ── Confirm ────────────────────────────────────────────────────────
echo ""
echo "  Will remove:"
for idx in "${selected[@]}"; do
  echo "    - ${comp_names[idx]} (${comp_sizes[idx]})"
done
echo ""
printf '%s' "  Proceed? [y/N] "
read -r -t 120 confirm
case "$confirm" in
  y|Y|yes|Yes)
    ;;
  *)
    echo "  Aborted."
    exit 0
    ;;
esac

# ── Execute ────────────────────────────────────────────────────────
echo ""
for idx in "${selected[@]}"; do
  echo "  Removing ${comp_names[idx]}..."
  comp_path="${components[idx]}"
  if [[ -n "$comp_path" ]]; then
    rm -rf "$comp_path"
  fi
done

refresh_desktop_database

echo ""
echo "  Done."
