#!/usr/bin/env bash
# Run the repository launcher with persistent graphics and exception logs.
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
log_root="${FUSION_DEBUG_LOG_ROOT:-$repo_dir/debug-logs}"
mkdir -p "$log_root"
log_dir="$(mktemp -d "$log_root/session-$(date +%Y%m%d-%H%M%S)-XXXXXX")"
export PROTON_LOG=1
export SteamGameId=fusion360
export PROTON_LOG_DIR="$log_dir"
export DXVK_LOG_LEVEL=info
export DXVK_LOG_PATH="$log_dir"
export WINEDEBUG="${FUSION_DEBUG_WINEDEBUG:-+timestamp,+pid,+tid,+seh,+debugstr}"
printf 'Fusion diagnostic logs: %s\n' "$log_dir"
status=0
bash "$repo_dir/src/bin/launch-fusion.sh" "$@" > >(tee "$log_dir/launcher.log") 2>&1 || status=$?
printf 'Fusion launcher exit status: %s\nLogs: %s\n' "$status" "$log_dir"
exit "$status"
