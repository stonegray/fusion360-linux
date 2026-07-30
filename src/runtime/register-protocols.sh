#!/usr/bin/env bash
# runtime-scripts/register-protocols.sh — Register adsk:// and adskidmgr:// protocol handlers
set -euo pipefail 2>/dev/null || set -euo
SCRIPT_DIR="$(cd "$(dirname "\${BASH_SOURCE[0]:-$0}")/.." && pwd)"
RUNTIME_DIR="$(cd "$(dirname "\${BASH_SOURCE[0]:-$0}")" && pwd)"
APPS="${F360_APPS_DIR:-$HOME/.local/share/applications/fusion360-linux}"
mkdir -p "$APPS"

cat > "$APPS/fusion360-callback-handler.desktop" <<EOF
[Desktop Entry]
Name=Fusion 360 Autodesk Callback Handler
Exec=$RUNTIME_DIR/fusion-callback-handler.sh %u
Type=Application
NoDisplay=true
MimeType=x-scheme-handler/adsk;x-scheme-handler/adskidmgr;
EOF

xdg-mime default fusion360-callback-handler.desktop x-scheme-handler/adsk 2>/dev/null || true
xdg-mime default fusion360-callback-handler.desktop x-scheme-handler/adskidmgr 2>/dev/null || true
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS" 2>/dev/null || true
echo "  adsk:// and adskidmgr:// registered"
