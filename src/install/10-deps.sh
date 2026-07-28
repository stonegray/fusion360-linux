# src/install/10-deps.sh — System dependencies
log_info " Installing packages: $PKGS"

if [[ -z "${PKGS:-}" ]]; then
  log_info " No packages to install."
  return 0
fi

set -f
if ! $INSTALL_CMD $PKGS 2>&1; then
  set +f
  log_info " Package install failed. Check sudo access and try again."
  return 1
fi
set +f

log_info " Done."
