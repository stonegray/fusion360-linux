#!/usr/bin/env bash
# File: kill-wine-proton-fusion-nuclear.sh
set -euo pipefail 2>/dev/null || set -euo

_this_file="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$_this_file")" && pwd)"
source "$SCRIPT_DIR/launcher-functions.sh"
kill_fusion_processes
