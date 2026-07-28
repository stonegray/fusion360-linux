#!/usr/bin/env bash
# setup-fusion.sh — Post-install configuration for Fusion360 on Linux.
# Re-runnable: fixes whatever is missing. Pass --force to re-do everything.
# Does not require Fusion360.exe to be installed yet — skips icon extraction if absent.
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
  echo "ERROR: Do not run setup-fusion.sh as root. Run as a normal user." >&2
  exit 1
fi

FORCE="${1:-}"

GE_PROTON=$(find "$HOME/.local/share/Steam/compatibilitytools.d/" -name proton -type f 2>/dev/null | head -1 || true)
FUSION_EXE=$(find "$HOME/.fusion360-proton2" -name Fusion360.exe -type f 2>/dev/null | head -1 || true)
BROWSER=$(command -v google-chrome chromium-browser chromium firefox 2>/dev/null | head -1 || true)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fusion360-linux"
CONFIG_FILE="$CONFIG_DIR/config"
APPLICATIONS_DIR="$HOME/.local/share/applications"
ICONS_DIR="$HOME/.local/share/icons/hicolor"

if [[ -z "$GE_PROTON" ]]; then
  echo "ERROR: GE-Proton not found. Run install.sh first."
  exit 1
fi

echo "setup: paths detected"
echo "  proton:   $GE_PROTON"
echo "  fusion:   ${FUSION_EXE:-not installed yet}"
echo "  browser:  ${BROWSER:-none}"
echo ""

# ── Step 1: WebView2 ──────────────────────────────────────────────────
install_webview2() {
  local pfx="$HOME/.fusion360-proton2/pfx"
  local target="$pfx/drive_c/Program Files (x86)/Microsoft/EdgeWebView"
  if [[ -d "$target" && "$FORCE" != "--force" ]]; then
    echo "  webview2: already installed"
    return
  fi

  local bootstrap="/tmp/MicrosoftEdgeWebview2Setup.exe"
  if [[ ! -f "$bootstrap" ]]; then
    echo "  webview2: downloading..."
    wget -q -O "$bootstrap" "https://go.microsoft.com/fwlink/p/?LinkId=2124703"
  fi

  echo "  webview2: installing (silent)..."
  STEAM_COMPAT_DATA_PATH="$HOME/.fusion360-proton2" \
  STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam" \
  "$GE_PROTON" run "$bootstrap" /silent /install 2>/dev/null || true

  if [[ -d "$target" ]]; then
    echo "  webview2: done"
  else
    echo "  webview2: install may not have completed (can re-run)"
  fi
}

# ── Step 2: config ────────────────────────────────────────────────────
write_config() {
  if [[ -f "$CONFIG_FILE" && "$FORCE" != "--force" ]]; then
    echo "  config:   already present"
    return
  fi

  mkdir -p "$CONFIG_DIR"

  local fusion_root=""
  if [[ -n "$FUSION_EXE" ]]; then
    fusion_root="$(dirname "$(dirname "$FUSION_EXE")")"
  else
    fusion_root="$HOME/.fusion360-proton2/pfx/drive_c/users/steamuser/AppData/Local/Autodesk/webdeploy/production"
  fi

  cat > "$CONFIG_FILE" <<EOF
PROTON=$GE_PROTON
STEAM_COMPAT_DATA_PATH=$HOME/.fusion360-proton2
STEAM_COMPAT_CLIENT_INSTALL_PATH=$HOME/.local/share/Steam
FUSION_ROOT=$fusion_root
BROWSER=$SCRIPT_DIR/runtime-scripts/fusion-browser.sh
BROWSER_LISTENER=$SCRIPT_DIR/runtime-scripts/fusion-browser-listener.sh
CALLBACK_HANDLER=$SCRIPT_DIR/runtime-scripts/fusion-callback-handler.sh
CHROME=${BROWSER:-/usr/bin/firefox}
FUSION_OVERLAY_KILLER=$SCRIPT_DIR/runtime-scripts/fusion-gray-overlay-event-killer.sh
FUSION_WINE_RESTART_SCRIPT=$SCRIPT_DIR/runtime-scripts/kill-wine-proton-fusion-nuclear.sh
FUSION_WINE_DPI=auto
FUSION_WINE_SCALE_PERCENT=auto
FUSION_WINE_DPI_FALLBACK=144
FUSION_WINE_SCALE_FALLBACK_PERCENT=150
FUSION_PROTON_USE_WINED3D=0
FUSION_PROTON_USE_XALIA=0
FUSION_DXVK_ASYNC=1
FUSION_NO_AT_BRIDGE=1
FUSION_FIX_BCP47LANGS=1
FUSION_WEBVIEW_NO_SANDBOX=1
FUSION_WEBVIEW_DISABLE_GPU=0
FUSION_USE_INTEL_VK_ICD=1
FUSION_ENABLE_OVERLAY_KILLER=1
FUSION_OVERLAY_SIZE_TOLERANCE_PERCENT=25
EOF
  echo "  config:   written"
}

# ── Step 3: protocol handlers ─────────────────────────────────────────
register_protocols() {
  local desktop="$APPLICATIONS_DIR/fusion360-callback-handler.desktop"
  if [[ -f "$desktop" && "$FORCE" != "--force" ]]; then
    echo "  adsk://:  already registered"
    return
  fi

  mkdir -p "$APPLICATIONS_DIR"
  cat > "$desktop" <<EOF
[Desktop Entry]
Name=Fusion 360 Autodesk Callback Handler
Exec=$SCRIPT_DIR/runtime-scripts/fusion-callback-handler.sh %u
Type=Application
NoDisplay=true
MimeType=x-scheme-handler/adsk;x-scheme-handler/adskidmgr;
EOF

  xdg-mime default fusion360-callback-handler.desktop x-scheme-handler/adsk 2>/dev/null || true
  xdg-mime default fusion360-callback-handler.desktop x-scheme-handler/adskidmgr 2>/dev/null || true
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPLICATIONS_DIR" 2>/dev/null || true
  echo "  adsk://:  registered"
}

# ── Step 4: icons (requires Fusion.exe) ───────────────────────────────
extract_icons() {
  if [[ -z "$FUSION_EXE" ]]; then
    echo "  icons:    skip (Fusion360.exe not installed yet)"
    return
  fi

  local sizes="16 22 24 32 48 64 72 96 128 192 256 512"
  local missing=0
  for s in $sizes; do
    [[ -f "$ICONS_DIR/${s}x${s}/apps/fusion360.png" ]] || missing=1
  done
  if [[ $missing -eq 0 && "$FORCE" != "--force" ]]; then
    echo "  icons:    already extracted"
    return
  fi

  if ! command -v wrestool &>/dev/null || ! command -v convert &>/dev/null; then
    echo "  icons:    skip (wrestool/convert not available)"
    return
  fi

  local ico; ico=$(mktemp /tmp/fusion360-icon-XXXXX.ico)
  wrestool -x -t 14 "$FUSION_EXE" > "$ico" 2>/dev/null || { rm -f "$ico"; echo "  icons:    no icon resource found"; return; }

  for s in $sizes; do
    local dir="$ICONS_DIR/${s}x${s}/apps"
    mkdir -p "$dir"
    convert "$ico" -resize "${s}x${s}" "$dir/fusion360.png" 2>/dev/null || true
  done
  rm -f "$ico"
  echo "  icons:    extracted"
}

# ── Step 5: desktop entry ────────────────────────────────────────────
install_desktop_entry() {
  local entry="$APPLICATIONS_DIR/autodesk-fusion360.desktop"
  if [[ -f "$entry" && "$FORCE" != "--force" ]]; then
    echo "  desktop:  already installed"
    return
  fi

  mkdir -p "$APPLICATIONS_DIR"
  cat > "$entry" <<EOF
[Desktop Entry]
Name=Autodesk Fusion 360
Comment=Fusion 360 CAD/CAM/CAE tool
Exec=$SCRIPT_DIR/launch-fusion.sh
Type=Application
Categories=Graphics;Science;Engineering;
StartupNotify=true
StartupWMClass=fusion360.exe
EOF

  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPLICATIONS_DIR" 2>/dev/null || true
  echo "  desktop:  installed"
}

# ── Step 6: KDE menu ─────────────────────────────────────────────────
refresh_kde_menu() {
  command -v kbuildsycoca6 &>/dev/null && { kbuildsycoca6 2>/dev/null || true; }
  command -v kbuildsycoca5 &>/dev/null && { kbuildsycoca5 2>/dev/null || true; }
}

# ── Step 7: cleanup ──────────────────────────────────────────────────
clean_bridge_temps() {
  rm -rf /tmp/fusion360-* 2>/dev/null || true
}

# ── Main ─────────────────────────────────────────────────────────────
echo "── setup: configuring fusion360 ──"
install_webview2
write_config
register_protocols
extract_icons
install_desktop_entry
refresh_kde_menu
clean_bridge_temps
echo ""
echo "  done. install fusion with:  ./install.sh --run-installer"
echo "  or launch with:             ./launch-fusion.sh"
