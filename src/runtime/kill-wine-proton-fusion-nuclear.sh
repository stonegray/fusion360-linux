#!/usr/bin/env bash
# File: kill-wine-proton-fusion-nuclear.sh
set -euo pipefail 2>/dev/null || set -euo

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/launcher-functions.sh"
kill_fusion_processes
