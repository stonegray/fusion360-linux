# src/install/38-dpi.sh — Apply DPI registry settings to Wine prefix
# Runs before the Fusion installer so the installer GUI also uses correct DPI.

echo "  [9/12] Applying display DPI settings..."

# Source config to get DPI values (written by step 6)
CONFIG_FILE="$F360_CONFIG_FILE"
if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
fi

if [[ ! -f "$PFX_DIR/pfx/user.reg" ]]; then
  echo "  [9/12] Prefix not yet initialized — skipping DPI config."
  return 0
fi
source "$SCRIPT_DIR/src/runtime/launcher-functions.sh"

STEAM_COMPAT_DATA_PATH="$PFX_DIR"
FUSION_WINE_DPI="${FUSION_WINE_DPI:-144}"
FUSION_WINE_SCALE_PERCENT="${FUSION_WINE_SCALE_PERCENT:-auto}"
FUSION_WINE_DPI_FALLBACK="${FUSION_WINE_DPI_FALLBACK:-144}"
FUSION_WINE_SCALE_FALLBACK_PERCENT="${FUSION_WINE_SCALE_FALLBACK_PERCENT:-150}"
FUSION_DPI_LOG_FILE="/tmp/fusion360-dpi.log"

# For the installer GUI: apply LogPixels only (font DPI scaling)
# Win8DpiScaling is applied at launch time by apply_fusion_wine_dpi
local user_reg="$PFX_DIR/pfx/user.reg"
local dpi_value; dpi_value="$(resolve_fusion_wine_dpi)"
[[ "$dpi_value" =~ ^[0-9]+$ ]] || { echo "  [9/12] Warning: invalid DPI value '$dpi_value'" >&2; return 1; }
local dpi_hex; dpi_hex=$(printf 'dword:%08x' "$dpi_value")

if grep -q '^\[Software\\\\Wine\\\\Fonts\]' "$user_reg" 2>/dev/null; then
  sed -i -e '/^\[Software\\\\Wine\\\\Fonts\]/,/^\[/{/^"LogPixels"/d;}' -e '/^\[Software\\\\Wine\\\\Fonts\]/a "LogPixels"='"$dpi_hex" "$user_reg" || { echo "  [9/12] Warning: failed to write DPI registry" >&2; return 1; }
else
  printf '\n[Software\\Wine\\Fonts]\n#time=1dd1c05750735e4\n"LogPixels"=%s\n' "$dpi_hex" >> "$user_reg"
fi

echo "  [9/12] DPI configured in Wine registry (LogPixels=$dpi_value)."
