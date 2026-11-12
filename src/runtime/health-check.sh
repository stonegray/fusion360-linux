#!/usr/bin/env bash
# runtime-scripts/health-check.sh — Quick health check before launching Fusion.
# Exits 0 if everything looks good, 1 otherwise.
set -euo pipefail 2>/dev/null || set -euo

# Load share/ modules for PFX_DIR, find_proton(), etc.
_share_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../share" 2>/dev/null && pwd)" || true
if [[ -z "$_share_dir" ]]; then
  _share_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../../share" 2>/dev/null && pwd)" || true
fi
if [[ -d "$_share_dir" ]]; then
  source "$_share_dir/load.sh"
fi
unset _share_dir
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fusion360-linux"
CONFIG_FILE="$CONFIG_DIR/config"

all_ok=1
check() {
  local label="$1"; shift
  if "$@" &>/dev/null; then
    echo "  [ok] $label"
  else
    echo "  [!!] $label"
    all_ok=0
  fi
}

echo "Fusion360 health check:"

check "Proton prefix exists"    test -d "$PFX_DIR/pfx"
check "Fusion360.exe found"     test -n "$(find "$PFX_DIR" -name Fusion360.exe -type f -print -quit 2>/dev/null)"
check "WebView2 installed"      test -d "$PFX_DIR/pfx/drive_c/Program Files (x86)/Microsoft/EdgeWebView"
check "Config file exists"      test -f "$CONFIG_FILE"
check "GE-Proton available"     test -n "$(find_proton "$COMPAT_DIR")"
check "Callback handler"        test -f "$HOME/.local/share/applications/fusion360-linux/fusion360-callback-handler.desktop"

# Opt-in upload fix (./install.sh --upload-fix): flag it if a Proton reinstall
# or update has replaced the patched wineserver.
upload_fix_intact() {
  local proton ws
  # Check the Proton the launcher uses, not just the first one installed.
  if declare -F configured_proton >/dev/null; then
    proton="$(configured_proton "$CONFIG_FILE")" || return 1
  else
    proton="$(find_proton "$COMPAT_DIR")" || return 1
  fi
  [[ -n "$proton" ]] || return 1
  ws="$(dirname "$proton")/files/bin/wineserver"
  grep -qs "^$(sha256sum "$ws" 2>/dev/null | awk '{print $1}')  " "$FUSION_DATA_DIR/upload-fix/patched.sha256"
}
if [[ -f "$FUSION_DATA_DIR/upload-fix/patched.sha256" ]]; then
  check "Upload fix (run ./install.sh --upload-fix)" upload_fix_intact
fi

if (( all_ok )); then
  echo "All checks passed."
  exit 0
else
  echo "Some checks failed. Run ./install.sh to fix."
  exit 1
fi
