# install-scripts/10-deps.sh — System dependencies
echo "  [1/5] Installing packages: $PKGS"
detect_distro
$INSTALL_CMD $PKGS
echo "  [1/5] Done."
