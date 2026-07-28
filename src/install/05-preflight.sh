# src/install/05-preflight.sh — System preflight checks
echo "  [2/12] Running preflight checks..."
echo "  [2/12] Detecting operating system..."
detect_distro
echo "  [2/12] Distro: ${ID:-unknown} — using: $INSTALL_CMD"
echo "  [2/12] Checking display, disk, and permissions..."
pre_flight
echo "  [2/12] Preflight passed."
