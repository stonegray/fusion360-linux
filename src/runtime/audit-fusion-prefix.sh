#!/usr/bin/env bash
# audit-fusion-prefix.sh: Read-only audit of the Fusion 360 Proton prefix.
set -euo pipefail

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/fusion360-linux/config"
REPORT_FILE="${1:-/tmp/fusion-prefix-audit.txt}"

if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
fi

export STEAM_COMPAT_DATA_PATH
export STEAM_COMPAT_CLIENT_INSTALL_PATH

PFX="$STEAM_COMPAT_DATA_PATH/pfx"
DRIVE_C="$PFX/drive_c"

{
  echo "============================================================"
  echo "Fusion 360 Proton prefix audit"
  echo "timestamp=$(date -Is)"
  echo "============================================================"
  echo

  echo "---- launcher/config paths ----"
  echo "PROTON=$PROTON"
  echo "STEAM_COMPAT_DATA_PATH=$STEAM_COMPAT_DATA_PATH"
  echo "STEAM_COMPAT_CLIENT_INSTALL_PATH=$STEAM_COMPAT_CLIENT_INSTALL_PATH"
  echo "PFX=$PFX"
  echo "DRIVE_C=$DRIVE_C"
  echo "FUSION_ROOT=$FUSION_ROOT"
  echo "BROWSER=$BROWSER"
  echo "CHROME=$CHROME"
  echo

  echo "---- proton path/version-ish ----"
  ls -l "$PROTON" 2>&1
  "$PROTON" --version 2>&1 || true
  echo

  echo "---- prefix basics ----"
  ls -ld "$STEAM_COMPAT_DATA_PATH" "$PFX" "$DRIVE_C" 2>&1
  echo

  echo "---- Fusion executables ----"
  find "$FUSION_ROOT" -maxdepth 5 -type f \( \
    -iname "Fusion360.exe" -o \
    -iname "AdskIdentityManager.exe" -o \
    -iname "*Identity*.exe" -o \
    -iname "*WebView*.exe" -o \
    -iname "*Browser*.exe" \
  \) -print 2>/dev/null | sort
  echo

  echo "---- WebView2 / Edge runtime candidates ----"
  find "$DRIVE_C/Program Files" "$DRIVE_C/Program Files (x86)" "$DRIVE_C/users" -maxdepth 9 \( \
    -iname "msedgewebview2.exe" -o \
    -iname "WebView2Loader.dll" -o \
    -iname "Microsoft.Web.WebView2.Core.dll" -o \
    -iname "*WebView2*" \
  \) -print 2>/dev/null | sort
  echo

  echo "---- common runtime DLLs in system32/syswow64 ----"
  for dll in \
    concrt140.dll \
    d3dcompiler_47.dll \
    d3d11.dll \
    d3d12.dll \
    dxgi.dll \
    mfc140.dll \
    mfc140u.dll \
    mscoree.dll \
    msvcp140.dll \
    msvcp140_1.dll \
    msvcp140_2.dll \
    ucrtbase.dll \
    vcomp140.dll \
    vcruntime140.dll \
    vcruntime140_1.dll \
    webview2loader.dll \
    winhttp.dll \
    wininet.dll \
    wldap32.dll \
    xinput1_4.dll
  do
    printf "%-28s" "$dll"
    found_paths="$(find "$DRIVE_C/windows/system32" "$DRIVE_C/windows/syswow64" -maxdepth 1 -iname "$dll" -print 2>/dev/null | sort | tr '\n' ' ')"
    if [[ -n "$found_paths" ]]; then
      echo "$found_paths"
    else
      echo "MISSING"
    fi
  done
  echo

  echo "---- DLL override registry sections ----"
  grep -n -A160 '^\[Software\\\\Wine\\\\DllOverrides\]' "$PFX/user.reg" "$PFX/system.reg" 2>/dev/null
  echo

  echo "---- AppDefaults registry sections ----"
  grep -n -A100 '^\[Software\\\\Wine\\\\AppDefaults' "$PFX/user.reg" "$PFX/system.reg" 2>/dev/null
  echo

  echo "---- X11 Driver registry section ----"
  grep -n -A80 '^\[Software\\\\Wine\\\\X11 Driver\]' "$PFX/user.reg" "$PFX/system.reg" 2>/dev/null
  echo

  echo "---- WineBrowser registry section ----"
  grep -n -A40 '^\[Software\\\\Wine\\\\WineBrowser\]' "$PFX/user.reg" "$PFX/system.reg" 2>/dev/null
  echo

  echo "---- uninstall registry display names ----"
  grep -h -A25 -E '^\[Software\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Uninstall|^\[Software\\\\Wow6432Node\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Uninstall' \
    "$PFX/user.reg" "$PFX/system.reg" 2>/dev/null \
    | grep -E '"DisplayName"=|"DisplayVersion"=' \
    | sed 's/^/  /'
  echo

  echo "---- recent Autodesk logs ----"
  find "$DRIVE_C/users" -path "*Autodesk*" -type f \( \
    -iname "*.log" -o \
    -iname "*.txt" \
  \) -printf '%TY-%Tm-%Td %TH:%TM %p\n' 2>/dev/null \
    | sort \
    | tail -n 120
  echo

  echo "---- recent Autodesk log errors/warnings ----"
  find "$DRIVE_C/users" -path "*Autodesk*" -type f \( \
    -iname "*.log" -o \
    -iname "*.txt" \
  \) -print0 2>/dev/null \
    | xargs -0 grep -I -n -E 'error|failed|missing|dll|module|exception|webview|cef|chrom|identity|oauth|browser|qt|qml|sidebar|project|data panel' 2>/dev/null \
    | tail -n 300
  echo

  echo "---- host tools ----"
  for tool in winetricks protontricks cabextract 7z unzip vulkaninfo glxinfo wmctrl xdotool xprop xrandr xdpyinfo; do
    printf "%-14s" "$tool"
    command -v "$tool" || echo "MISSING"
  done
  echo

  echo "---- host Vulkan ICD files ----"
  ls -1 /usr/share/vulkan/icd.d 2>/dev/null
  echo

  echo "============================================================"
  echo "End of audit"
  echo "============================================================"
} > "$REPORT_FILE" 2>&1

echo "$REPORT_FILE"