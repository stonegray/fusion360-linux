# install-scripts/10-deps.sh — System dependencies
echo "  [1/5] Installing packages: $PKGS"
detect_distro

source "$SCRIPT_DIR/helpers/run_scrollbox.sh"
run_scrollbox 10 "$INSTALL_CMD $PKGS"

echo "  [1/5] Done."
