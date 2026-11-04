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

# Runtime helpers built at install time by 26-runtime-patches.sh. Nothing is
# shipped prebuilt, so a missing or source-newer-than-binary artifact means
# the last install did not finish that step — Fusion then silently falls back
# to stock Wine behaviour.
shim_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/fusion360-linux/config"

# helper: stale_or_missing <artifact> <newest source> <label> <remedy-hint>
check_helper() {
  local artifact="$1" src="$2" label="$3" hint="$4"
  if [[ ! -f "$artifact" ]]; then
    warn "$label is missing — run ./install.sh"
    ((stuck_found++)) || true
  elif [[ -f "$src" && "$src" -nt "$artifact" ]]; then
    warn "$label is older than its source — rebuild with ./install.sh"
    ((stuck_found++)) || true
  else
    pass "$label present and up to date"
  fi
}

nd_dir="$F360_DATA_DIR/native-dialogs"
shim_wanted=0
[[ -f "$shim_cfg" ]] && grep -qE '^FUSION_NATIVE_DIALOGS=1' "$shim_cfg" && shim_wanted=1

if [[ $shim_wanted -eq 1 ]]; then
  # dlgshim.dll depends on all three sources, so compare against the newest.
  newest_src=""
  for f in "$nd_dir"/comdlg32.c "$nd_dir"/dialog_com.c "$nd_dir"/shim_log.c; do
    if [[ -f "$f" && ( -z "$newest_src" || "$f" -nt "$newest_src" ) ]]; then newest_src="$f"; fi
  done
  check_helper "$nd_dir/dlgshim.dll" "$newest_src" "Native dialog shim" ""
  if [[ ! -x "$nd_dir/hostrunner" ]]; then
    warn "hostrunner is missing — native dialogs will fail to pick files"
    ((stuck_found++)) || true
  fi
  command -v kdialog &>/dev/null || warn "kdialog not installed — native dialogs will not appear"
fi

twf_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/fusion360-linux/config"
twf_wanted=0
[[ -f "$twf_cfg" ]] && grep -qE '^FUSION_ENABLE_TOOLWINDOW_FIXER=1' "$twf_cfg" && twf_wanted=1
if [[ $twf_wanted -eq 1 ]]; then
  check_helper "$F360_DATA_DIR/toolwindow-fixer/fusion-toolwindow-fixer.exe" \
               "$SCRIPT_DIR/../toolwindow-fixer/fusion-toolwindow-fixer.c" \
               "Toolwindow fixer" ""
fi
