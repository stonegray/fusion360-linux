# src/install/10-deps.sh — System dependencies
detect_distro
echo "  [1/5] Installing packages: $PKGS"

if ! $INSTALL_CMD $PKGS 2>&1; then
  echo "  [1/5] Package install failed. Check sudo access and try again."
return 1
fi

echo "  [1/5] Done."
