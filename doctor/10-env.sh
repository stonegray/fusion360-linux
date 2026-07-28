# doctor/10-env.sh — System Environment checks

header "1. System Environment"

if [[ -f /etc/os-release ]]; then
  source /etc/os-release
  info "Distro:    $PRETTY_NAME"
  info "ID:        $ID"
  info "Version:   ${VERSION_ID:-unknown}"
else
  warn "No /etc/os-release found."
fi

info "Kernel:    $(uname -sr)"
info "Arch:      $(uname -m)"
info "Desktop:   ${XDG_CURRENT_DESKTOP:-unknown}"
info "Session:   ${XDG_SESSION_TYPE:-unknown}"
info "Session ID: ${XDG_SESSION_ID:-unknown}"

if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
  info "Display:   Wayland ($WAYLAND_DISPLAY)"
elif [[ -n "${DISPLAY:-}" ]]; then
  info "Display:   X11 ($DISPLAY)"
else
  fail "No display server detected (DISPLAY and WAYLAND_DISPLAY both unset)."
fi

if [[ -n "${KDE_SESSION_VERSION:-}" ]]; then
  info "KDE ver:   $KDE_SESSION_VERSION"
fi

if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
  info "DBus:      ${DBUS_SESSION_BUS_ADDRESS:0:60}..."
else
  warn "DBUS_SESSION_BUS_ADDRESS not set — protocol handlers may fail."
fi

if [[ -d "${XDG_RUNTIME_DIR:-}" ]]; then
  info "XDG_RUNTIME_DIR: $XDG_RUNTIME_DIR"
else
  warn "XDG_RUNTIME_DIR not set or missing — browser bridge may fail."
fi

if command -v df &>/dev/null; then
  info "Home FS:   $(df -T "$HOME" | tail -1 | awk '{print $2}')"
fi

if [[ "$QUICK" == true ]]; then
  quick_exit
fi
