# doctor/30-proton.sh — Proton & Prefix checks

header "3. Proton & Prefix"

COMPAT_DIR="$HOME/.local/share/Steam/compatibilitytools.d"
PFX_DIR="$HOME/.fusion360-proton2"

proton_bins=()
while IFS= read -r -d '' p; do
  proton_bins+=("$p")
done < <(find "$COMPAT_DIR" -name proton -type f -print0 2>/dev/null || true)

if [[ ${#proton_bins[@]} -eq 0 ]]; then
  fail "GE-Proton — no proton found in $COMPAT_DIR"
else
  pass "GE-Proton — ${#proton_bins[@]} installation(s) found"
  for p in "${proton_bins[@]}"; do
    detail "$p"
    ver=$("$p" --version 2>/dev/null | head -1 || echo "version unknown")
    detail "  → $ver"
  done
fi

if [[ -d "$PFX_DIR/pfx" ]]; then
  pass "Proton prefix exists at $PFX_DIR"
  pfx_size=$(du -sh "$PFX_DIR" 2>/dev/null | cut -f1)
  info "Prefix size: $pfx_size"
else
  if [[ -d "$PFX_DIR" ]]; then
    fail "Proton prefix directory exists but has no pfx/ — install may be incomplete"
  else
    fail "Proton prefix directory $PFX_DIR does not exist — run Phase 2 installer"
  fi
fi

ws_lock=$(find "$PFX_DIR" -name '.wineserver.lock' -type f 2>/dev/null | head -1 || true)
if [[ -n "$ws_lock" ]]; then
  warn "Wineserver lock file found ($ws_lock) — may indicate unclean shutdown"
fi

setup_lock=$(find "$PFX_DIR" -name 'setup*lock*' -o -name 'install*lock*' 2>/dev/null | head -1 || true)
if [[ -n "$setup_lock" ]]; then
  warn "Setup lock file found ($setup_lock) — installer may have been interrupted"
fi
