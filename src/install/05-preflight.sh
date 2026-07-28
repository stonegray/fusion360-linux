# src/install/05-preflight.sh — System preflight checks
log_info " Running preflight checks..."
log_info " Detecting operating system..."
detect_distro
log_info " Distro: ${ID:-unknown} — using: $INSTALL_CMD"
log_info " Checking display, disk, and permissions..."
pre_flight
log_info " Preflight passed."
