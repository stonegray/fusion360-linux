# src/install/25-install-to-location.sh — Copy runtime scripts to XDG data dir
# After this step, the install is self-contained and doesn't need the repo.

echo "  [install] Installing runtime scripts to $F360_DATA_DIR..."

# Create target directories
mkdir -p "$F360_DATA_DIR"
mkdir -p "$F360_APPS_DIR"
mkdir -p "$F360_BIN_DIR"

# Copy runtime scripts
mkdir -p "$F360_DATA_DIR/runtime-scripts"
cp -r "$SCRIPT_DIR/src/runtime/." "$F360_DATA_DIR/runtime-scripts/"
cp "$SCRIPT_DIR/src/bin/launch-fusion.sh" "$F360_DATA_DIR/"
cp "$SCRIPT_DIR/Makefile" "$F360_DATA_DIR/" 2>/dev/null || true
chmod +x "$F360_DATA_DIR/launch-fusion.sh" "$F360_DATA_DIR/runtime-scripts/"*.sh "$F360_DATA_DIR/runtime-scripts/"*.py 2>/dev/null || true

# Create CLI symlinks
ln -sf "$F360_DATA_DIR/launch-fusion.sh" "$F360_BIN_DIR/launch-fusion"
ln -sf "$F360_DATA_DIR/launch-fusion.sh" "$F360_BIN_DIR/fusion360"
ln -sf "$SCRIPT_DIR/status.sh" "$F360_BIN_DIR/fusion-status" 2>/dev/null || true
ln -sf "$SCRIPT_DIR/doctor.sh" "$F360_BIN_DIR/fusion-doctor" 2>/dev/null || true
ln -sf "$SCRIPT_DIR/uninstall.sh" "$F360_BIN_DIR/fusion-uninstall" 2>/dev/null || true

echo "  [install] Runtime scripts installed to $F360_DATA_DIR"
echo "  [install] CLI symlinks in $F360_BIN_DIR: launch-fusion, fusion360, fusion-status, fusion-doctor, fusion-uninstall"
