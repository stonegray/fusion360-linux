# install-scripts/10-deps.sh — System dependencies
detect_distro
echo "  [1/5] Installing packages: $PKGS"

source "$SCRIPT_DIR/helpers/run_scrollbox.sh"
if ! $INSTALL_CMD $PKGS 2>&1 | run_scrollbox 5; then
  echo "  [1/5] Package install failed. Check sudo access and try again."
  exit 1
fi

echo "  [1/5] Done."
