# src/install/20-ge-proton.sh — Download and extract GE-Proton
mkdir -p "$COMPAT_DIR"
existing=$(find "$COMPAT_DIR" -name proton -type f 2>/dev/null | head -1 || true)
if [[ -n "$existing" ]]; then
  echo "  [2/5] GE-Proton already installed: $(dirname "$existing")"
  return 0 2>/dev/null || true
fi

tarball="/tmp/${GE_PROTON_VERSION}.tar.gz"
if [[ ! -f "$tarball" ]]; then
  echo "  [2/5] Downloading ${GE_PROTON_VERSION} (~500MB)..."
  wget --timeout=30 -O "$tarball" "$GE_PROTON_URL"
else
  echo "  [2/5] Already downloaded: $tarball"
fi

if ! tar -tzf "$tarball" &>/dev/null; then
  echo "  [GE-Proton] Download corrupted, re-downloading..."
  rm -f "$tarball"
  wget --timeout=30 -O "$tarball" "$GE_PROTON_URL"
  tar -tzf "$tarball" &>/dev/null || {
    echo "  [GE-Proton] Download still corrupted after retry." >&2
    return 1
  }
fi

echo "  [2/5] Extracting..."
tar -xf "$tarball" -C "$COMPAT_DIR"
echo "  [2/5] Done: $COMPAT_DIR/$GE_PROTON_VERSION/proton"
