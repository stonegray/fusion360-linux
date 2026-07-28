#!/usr/bin/env bash
# doctor.sh — Comprehensive diagnostic for Fusion360 on Linux
#
# Checks environment, dependencies, installation state, running processes,
# log files, and potential stuck-install indicators. Produces a full report
# users can share when asking for help.
#
# Usage:
#   ./doctor.sh              # print report
#   ./doctor.sh --save       # save report to /tmp/fusion360-doctor-<timestamp>.txt
#   ./doctor.sh --quick      # condensed summary only

set -uo pipefail

SAVE="${1:-}"
QUICK=false
REPORT_FILE=""

if [[ "$SAVE" == "--save" ]]; then
  REPORT_FILE="/tmp/fusion360-doctor-$(date +%Y%m%d-%H%M%S).txt"
elif [[ "$SAVE" == "--quick" ]]; then
  QUICK=true
fi

# ── Output helpers ───────────────────────────────────────────────────
SECTION_PASS=0
SECTION_FAIL=0
SECTION_WARN=0
RECOMMENDATIONS=()

emit()  { echo -e "$*"; }
header() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $*"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}
pass()  { echo "  [PASS] $*"; ((SECTION_PASS++)); }
fail()  { echo "  [FAIL] $*"; ((SECTION_FAIL++)); RECOMMENDATIONS+=("$*"); }
warn()  { echo "  [WARN] $*"; ((SECTION_WARN++)); }
info()  { echo "  [INFO] $*"; }
detail(){ echo "         $*"; }

# ── Write to file if --save ──────────────────────────────────────────
if [[ -n "$REPORT_FILE" ]]; then
  exec > >(tee "$REPORT_FILE") 2>&1
fi

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     Fusion360 on Linux — Doctor Report                      ║"
echo "║     $(date)                ║"
echo "╚══════════════════════════════════════════════════════════════╝"

# ═════════════════════════════════════════════════════════════════════
# 1. SYSTEM ENVIRONMENT
# ═════════════════════════════════════════════════════════════════════
header "1. System Environment"

# OS release
if [[ -f /etc/os-release ]]; then
  source /etc/os-release
  info "Distro:    $PRETTY_NAME"
  info "ID:        $ID"
  info "Version:   ${VERSION_ID:-unknown}"
else
  warn "No /etc/os-release found."
fi

# Kernel
info "Kernel:    $(uname -sr)"
info "Arch:      $(uname -m)"

# Desktop environment
info "Desktop:   ${XDG_CURRENT_DESKTOP:-unknown}"
info "Session:   ${XDG_SESSION_TYPE:-unknown}"
info "Session ID: ${XDG_SESSION_ID:-unknown}"

# Display server
if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
  info "Display:   Wayland ($WAYLAND_DISPLAY)"
elif [[ -n "${DISPLAY:-}" ]]; then
  info "Display:   X11 ($DISPLAY)"
else
  fail "No display server detected (DISPLAY and WAYLAND_DISPLAY both unset)."
fi

# KDE session version
if [[ -n "${KDE_SESSION_VERSION:-}" ]]; then
  info "KDE ver:   $KDE_SESSION_VERSION"
fi

# DBus
if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
  info "DBus:      ${DBUS_SESSION_BUS_ADDRESS:0:60}..."
else
  warn "DBUS_SESSION_BUS_ADDRESS not set — protocol handlers may fail."
fi

# XDG_RUNTIME_DIR
if [[ -d "${XDG_RUNTIME_DIR:-}" ]]; then
  info "XDG_RUNTIME_DIR: $XDG_RUNTIME_DIR"
else
  warn "XDG_RUNTIME_DIR not set or missing — browser bridge may fail."
fi

# Home partition type
if command -v df &>/dev/null; then
  info "Home FS:   $(df -T "$HOME" | tail -1 | awk '{print $2}')"
fi

if [[ "$QUICK" == true ]]; then
  echo ""
  echo "── Quick Summary ──"
  echo "  Pass: $SECTION_PASS  Fail: $SECTION_FAIL  Warn: $SECTION_WARN"
  echo ""
  if [[ ${#RECOMMENDATIONS[@]} -gt 0 ]]; then
    echo "  Issues found:"
    for r in "${RECOMMENDATIONS[@]}"; do echo "    - $r"; done
  fi
  exit $(( SECTION_FAIL > 0 ? 1 : 0 ))
fi

# ═════════════════════════════════════════════════════════════════════
# 2. DEPENDENCIES (system packages)
# ═════════════════════════════════════════════════════════════════════
header "2. System Dependencies"

DEPS=(icoutils zenity cabextract wget xdg-utils desktop-file-utils)
DESIRED=(icoutils zenity python3-tk cabextract wget xdg-utils desktop-file-utils)

# Detect package manager
PKG_MGR=""
if command -v apt-get &>/dev/null; then
  PKG_MGR="apt-get"
elif command -v dnf &>/dev/null; then
  PKG_MGR="dnf"
elif command -v pacman &>/dev/null; then
  PKG_MGR="pacman"
elif command -v zypper &>/dev/null; then
  PKG_MGR="zypper"
fi
info "Package manager: ${PKG_MGR:-unknown}"

# Check each dep by looking for key binaries
check_dep() {
  local bin="$1" pkg="$2"
  if command -v "$bin" &>/dev/null; then
    pass "$pkg ($bin found)"
  else
    fail "$pkg ($bin not found)"
  fi
}

check_dep wrestool "icoutils"
check_dep zenity  "zenity"
check_dep cabextract "cabextract"
check_dep wget    "wget"
check_dep xdg-open "xdg-utils"
check_dep desktop-file-validate "desktop-file-utils"

# python3-tk (may not have a binary, check import)
if python3 -c "import tkinter" &>/dev/null 2>&1; then
  pass "python3-tk (tkinter import OK)"
else
  fail "python3-tk (tkinter import failed — launcher-config GUI needs this)"
fi

# ImageMagick convert (for icon extraction, installed optionally)
if command -v convert &>/dev/null; then
  pass "imagemagick (convert found) — icon extraction available"
fi

# Check for Vulkan ICD
vk_icd_count=$(find /usr/share/vulkan/icd.d/ -name '*.json' 2>/dev/null | wc -l)
if [[ "$vk_icd_count" -gt 0 ]]; then
  info "Vulkan ICD: $vk_icd_count file(s) found"
  ls /usr/share/vulkan/icd.d/ 2>/dev/null | sed 's/^/             /'
else
  warn "No Vulkan ICD files found — Fusion may fall back to software rendering"
fi

# ═════════════════════════════════════════════════════════════════════
# 3. PROTON & PREFIX
# ═════════════════════════════════════════════════════════════════════
header "3. Proton & Prefix"

COMPAT_DIR="$HOME/.local/share/Steam/compatibilitytools.d"
PFX_DIR="$HOME/.fusion360-proton2"

# GE-Proton
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
    # Try to get version
    ver=$("$p" --version 2>/dev/null | head -1 || echo "version unknown")
    detail "  → $ver"
  done
fi

# Proton prefix
if [[ -d "$PFX_DIR/pfx" ]]; then
  pass "Proton prefix exists at $PFX_DIR"
  pfx_size=$(du -sh "$PFX_DIR" 2>/dev/null | cut -f1)
  info "Prefix size: $pfx_size"
  if [[ -d "$PFX_DIR" ]]; then
    fail "Proton prefix directory exists but has no pfx/ — install may be incomplete"
  else
    fail "Proton prefix directory $PFX_DIR does not exist — run Phase 2 installer"
  fi
fi

# Check for wineserver lock files (stuck install indicator)
ws_lock=$(find "$PFX_DIR" -name '.wineserver.lock' -type f 2>/dev/null | head -1 || true)
if [[ -n "$ws_lock" ]]; then
  warn "Wineserver lock file found ($ws_lock) — may indicate unclean shutdown"
fi

# Check for leftover setup lock files
setup_lock=$(find "$PFX_DIR" -name 'setup*lock*' -o -name 'install*lock*' 2>/dev/null | head -1 || true)
if [[ -n "$setup_lock" ]]; then
  warn "Setup lock file found ($setup_lock) — installer may have been interrupted"
fi

# ═════════════════════════════════════════════════════════════════════
# 4. FUSION INSTALLATION
# ═════════════════════════════════════════════════════════════════════
header "4. Fusion Installation"

# Fusion360.exe
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

# Production directory
production_dir=""
if [[ -n "$fusion_exe" ]]; then
  # Navigate up from Fusion360.exe to find production dir
  production_dir="$(dirname "$(dirname "$fusion_exe")")"
  if [[ -n "$production_dir" ]]; then
    pass "Production directory: $production_dir"
  fi
fi

# Check for multiple versions (stuck install indicator)
if [[ -d "$PFX_DIR/pfx/drive_c/users/steamuser/AppData/Local/Autodesk/webdeploy/production" ]]; then
  prod_count=$(find "$PFX_DIR/pfx/drive_c/users/steamuser/AppData/Local/Autodesk/webdeploy/production" -maxdepth 2 -name "Fusion360.exe" -type f 2>/dev/null | wc -l)
  if [[ "$prod_count" -gt 1 ]]; then
    warn "Multiple Fusion360.exe copies found ($prod_count) — possible duplicate install"
  fi
fi

# AdskIdentityManager.exe
if [[ -d "$PFX_DIR" ]]; then
  idmgr=$(find "$PFX_DIR" -name AdskIdentityManager.exe -type f -print 2>/dev/null | head -1 || true)
  if [[ -n "$idmgr" ]]; then
    pass "AdskIdentityManager.exe found"
  else
    warn "AdskIdentityManager.exe not found — sign-in bridge may fail"
  fi
fi

# WebView2
webview_dir="$PFX_DIR/pfx/drive_c/Program Files (x86)/Microsoft/EdgeWebView"
if [[ -d "$webview_dir" ]]; then
  pass "WebView2 runtime installed in prefix"
  webview_size=$(du -sh "$webview_dir" 2>/dev/null | cut -f1)
  info "WebView2 size: $webview_size"
else
  fail "WebView2 runtime not installed — run setup-fusion.sh"
fi

# Critical DLL check
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

# ═════════════════════════════════════════════════════════════════════
# 5. CONFIGURATION
# ═════════════════════════════════════════════════════════════════════
header "5. Configuration"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fusion360-linux"
CONFIG_FILE="$CONFIG_DIR/config"

if [[ -f "$CONFIG_FILE" ]]; then
  pass "Config file exists: $CONFIG_FILE"
  # Source it to validate
  if source "$CONFIG_FILE" 2>/dev/null; then
    pass "Config file parses correctly"
  else
    fail "Config file has syntax errors"
  fi

  # Validate key paths from config
  info "Checking config paths..."
  for var_name in PROTON STEAM_COMPAT_DATA_PATH FUSION_ROOT BROWSER CHROME; do
    val="${!var_name:-}"
    if [[ -z "$val" ]]; then
      warn "$var_name is not set in config"
    elif [[ -e "$val" ]]; then
      pass "Config $var_name → $val"
    else
      fail "Config $var_name points to missing path: $val"
    fi
  done
  for var_name in BROWSER_LISTENER CALLBACK_HANDLER FUSION_OVERLAY_KILLER; do
    val="${!var_name:-}"
    if [[ -z "$val" ]]; then
      warn "$var_name is not set in config"
    elif [[ -x "$val" ]]; then
      pass "Config $var_name → $val (executable)"
    elif [[ -f "$val" ]]; then
      warn "Config $var_name exists but is not executable: $val"
    else
      fail "Config $var_name missing: $val"
    fi
  done
else
  fail "Config file not found — run setup-fusion.sh or launch-fusion.sh --configure"
fi

# Desktop entries
app_dir="$HOME/.local/share/applications"
if [[ -f "$app_dir/fusion360-callback-handler.desktop" ]]; then
  pass "Callback handler desktop entry installed"
  if command -v desktop-file-validate &>/dev/null; then
    desktop-file-validate "$app_dir/fusion360-callback-handler.desktop" 2>/dev/null && \
      pass "Callback desktop entry validates" || \
      warn "Callback desktop entry has validation issues"
  fi
else
  fail "Callback handler desktop entry missing — run setup-fusion.sh"
fi

if [[ -f "$app_dir/autodesk-fusion360.desktop" ]]; then
  pass "Fusion360 desktop entry installed"
  if command -v desktop-file-validate &>/dev/null; then
    desktop-file-validate "$app_dir/autodesk-fusion360.desktop" 2>/dev/null && \
      pass "Fusion360 desktop entry validates" || \
      warn "Fusion360 desktop entry has validation issues"
  fi
else
  fail "Fusion360 desktop entry missing — run setup-fusion.sh"
fi

# Protocol handlers
for scheme in adsk adskidmgr; do
  handler=$(xdg-mime query default "x-scheme-handler/$scheme" 2>/dev/null || true)
  if echo "$handler" | grep -qi "fusion360-callback-handler"; then
    pass "$scheme:// protocol → $handler"
  else
    fail "$scheme:// protocol not registered (current: ${handler:-none})"
  fi
done

# Icons
icon_found=0
for size in 16 22 24 32 48 64 72 96 128 192 256 512; do
  icon_path="$HOME/.local/share/icons/hicolor/${size}x${size}/apps/fusion360.png"
  if [[ -f "$icon_path" ]]; then
    icon_found=1
    break
  fi
done
if [[ $icon_found -eq 1 ]]; then
  pass "Application icons installed"
else
  warn "Application icons not installed — run setup-fusion.sh"
fi

# ═════════════════════════════════════════════════════════════════════
# 6. BRIDGE INFRASTRUCTURE
# ═════════════════════════════════════════════════════════════════════
header "6. Bridge Infrastructure"

BRIDGE_DIRS=(
  "/tmp/fusion360-browser-requests"
  "/tmp/fusion360-browser-processed"
  "/tmp/fusion360-callback-requests"
  "/tmp/fusion360-callback-processed"
)

all_bridge_ok=1
for d in "${BRIDGE_DIRS[@]}"; do
  if [[ -d "$d" ]]; then
    pass "Bridge dir $d exists"
    # Check for stale files
    stale_count=$(find "$d" -type f -mmin +60 2>/dev/null | wc -l)
    if [[ "$stale_count" -gt 0 ]]; then
      warn "  $stale_count stale file(s) older than 1 hour in $d"
    fi
  else
    # Bridge dirs are created at launch; doesn't exist yet is OK
    info "Bridge dir $d does not exist (will be created on next launch)"
    all_bridge_ok=0
  fi
done

# Check /tmp disk space for bridge
tmp_avail_kb=$(df --output=avail /tmp 2>/dev/null | tail -n1)
tmp_avail_mb=$((tmp_avail_kb / 1024))
info "/tmp available: ${tmp_avail_mb}MB"

# ═════════════════════════════════════════════════════════════════════
# 7. RUNNING PROCESSES
# ═════════════════════════════════════════════════════════════════════
header "7. Running Processes"

# Fusion/ Autodesk processes
fusion_procs=$(pgrep -af 'Fusion360|AdskIdentity|Adsk|AdSSO|CefSharp' 2>/dev/null || true)
if [[ -n "$fusion_procs" ]]; then
  pass "Fusion/Autodesk processes found"
  echo "$fusion_procs" | sed 's/^/  /'
else
  info "No Fusion/Autodesk processes running"
fi

# Wine/Proton processes
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

# Check for wineserver specifically
if pgrep -x wineserver &>/dev/null; then
  pass "wineserver is running"
  ws_pid=$(pgrep -x wineserver)
  ws_age=$(ps -o etimes= -p "$ws_pid" 2>/dev/null | tr -d ' ' || echo "?")
  info "  wineserver PID $ws_pid, running for ${ws_age}s"
fi

# Browser listener
listener_procs=$(pgrep -af 'fusion-browser-listener' 2>/dev/null || true)
if [[ -n "$listener_procs" ]]; then
  pass "fusion-browser-listener is running"
  echo "$listener_procs" | sed 's/^/  /'
else
  info "fusion-browser-listener not running (starts with launch-fusion.sh)"
fi

# Overlay killer
overlay_procs=$(pgrep -af 'fusion-gray-overlay' 2>/dev/null || true)
if [[ -n "$overlay_procs" ]]; then
  pass "fusion-gray-overlay-event-killer is running"
  echo "$overlay_procs" | sed 's/^/  /'
else
  info "fusion-gray-overlay-event-killer not running (starts with launch-fusion.sh)"
fi

# ═════════════════════════════════════════════════════════════════════
# 8. LOG FILES
# ═════════════════════════════════════════════════════════════════════
header "8. Log Files"

# Fusion logs
if [[ -d "$PFX_DIR" ]]; then
  fusion_logs=$(find "$PFX_DIR/pfx/drive_c/users" -path "*Autodesk*" -type f \( -name "*.log" -o -name "*.txt" \) 2>/dev/null)
  log_count=$(echo "$fusion_logs" | grep -c . 2>/dev/null || echo 0)
  if [[ "$log_count" -gt 0 ]]; then
    pass "$log_count Fusion log file(s) found"
    newest_log=$(echo "$fusion_logs" | sort | tail -1)
    info "Newest: $newest_log"
    # Check last 10 lines for errors
    recent_errors=$(tail -20 "$newest_log" 2>/dev/null | grep -i 'error\|fail\|exception\|crash\|stack' | head -10 || true)
    if [[ -n "$recent_errors" ]]; then
      warn "Recent errors in newest log:"
      echo "$recent_errors" | sed 's/^/    /'
    fi
  else
    info "No Fusion log files found (expected if Fusion hasn't been run)"
  fi
fi

# Check bridge log
bridge_log="/tmp/fusion-browser-bridge.log"
if [[ -f "$bridge_log" ]]; then
  bridge_size=$(stat -c%s "$bridge_log" 2>/dev/null || echo "?")
  pass "Browser bridge log exists ($bridge_size bytes)"
  # Check for errors in bridge log
  bridge_errors=$(grep -i 'error\|fail\|exception' "$bridge_log" 2>/dev/null | head -5 || true)
  if [[ -n "$bridge_errors" ]]; then
    warn "Errors in bridge log:"
    echo "$bridge_errors" | sed 's/^/    /'
  fi
else
  info "Browser bridge log not found (created when Fusion is launched)"
fi

# WineBrowser registration log
winebrowser_log="/tmp/fusion360-winebrowser-register.log"
if [[ -f "$winebrowser_log" ]]; then
  if grep -qi 'error\|fail' "$winebrowser_log" 2>/dev/null; then
    warn "WineBrowser registration had errors:"
    cat "$winebrowser_log" | sed 's/^/    /'
  else
    pass "WineBrowser registration log clean"
  fi
fi

# DPI log
dpi_log="/tmp/fusion360-dpi.log"
if [[ -f "$dpi_log" ]]; then
  info "DPI log exists (contents below)"
  tail -5 "$dpi_log" | sed 's/^/  /'
fi

# ═════════════════════════════════════════════════════════════════════
# 9. STUCK INSTALL INDICATORS
# ═════════════════════════════════════════════════════════════════════
header "9. Stuck Install Indicators"

stuck_found=0

# Indicator: GE-Proton downloaded but not extracted?
for tgz in "$HOME"/Downloads/GE-Proton*.tar.gz "$HOME"/Downloads/proton-ge*.tar.gz; do
  if [[ -f "$tgz" ]]; then
    warn "GE-Proton archive found but possibly not extracted: $tgz"
    ((stuck_found++)) || true
  fi
done

# Indicator: WebView2 bootstrapper downloaded but not installed
bootstrap="/tmp/MicrosoftEdgeWebview2Setup.exe"
if [[ -f "$bootstrap" ]]; then
  if [[ ! -d "$webview_dir" ]]; then
    warn "WebView2 bootstrapper downloaded but runtime not installed yet — run setup-fusion.sh"
    ((stuck_found++)) || true
  fi
fi

# Indicator: Installer exe present in Downloads but not run
installer_exe=$(find "$HOME/Downloads" -name 'FusionClientDownloader.exe' -type f 2>/dev/null | head -1 || true)
if [[ -n "$installer_exe" && -z "${fusion_exe:-}" ]]; then
  warn "Installer downloaded ($installer_exe) but Fusion360.exe not found in prefix — Phase 2 may not have completed"
  ((stuck_found++)) || true
fi

# Indicator: Partial prefix with no Fusion installation
if [[ -d "$PFX_DIR/pfx" ]]; then
  pfx_file_count=$(find "$PFX_DIR/pfx" -type f 2>/dev/null | wc -l)
  if [[ "$pfx_file_count" -lt 50 ]]; then
    warn "Prefix has only $pfx_file_count files — likely incomplete install"
    ((stuck_found++)) || true
  fi
  # Check for the "New version downloaded" staging directory
  staging=$(find "$PFX_DIR" -path "*webdeploy/staging*" -type d 2>/dev/null | head -1 || true)
  if [[ -n "$staging" ]]; then
    warn "Staging directory found ($staging) — may indicate interrupted update"
    ((stuck_found++)) || true
  fi
fi

# Indicator: Runtime DLLs missing (common stuck-install sign)
if [[ -d "$PFX_DIR/pfx" ]]; then
  for critical_dll in vcruntime140.dll msvcp140.dll; do
    if ! find "$PFX_DIR/pfx/drive_c/windows/system32" -maxdepth 1 -iname "$critical_dll" -print 2>/dev/null | grep -q .; then
      warn "Critical DLL $critical_dll missing — Windows runtime components may not be installed"
      ((stuck_found++)) || true
      break
    fi
  done
fi

# Indicator: Invalid config values (paths pointing inside /tmp from old setup)
if [[ -f "$CONFIG_FILE" ]]; then
  if grep -q '/tmp/' "$CONFIG_FILE" 2>/dev/null; then
    warn "Config references /tmp/ paths — should point to persistent repo location"
    ((stuck_found++)) || true
  fi
fi

if [[ $stuck_found -eq 0 ]]; then
  pass "No stuck-install indicators detected"
fi

# ═════════════════════════════════════════════════════════════════════
# 10. NETWORK
# ═════════════════════════════════════════════════════════════════════
header "10. Network"

# Quick connectivity check (non-blocking, single attempt each)
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

# ═════════════════════════════════════════════════════════════════════
# SUMMARY
# ═════════════════════════════════════════════════════════════════════
header "Summary"
echo "  Passed checks:  $SECTION_PASS"
echo "  Failed checks:  $SECTION_FAIL"
echo "  Warnings:       $SECTION_WARN"
echo ""

if [[ ${#RECOMMENDATIONS[@]} -gt 0 ]]; then
  echo "  ┌── Recommendations ──"
  for r in "${RECOMMENDATIONS[@]}"; do
    echo "  │ $r"
  done
  echo "  └─────────────────────"
  echo ""
fi

if [[ $SECTION_FAIL -eq 0 ]]; then
  echo "  ✓ All critical checks passed. Fusion360 should be ready to launch."
  exit 0
elif [[ $SECTION_FAIL -lt 3 ]]; then
  echo "  △ $SECTION_FAIL minor issue(s). Likely launchable but some features may be affected."
  exit 1
else
  echo "  ✗ $SECTION_FAIL critical issue(s). Run install.sh and setup-fusion.sh before launching."
  exit 2
fi
