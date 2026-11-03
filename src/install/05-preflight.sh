# src/install/05-preflight.sh — System preflight checks
log_info " Running preflight checks..."
log_info " Detecting operating system..."

# Use share/os.fn's canonical functions
local distro; distro="$(detect_distro)"
INSTALL_CMD="sudo $(distro_install_cmd "$distro")"

# Load distro package list
local distro_file="$SCRIPT_DIR/src/install/distro/${distro}.txt"
[[ ! -f "$distro_file" ]] && distro_file="$SCRIPT_DIR/src/install/distro/generic.txt"
PKGS=$(tr '\n' ' ' < "$distro_file" 2>/dev/null | sed 's/ *$//')

log_info " Distro: $distro — using: $INSTALL_CMD"
log_info " Checking display, disk, and permissions..."
pre_flight
log_info " Preflight passed."
