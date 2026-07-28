# doctor/90-install.sh — Stuck Install Indicator checks

header "9. Stuck Install Indicators"

stuck_found=0

for tgz in "$HOME"/Downloads/GE-Proton*.tar.gz "$HOME"/Downloads/proton-ge*.tar.gz; do
  if [[ -f "$tgz" ]]; then
    warn "GE-Proton archive found but possibly not extracted: $tgz"
    ((stuck_found++)) || true
  fi
done

bootstrap="/tmp/MicrosoftEdgeWebview2Setup.exe"
if [[ -f "$bootstrap" ]]; then
  webview_dir="$PFX_DIR/pfx/drive_c/Program Files (x86)/Microsoft/EdgeWebView"
  if [[ ! -d "$webview_dir" ]]; then
    warn "WebView2 bootstrapper downloaded but runtime not installed yet — run setup-fusion.sh"
    ((stuck_found++)) || true
  fi
fi

installer_exe=$(find "$HOME/Downloads" -name 'FusionClientDownloader.exe' -type f 2>/dev/null | head -1 || true)
if [[ -n "$installer_exe" && -z "${fusion_exe:-}" ]]; then
  warn "Installer downloaded ($installer_exe) but Fusion360.exe not found in prefix — Phase 2 may not have completed"
  ((stuck_found++)) || true
fi

if [[ -d "$PFX_DIR/pfx" ]]; then
  pfx_file_count=$(find "$PFX_DIR/pfx" -type f 2>/dev/null | wc -l)
  if [[ "$pfx_file_count" -lt 50 ]]; then
    warn "Prefix has only $pfx_file_count files — likely incomplete install"
    ((stuck_found++)) || true
  fi
  staging=$(find "$PFX_DIR" -path "*webdeploy/staging*" -type d 2>/dev/null | head -1 || true)
  if [[ -n "$staging" ]]; then
    warn "Staging directory found ($staging) — may indicate interrupted update"
    ((stuck_found++)) || true
  fi
fi

if [[ -d "$PFX_DIR/pfx" ]]; then
  for critical_dll in vcruntime140.dll msvcp140.dll; do
    if ! find "$PFX_DIR/pfx/drive_c/windows/system32" -maxdepth 1 -iname "$critical_dll" -print 2>/dev/null | grep -q .; then
      warn "Critical DLL $critical_dll missing — Windows runtime components may not be installed"
      ((stuck_found++)) || true
      break
    fi
  done
fi

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/fusion360-linux/config"
if [[ -f "$CONFIG_FILE" ]]; then
  if grep -q '/tmp/' "$CONFIG_FILE" 2>/dev/null; then
    warn "Config references /tmp/ paths — should point to persistent repo location"
    ((stuck_found++)) || true
  fi
fi

if [[ $stuck_found -eq 0 ]]; then
  pass "No stuck-install indicators detected"
fi
