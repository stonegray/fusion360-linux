# src/doctor/80-logs.sh — Log File checks

header "8. Log Files"

if [[ -d "$PFX_DIR" ]]; then
  fusion_logs=$(find "$PFX_DIR/pfx/drive_c/users" -path "*Autodesk*" -type f \( -name "*.log" -o -name "*.txt" \) 2>/dev/null)
  log_count=$(echo "$fusion_logs" | grep -c . 2>/dev/null || echo 0)
  if [[ "$log_count" -gt 0 ]]; then
    pass "$log_count Fusion log file(s) found"
    newest_log=$(echo "$fusion_logs" | sort | tail -1)
    info "Newest: $newest_log"
    recent_errors=$(tail -20 "$newest_log" 2>/dev/null | grep -i 'error\|fail\|exception\|crash\|stack' | head -10 || true)
    if [[ -n "$recent_errors" ]]; then
      warn "Recent errors in newest log:"
      echo "$recent_errors" | sed 's/^/    /'
    fi
  else
    info "No Fusion log files found (expected if Fusion hasn't been run)"
  fi
fi

bridge_log="/tmp/fusion-browser-bridge.log"
if [[ -f "$bridge_log" ]]; then
  bridge_size=$(stat -c%s "$bridge_log" 2>/dev/null || echo "?")
  pass "Browser bridge log exists ($bridge_size bytes)"
  bridge_errors=$(grep -i 'error\|fail\|exception' "$bridge_log" 2>/dev/null | head -5 || true)
  if [[ -n "$bridge_errors" ]]; then
    warn "Errors in bridge log:"
    echo "$bridge_errors" | sed 's/^/    /'
  fi
else
  info "Browser bridge log not found (created when Fusion is launched)"
fi

winebrowser_log="/tmp/fusion360-winebrowser-register.log"
if [[ -f "$winebrowser_log" ]]; then
  if grep -qi 'error\|fail' "$winebrowser_log" 2>/dev/null; then
    warn "WineBrowser registration had errors:"
    cat "$winebrowser_log" | sed 's/^/    /'
  else
    pass "WineBrowser registration log clean"
  fi
fi

dpi_log="/tmp/fusion360-dpi.log"
if [[ -f "$dpi_log" ]]; then
  info "DPI log exists (contents below)"
  tail -5 "$dpi_log" | sed 's/^/  /'
fi
