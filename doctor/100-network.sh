# doctor/100-network.sh — Network connectivity checks

header "10. Network"

if command -v wget &>/dev/null; then
  if wget -q --timeout=5 --spider https://go.microsoft.com/fwlink/p/?LinkId=2124703 2>/dev/null; then
    pass "Can reach Microsoft CDN (WebView2 download)"
  else
    warn "Cannot reach Microsoft CDN — WebView2 install will fail during setup-fusion.sh"
  fi
  if wget -q --timeout=5 --spider https://github.com 2>/dev/null; then
    pass "Can reach GitHub (GE-Proton downloads)"
  else
    warn "Cannot reach GitHub — GE-Proton downloads will fail"
  fi
  if wget -q --timeout=5 --spider https://autodesk.com 2>/dev/null; then
    pass "Can reach Autodesk"
  else
    warn "Cannot reach Autodesk — Fusion login may fail"
  fi
else
  warn "wget not available — skipping network checks"
fi
