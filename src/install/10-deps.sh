# src/install/10-deps.sh — System dependencies
echo "  [1/5] Installing packages: $PKGS"

if [[ -z "${PKGS:-}" ]]; then
  echo "  [deps] No packages to install."
  return 0
fi

set -f
if ! $INSTALL_CMD $PKGS 2>&1; then
  set +f
  echo "  [1/5] Package install failed. Check sudo access and try again."
  return 1
fi
set +f

echo "  [1/5] Done."
