#!/usr/bin/env bash
# doctor.sh — Comprehensive diagnostic for Fusion360 on Linux
#
# Splits into modules under doctor/*.sh. Run from anywhere in the repo.
#
# Usage:
#   ./doctor.sh              # full report
#   ./doctor.sh --save       # save to /tmp/fusion360-doctor-<ts>.txt
#   ./doctor.sh --quick      # condensed summary only

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/doctor/00-common.sh"
parse_args "$@"
print_banner

for module in "$SCRIPT_DIR"/doctor/[0-9][0-9]-*.sh; do
  source "$module"
done

print_summary
