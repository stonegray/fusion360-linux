# src/install/20-ge-proton.sh — Download and extract GE-Proton
mkdir -p "$COMPAT_DIR"
existing="$(find_proton "$COMPAT_DIR")"
if [[ -n "$existing" ]]; then
  log_info " GE-Proton already installed: $(dirname "$existing")"
  return 0 2>/dev/null || true
fi

# Check available disk space — GE-Proton is ~500MB compressed, ~1.5GB extracted
_check_space() {
  local dir="$1" needed_mb="$2" label="$3"
  local avail_mb
  avail_mb=$(df -m "$dir" 2>/dev/null | awk 'NR==2 {print $4}') || true
  if [[ -z "$avail_mb" ]] || [[ "$avail_mb" -lt "$needed_mb" ]]; then
    log_fail " Not enough space in $label ($dir): need ${needed_mb}MB, have ${avail_mb:-?}MB."
    log_info " Free space and try again, or set a larger tmpdir."
    return 1
  fi
}
_check_space "/tmp" 2500 "/tmp (download + extraction)" || return 1 2>/dev/null || true
_check_space "$COMPAT_DIR" 2000 "$COMPAT_DIR (extraction target)" || return 1 2>/dev/null || true

local tarball; tarball="$(mktemp -t fusion360-ge-proton.XXXX).tar.gz"
if [[ ! -f "$tarball" ]]; then
  log_info " Downloading ${GE_PROTON_VERSION} (~500MB)..."
  wget --timeout=30 -c -O "$tarball" "$GE_PROTON_URL"
else
  log_info " Already downloaded: $tarball"
fi

if ! tar -tzf "$tarball" &>/dev/null; then
  log_info " Download corrupted, re-downloading..."
  rm -f "$tarball"
  wget --timeout=30 -c -O "$tarball" "$GE_PROTON_URL"
  tar -tzf "$tarball" &>/dev/null || {
    log_info " Download still corrupted after retry." >&2
    return 1
  }
fi

log_info " Extracting..."
tar -xf "$tarball" -C "$COMPAT_DIR"
log_info " Done: $COMPAT_DIR/$GE_PROTON_VERSION/proton"
