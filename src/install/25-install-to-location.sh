# src/install/25-install-to-location.sh — Copy runtime scripts to XDG data dir
# After this step, the install is self-contained and doesn't need the repo.

log_info " Installing runtime scripts to $F360_DATA_DIR..."

# Create target directories
mkdir -p "$F360_DATA_DIR"
mkdir -p "$F360_APPS_DIR"
mkdir -p "$F360_BIN_DIR"

# Copy runtime scripts
mkdir -p "$F360_DATA_DIR/runtime-scripts"
cp -r "$SCRIPT_DIR/src/runtime/." "$F360_DATA_DIR/runtime-scripts/"
cp "$SCRIPT_DIR/src/bin/launch-fusion.sh" "$F360_DATA_DIR/"
cp "$SCRIPT_DIR/src/doctor/doctor.sh" "$F360_DATA_DIR/"
cp "$SCRIPT_DIR/Makefile" "$F360_DATA_DIR/" 2>/dev/null || true
chmod +x "$F360_DATA_DIR/launch-fusion.sh" "$F360_DATA_DIR/doctor.sh" "$F360_DATA_DIR/runtime-scripts/"*.sh "$F360_DATA_DIR/runtime-scripts/"*.py 2>/dev/null || true

# Create CLI symlinks
ln -sf "$F360_DATA_DIR/launch-fusion.sh" "$F360_BIN_DIR/launch-fusion"
ln -sf "$F360_DATA_DIR/doctor.sh" "$F360_BIN_DIR/fusion-doctor" 2>/dev/null || true
ln -sf "$F360_DATA_DIR/uninstall.sh" "$F360_BIN_DIR/fusion-uninstall" 2>/dev/null || true

# Install MIME type definitions for Fusion 360 file formats
log_info " Installing MIME types..."
MIME_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/mime"
mkdir -p "$MIME_DIR/packages"
cp "$SCRIPT_DIR/src/install/data/fusion360-mime.xml" "$MIME_DIR/packages/fusion360.xml"
if command -v update-mime-database &>/dev/null; then
  update-mime-database "$MIME_DIR" 2>/dev/null || true
  log_info " MIME database updated."
else
  log_info " update-mime-database not found — MIME types copied but not activated."
fi

log_info " Runtime scripts installed to $F360_DATA_DIR"
log_info " CLI symlinks in $F360_BIN_DIR: launch-fusion, fusion360, fusion-doctor, fusion-uninstall"
