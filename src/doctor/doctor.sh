#!/usr/bin/env bash
# doctor.sh — Comprehensive diagnostic for Fusion360 on Linux
#
# Splits into modules under src/doctor/*.sh. Run from anywhere in the repo.
#
# Usage:
#   ./doctor.sh              # full report
#   ./doctor.sh --save       # save to /tmp/fusion360-doctor-<ts>.txt
#   ./doctor.sh --quick      # condensed summary only

set -euo pipefail

# ── Root guard ─────────────────────────────────────────────────────────
if [[ $EUID -eq 0 ]]; then
  echo "ERROR: Do not run doctor.sh as root. Run as a normal user." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/00-common.sh"
parse_args "$@"
print_banner

for module in "$SCRIPT_DIR"/[0-9][0-9]-*.sh; do
  source "$module" 2>/dev/null || warn "Failed to load module: $(basename "$module")"
done

print_summary
