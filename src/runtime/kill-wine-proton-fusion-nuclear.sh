#!/usr/bin/env bash
# File: kill-wine-proton-fusion-nuclear.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/runtime/launcher-functions.sh"
kill_fusion_processes
