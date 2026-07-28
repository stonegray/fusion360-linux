# src/install/20-ge-proton.sh — Download and extract GE-Proton
mkdir -p "$COMPAT_DIR"
existing=$(find "$COMPAT_DIR" -name proton -type f 2>/dev/null | head -1 || true)
if [[ -n "$existing" ]]; then
  log_info " GE-Proton already installed: $(dirname "$existing")"
  return 0 2>/dev/null || true
fi

tarball="/tmp/${GE_PROTON_VERSION}.tar.gz"
if [[ ! -f "$tarball" ]]; then
  log_info " Downloading ${GE_PROTON_VERSION} (~500MB)..."
  wget --timeout=30 -O "$tarball" "$GE_PROTON_URL"
else
  log_info " Already downloaded: $tarball"
fi

if ! tar -tzf "$tarball" &>/dev/null; then
  log_info " Download corrupted, re-downloading..."
  rm -f "$tarball"
  wget --timeout=30 -O "$tarball" "$GE_PROTON_URL"
  tar -tzf "$tarball" &>/dev/null || {
    log_info " Download still corrupted after retry." >&2
    return 1
  }
fi

log_info " Extracting..."
tar -xf "$tarball" -C "$COMPAT_DIR"
log_info " Done: $COMPAT_DIR/$GE_PROTON_VERSION/proton"
