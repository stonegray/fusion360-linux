# install-scripts/10-deps.sh — System dependencies
detect_distro
echo "  [1/5] Installing packages: $PKGS"

source "$SCRIPT_DIR/helpers/run_scrollbox.sh"
if ! run_scrollbox 10 "$INSTALL_CMD $PKGS"; then
  echo "  [1/5] Package install failed. Check sudo access and try again."
  exit 1
fi
