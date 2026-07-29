# src/install/39-windows-version.sh — Set Windows build number registry entries
# Spoofs Windows 10 build 19045 so applications checking the version see a
# real Windows 10 build instead of Wine's default (which can confuse
# software that checks CurrentBuild for feature detection).

log_info " Setting Windows build number in registry..."

local wine_bin
wine_bin="$(proton_wine_bin "$proton")"
if [[ ! -x "$wine_bin" ]]; then
  log_info " Warning: Wine binary not found — skipping Windows build number config."
  return 0
fi

local pfx="$PFX_DIR/pfx"
local key="HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion"

_run() { WINEPREFIX="$pfx" "$wine_bin" reg add "$key" /v "$1" /t REG_SZ /d "$2" /f &>/dev/null || true; }

_run CurrentBuild      19045
_run CurrentBuildNumber 19045
_run BuildLabEx        "19045.1.amd64fre.vb_release.191206-1406"
_run EditionID         Professional

log_info " Windows build number configured (19045)."
