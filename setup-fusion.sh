#!/usr/bin/env bash
set -euo pipefail

# setup-fusion.sh — Phase 3: Post-install configuration for Fusion360 on Linux
# Re-runnable: safe to run any time to fix a broken configuration.
# Pass --force to re-do all steps even if already configured.

# ── Root guard ─────────────────────────────────────────────────────────
if [[ $EUID -eq 0 ]]; then
  echo "ERROR: Do not run setup-fusion.sh as root. Run as a normal user." >&2
  exit 1
fi

FORCE="${1:-}"

# ── Auto-detect paths ────────────────────────────────────────────────
GE_PROTON=$(find "$HOME/.local/share/Steam/compatibilitytools.d/" -name proton -type f 2>/dev/null | head -1 || true)
FUSION_EXE=$(find "$HOME/.fusion360-proton2" -name Fusion360.exe -type f 2>/dev/null | head -1 || true)
BROWSER=$(command -v google-chrome chromium-browser chromium firefox 2>/dev/null | head -1 || true)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fusion360-linux"
CONFIG_FILE="$CONFIG_DIR/config"
APPLICATIONS_DIR="$HOME/.local/share/applications"
ICONS_DIR="$HOME/.local/share/icons/hicolor"

# ── Check prerequisites ──────────────────────────────────────────────
if [[ -z "$FUSION_EXE" ]]; then
  cat >&2 <<EOF
ERROR: Fusion360.exe not found in ~/.fusion360-proton2.

Make sure you have completed Phase 2 (Fusion installer via Proton).
Run install.sh for instructions, or check:
  ~/.fusion360-proton2/pfx/drive_c/users/steamuser/AppData/Local/Autodesk/webdeploy/production/

If Fusion360.exe is in a different location, set the --configure path or
run launch-fusion.sh --configure after this script finishes.
EOF
  exit 1
fi

if [[ -z "$GE_PROTON" ]]; then
  cat >&2 <<EOF
ERROR: GE-Proton not found in ~/.local/share/Steam/compatibilitytools.d/

Download and extract GE-Proton first:
  wget https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton11-3/GE-Proton11-3.tar.gz
  tar -xf GE-Proton*.tar.gz -C ~/.local/share/Steam/compatibilitytools.d/
EOF
  exit 1
fi

echo "=== Fusion360 Linux — Phase 3: Configuration ==="
echo ""
echo "Detected:"
echo "  GE-Proton:     $GE_PROTON"
echo "  Fusion360.exe: $FUSION_EXE"
echo "  Browser:       ${BROWSER:-none detected}"
echo ""

# ── Helper: skip check ───────────────────────────────────────────────
already_done() {
  [[ "$FORCE" == "--force" ]] && return 1
  return 0
}

# ── Step a: Install WebView2 ─────────────────────────────────────────
install_webview2() {
  local pfx
  pfx="$HOME/.fusion360-proton2/pfx"

  if [[ -d "$pfx/drive_c/Program Files (x86)/Microsoft/EdgeWebView" ]]; then
    echo "[SKIP] WebView2 runtime already installed in Proton prefix."
    already_done && return
  fi

  echo "[WEBVIEW2] Downloading Microsoft Edge WebView2 bootstrapper..."
  local bootstrap="/tmp/MicrosoftEdgeWebview2Setup.exe"
  if [[ ! -f "$bootstrap" ]]; then
    wget -O "$bootstrap" "https://go.microsoft.com/fwlink/p/?LinkId=2124703" 2>/dev/null || {
      echo "[ERROR] Failed to download WebView2 bootstrapper. Check your internet connection."
      return 1
    }
  else
    echo "[WEBVIEW2] Bootstrapper already downloaded."
  fi

  echo "[WEBVIEW2] Installing WebView2 runtime into Proton prefix (unattended)..."
  echo "  This may take a minute. The installer runs silently."
  STEAM_COMPAT_DATA_PATH="$HOME/.fusion360-proton2" \
  STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam" \
  "$GE_PROTON" run "$bootstrap" /silent /install 2>/dev/null || true

  if [[ -d "$pfx/drive_c/Program Files (x86)/Microsoft/EdgeWebView" ]]; then
    echo "[WEBVIEW2] Installed successfully."
  else
    echo "[WARNING] WebView2 may not have installed. You can run setup-fusion.sh again later."
  fi
}

# ── Step b: Write config ─────────────────────────────────────────────
write_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    echo "[SKIP] Config file already exists: $CONFIG_FILE"
    already_done && return
  fi

  echo "[CONFIG] Writing config file..."
  mkdir -p "$CONFIG_DIR"

  FUSION_ROOT="$(dirname "$(dirname "$FUSION_EXE")")"

  cat > "$CONFIG_FILE" <<EOF
PROTON=$GE_PROTON
STEAM_COMPAT_DATA_PATH=$HOME/.fusion360-proton2
STEAM_COMPAT_CLIENT_INSTALL_PATH=$HOME/.local/share/Steam
FUSION_ROOT=$FUSION_ROOT
BROWSER=$SCRIPT_DIR/scripts/fusion-browser.sh
BROWSER_LISTENER=$SCRIPT_DIR/scripts/fusion-browser-listener.sh
CALLBACK_HANDLER=$SCRIPT_DIR/scripts/fusion-callback-handler.sh
CHROME=${BROWSER:-/usr/bin/firefox}
FUSION_OVERLAY_KILLER=$SCRIPT_DIR/scripts/fusion-gray-overlay-event-killer.sh
FUSION_WINE_RESTART_SCRIPT=$SCRIPT_DIR/scripts/kill-wine-proton-fusion-nuclear.sh
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

  echo "[CONFIG] Written to $CONFIG_FILE"
}

# ── Step c: Register protocol handlers ───────────────────────────────
register_protocols() {
  local desktop_file="$APPLICATIONS_DIR/fusion360-callback-handler.desktop"

  if [[ -f "$desktop_file" ]]; then
    echo "[SKIP] Protocol handler desktop file already exists."
    already_done && return
  fi

  echo "[PROTOCOLS] Registering adsk:// and adskidmgr:// protocol handlers..."
  mkdir -p "$APPLICATIONS_DIR"

  cat > "$desktop_file" <<EOF
[Desktop Entry]
Name=Fusion 360 Autodesk Callback Handler
Exec=$SCRIPT_DIR/scripts/fusion-callback-handler.sh %u
Type=Application
NoDisplay=true
MimeType=x-scheme-handler/adsk;x-scheme-handler/adskidmgr;
EOF

  xdg-mime default fusion360-callback-handler.desktop x-scheme-handler/adsk 2>/dev/null || true
  xdg-mime default fusion360-callback-handler.desktop x-scheme-handler/adskidmgr 2>/dev/null || true

  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APPLICATIONS_DIR" >/dev/null 2>&1 || true
  fi

  echo "[PROTOCOLS] Registered."
}

# ── Step d: Extract icons ────────────────────────────────────────────
extract_icons() {
  local icon_sizes
  icon_sizes="16 22 24 32 48 64 72 96 128 192 256 512"
  local need_extract=0

  for size in $icon_sizes; do
    local icon_file="$ICONS_DIR/${size}x${size}/apps/fusion360.png"
    if [[ ! -f "$icon_file" ]]; then
      need_extract=1
      break
    fi
  done

  if [[ $need_extract -eq 0 ]]; then
    echo "[SKIP] Icons already extracted."
    already_done && return
  fi

  echo "[ICONS] Extracting icons from Fusion360.exe..."
  if ! command -v wrestool &>/dev/null; then
    echo "[ERROR] wrestool not found. Install icoutils package."
    return 1
  fi
  if ! command -v convert &>/dev/null; then
    echo "[ERROR] convert (ImageMagick) not found. Install imagemagick package."
    return 1
  fi

  local tmp_ico
  tmp_ico=$(mktemp /tmp/fusion360-icon-XXXXX.ico)
  local tmp_png
  tmp_png=$(mktemp /tmp/fusion360-icon-XXXXX.png)

  wrestool -x -t 14 "$FUSION_EXE" > "$tmp_ico" 2>/dev/null || {
    echo "[WARNING] Failed to extract icon from Fusion360.exe (no icon resource found)."
    rm -f "$tmp_ico"
    return
  }

  for size in $icon_sizes; do
    local icon_dir="$ICONS_DIR/${size}x${size}/apps"
    mkdir -p "$icon_dir"
    convert "$tmp_ico" -resize "${size}x${size}" "$icon_dir/fusion360.png" 2>/dev/null || true
    if [[ -f "$icon_dir/fusion360.png" ]]; then
      echo "  Created: $icon_dir/fusion360.png"
    fi
  done

  rm -f "$tmp_ico" "$tmp_png"
  echo "[ICONS] Done."
}

# ── Step e: Install desktop entry ────────────────────────────────────
install_desktop_entry() {
  local desktop_entry="$APPLICATIONS_DIR/autodesk-fusion360.desktop"

  if [[ -f "$desktop_entry" ]]; then
    echo "[SKIP] Desktop entry already exists."
    already_done && return
  fi

  echo "[DESKTOP] Installing desktop entry..."
  mkdir -p "$APPLICATIONS_DIR"

  cat > "$desktop_entry" <<EOF
[Desktop Entry]
Name=Autodesk Fusion 360
Comment=Fusion 360 CAD/CAM/CAE tool
Exec=$SCRIPT_DIR/launch-fusion.sh
Type=Application
Categories=Graphics;Science;Engineering;
StartupNotify=true
StartupWMClass=fusion360.exe
MimeType=application/x-fusion360
EOF

  chmod 644 "$desktop_entry"

  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APPLICATIONS_DIR" >/dev/null 2>&1 || true
  fi

  echo "[DESKTOP] Installed: $desktop_entry"
}

# ── Step f: Refresh KDE menu ─────────────────────────────────────────
refresh_kde_menu() {
  if command -v kbuildsycoca6 &>/dev/null; then
    echo "[KDE] Refreshing KDE menu cache..."
    kbuildsycoca6 2>/dev/null || true
    echo "[KDE] Done."
  elif command -v kbuildsycoca5 &>/dev/null; then
    echo "[KDE] Refreshing KDE menu cache..."
    kbuildsycoca5 2>/dev/null || true
    echo "[KDE] Done."
  else
    echo "[KDE] kbuildsycoca not found (not a KDE Plasma session, skipping)."
  fi
}

# ── Step g: Clean bridge temp dirs ───────────────────────────────────
clean_bridge_temps() {
  echo "[CLEAN] Removing stale bridge temp files..."
  rm -rf /tmp/fusion360-* 2>/dev/null || true
  echo "[CLEAN] Done."
}

# ── Main ─────────────────────────────────────────────────────────────
main() {
  install_webview2
  write_config
  register_protocols
  extract_icons
  install_desktop_entry
  refresh_kde_menu
  clean_bridge_temps

  echo ""
  echo "============================================================"
  echo "Setup complete! Run ./launch-fusion.sh to start Fusion360."
  echo "Or use: make run"
  echo "============================================================"
}

main "$@"
