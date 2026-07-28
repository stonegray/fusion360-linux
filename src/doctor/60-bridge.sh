# src/doctor/60-bridge.sh — Bridge Infrastructure checks

header "6. Bridge Infrastructure"

BRIDGE_DIRS=(
  "/tmp/fusion360-browser-requests"
  "/tmp/fusion360-browser-processed"
  "/tmp/fusion360-callback-requests"
  "/tmp/fusion360-callback-processed"
)

for d in "${BRIDGE_DIRS[@]}"; do
  if [[ -d "$d" ]]; then
    pass "Bridge dir $d exists"
    stale_count=$(find "$d" -type f -mmin +60 2>/dev/null | wc -l)
    if [[ "$stale_count" -gt 0 ]]; then
      warn "  $stale_count stale file(s) older than 1 hour in $d"
    fi
  else
    info "Bridge dir $d does not exist (will be created on next launch)"
  fi
done

tmp_avail_kb=$(df --output=avail /tmp 2>/dev/null | tail -n1)
tmp_avail_mb=$((tmp_avail_kb / 1024))
info "/tmp available: ${tmp_avail_mb}MB"
