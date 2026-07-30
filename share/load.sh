# share/load.sh — Single entry point for all share/ modules
#
# Usage: source /path/to/share/load.sh
#
# Sources all .fn files in dependency order.  Every script that needs
# share/ utilities should source THIS FILE ONLY, never individual .fn
# files directly.
#
# Layer 0 (no dependencies)
_this_file="${BASH_SOURCE[0]:-$0}"
_SHARE_DIR="$(cd "$(dirname "$_this_file")" && pwd)"
source "$_SHARE_DIR/colors.fn"
source "$_SHARE_DIR/paths.fn"
source "$_SHARE_DIR/constants.fn"
source "$_SHARE_DIR/guard.fn"
source "$_SHARE_DIR/traps.fn"

# Layer 1 (depends on Layer 0)
source "$_SHARE_DIR/log.fn"
source "$_SHARE_DIR/os.fn"
source "$_SHARE_DIR/network.fn"
source "$_SHARE_DIR/disk.fn"
source "$_SHARE_DIR/hosts.fn"

# Layer 2 (depends on Layers 0-1)
source "$_SHARE_DIR/proton.fn"
source "$_SHARE_DIR/wine.fn"
source "$_SHARE_DIR/config.fn"
source "$_SHARE_DIR/desktop.fn"
source "$_SHARE_DIR/icon.fn"
source "$_SHARE_DIR/browser-request.fn"
source "$_SHARE_DIR/detect-display.fn"
source "$_SHARE_DIR/browser-bridge.fn"

# Layer 3 (depends on Layers 0-2)
source "$_SHARE_DIR/dpi.fn"
source "$_SHARE_DIR/dark-mode.fn"
source "$_SHARE_DIR/process.fn"
source "$_SHARE_DIR/daemon.fn"
source "$_SHARE_DIR/cleanup.fn"

# Layer 4 (depends on Layers 0-1)
source "$_SHARE_DIR/report.fn"
source "$_SHARE_DIR/check-dep.fn"

unset _SHARE_DIR
