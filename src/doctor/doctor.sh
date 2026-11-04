#!/usr/bin/env bash
# doctor.sh — Comprehensive diagnostic for Fusion360 on Linux
#
# Splits into modules under src/doctor/*.sh. Run from anywhere in the repo.
#
# Usage:
#   ./doctor.sh              # full report
#   ./doctor.sh --save       # save to /tmp/fusion360-doctor-<ts>.txt
#   ./doctor.sh --quick      # condensed summary only

set -euo pipefail 2>/dev/null || set -euo

# ── Root guard ─────────────────────────────────────────────────────────
if [[ $EUID -eq 0 ]]; then
  echo "ERROR: Do not run doctor.sh as root. Run as a normal user." >&2
  exit 1
fi

# readlink -f: doctor.sh is reached through the ~/.local/bin/fusion-doctor
# symlink, and plain dirname would point SCRIPT_DIR at ~/.local/bin, where
# none of the NN-*.sh modules live.
_this_file="$(readlink -f "${BASH_SOURCE[0]:-$0}")"
SCRIPT_DIR="$(cd "$(dirname "$_this_file")" && pwd)"

source "$SCRIPT_DIR/00-common.sh"
parse_args "$@"
print_banner

if ! compgen -G "$SCRIPT_DIR/[0-9][0-9]-*.sh" >/dev/null; then
  echo "ERROR: no check modules found in $SCRIPT_DIR." >&2
  echo "       The install is incomplete — re-run install.sh." >&2
  exit 1
fi

for module in "$SCRIPT_DIR"/[0-9][0-9]-*.sh; do
  # Not silenced: a module that fails to load would otherwise be reported as
  # an empty warning while its checks silently never run.
  source "$module" || warn "Failed to load module: $(basename "$module")"
done

print_summary
