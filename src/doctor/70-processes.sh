# src/doctor/70-processes.sh — Running Process checks

header "7. Running Processes"

fusion_procs=$(pgrep -af 'Fusion360|AdskIdentity|Adsk|AdSSO|CefSharp' 2>/dev/null || true)
if [[ -n "$fusion_procs" ]]; then
  pass "Fusion/Autodesk processes found"
  echo "$fusion_procs" | sed 's/^/  /'
else
  info "No Fusion/Autodesk processes running"
fi

wine_procs=$(pgrep -af 'wine|wineserver|wine64|wine64-preloader|wine-preloader' 2>/dev/null || true)
if [[ -n "$wine_procs" ]]; then
  wine_count=$(echo "$wine_procs" | wc -l)
  pass "Wine/Proton processes: $wine_count running"
  echo "$wine_procs" | head -5 | sed 's/^/  /'
  if [[ $(echo "$wine_procs" | wc -l) -gt 5 ]]; then
    detail "... and $(($(echo "$wine_procs" | wc -l) - 5)) more"
  fi
else
  info "No Wine/Proton processes running"
fi

if pgrep -x wineserver &>/dev/null; then
  pass "wineserver is running"
  ws_pid=$(pgrep -x wineserver)
  ws_age=$(ps -o etimes= -p "$ws_pid" 2>/dev/null | tr -d ' ' || echo "?")
  info "  wineserver PID $ws_pid, running for ${ws_age}s"
fi

listener_procs=$(pgrep -af 'fusion-browser-listener' 2>/dev/null || true)
if [[ -n "$listener_procs" ]]; then
  pass "fusion-browser-listener is running"
  echo "$listener_procs" | sed 's/^/  /'
else
  info "fusion-browser-listener not running (starts with launch-fusion.sh)"
fi

overlay_procs=$(pgrep -af 'fusion-gray-overlay' 2>/dev/null || true)
if [[ -n "$overlay_procs" ]]; then
  pass "fusion-gray-overlay-event-killer is running"
  echo "$overlay_procs" | sed 's/^/  /'
else
  info "fusion-gray-overlay-event-killer not running (starts with launch-fusion.sh)"
fi

toolwindow_procs=$(pgrep -af 'fusion-toolwindow-fixer' 2>/dev/null || true)
if [[ -n "$toolwindow_procs" ]]; then
  pass "fusion-toolwindow-fixer.exe is running"
  echo "$toolwindow_procs" | sed 's/^/  /'
else
  info "fusion-toolwindow-fixer.exe not running (starts with launch-fusion.sh)"
fi
