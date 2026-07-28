# doctor/40-fusion.sh — Fusion Installation checks (incl. critical DLLs)

header "4. Fusion Installation"

fusion_exe=""
if [[ -d "$PFX_DIR" ]]; then
  fusion_exe=$(find "$PFX_DIR" -name Fusion360.exe -type f -print 2>/dev/null | head -1 || true)
fi

if [[ -n "$fusion_exe" ]]; then
  pass "Fusion360.exe found"
  detail "$fusion_exe"
  exe_size=$(stat -c%s "$fusion_exe" 2>/dev/null || echo "?")
  info "Size: $exe_size bytes"
else
  fail "Fusion360.exe not found — Fusion may not be installed"
fi

production_dir=""
if [[ -n "$fusion_exe" ]]; then
  production_dir="$(dirname "$(dirname "$fusion_exe")")"
  if [[ -n "$production_dir" ]]; then
    pass "Production directory: $production_dir"
  fi
fi

if [[ -d "$PFX_DIR/pfx/drive_c/users/steamuser/AppData/Local/Autodesk/webdeploy/production" ]]; then
  prod_count=$(find "$PFX_DIR/pfx/drive_c/users/steamuser/AppData/Local/Autodesk/webdeploy/production" -maxdepth 2 -name "Fusion360.exe" -type f 2>/dev/null | wc -l)
  if [[ "$prod_count" -gt 1 ]]; then
    warn "Multiple Fusion360.exe copies found ($prod_count) — possible duplicate install"
  fi
fi

if [[ -d "$PFX_DIR" ]]; then
  idmgr=$(find "$PFX_DIR" -name AdskIdentityManager.exe -type f -print 2>/dev/null | head -1 || true)
  if [[ -n "$idmgr" ]]; then
    pass "AdskIdentityManager.exe found"
  else
    warn "AdskIdentityManager.exe not found — sign-in bridge may fail"
  fi
fi

webview_dir="$PFX_DIR/pfx/drive_c/Program Files (x86)/Microsoft/EdgeWebView"
if [[ -d "$webview_dir" ]]; then
  pass "WebView2 runtime installed in prefix"
  webview_size=$(du -sh "$webview_dir" 2>/dev/null | cut -f1)
  info "WebView2 size: $webview_size"
else
  fail "WebView2 runtime not installed — run setup-fusion.sh"
fi

check_dll() {
  local dll="$1"
  local found
  found=$(find "$PFX_DIR/pfx/drive_c/windows/system32" "$PFX_DIR/pfx/drive_c/windows/syswow64" \
    -maxdepth 1 -iname "$dll" -print 2>/dev/null | head -1 || true)
  if [[ -n "$found" ]]; then
    pass "DLL $dll present"
  else
    warn "DLL $dll not found — Fusion may need additional runtime components"
  fi
}
if [[ -d "$PFX_DIR/pfx" ]]; then
  header "4a. Critical DLLs"
  for dll in vcruntime140.dll vcruntime140_1.dll msvcp140.dll concrt140.dll ucrtbase.dll; do
    check_dll "$dll"
  done
fi
