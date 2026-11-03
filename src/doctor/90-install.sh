# src/doctor/90-install.sh — Stuck Install Indicator checks

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
    warn "WebView2 bootstrapper downloaded but runtime not installed yet — run ./install.sh"
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

# Native dialog shim: built at install time by 26-runtime-patches.sh. A missing
# or stale pair means Fusion silently falls back to Wine's Windows-style dialog
# (or, worse, loads a shim built from different sources).
nd_dir="$F360_DATA_DIR/native-dialogs"
shim_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/fusion360-linux/config"
shim_wanted=0
[[ -f "$shim_cfg" ]] && grep -qE '^FUSION_NATIVE_DIALOGS=1' "$shim_cfg" && shim_wanted=1

if [[ $shim_wanted -eq 1 ]]; then
  if [[ ! -f "$nd_dir/dlgshim.dll" || ! -x "$nd_dir/hostrunner" ]]; then
    warn "Native dialogs enabled but shim is missing from $nd_dir — run ./install.sh"
    ((stuck_found++)) || true
  elif [[ -f "$nd_dir/dlgshim.dll" && -f "$nd_dir/comdlg32.c" ]] &&
       [[ "$nd_dir/comdlg32.c" -nt "$nd_dir/dlgshim.dll" ]]; then
    warn "dlgshim.dll is older than its source — rebuild with ./install.sh"
    ((stuck_found++)) || true
  else
    pass "Native dialog shim present and up to date"
  fi
  command -v kdialog &>/dev/null || warn "kdialog not installed — native dialogs will not appear"
fi
