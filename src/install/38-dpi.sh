# src/install/38-dpi.sh — Apply DPI registry settings to Wine prefix
# Runs before the Fusion installer so the installer GUI also uses correct DPI.

echo "  [8/11] Applying display DPI settings..."

# Source config to get DPI values (written by step 6)
CONFIG_FILE="$F360_CONFIG_FILE"
if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
fi

if [[ ! -f "$PFX_DIR/pfx/user.reg" ]]; then
  echo "  [8/11] Prefix not yet initialized — skipping DPI config."
  return 0
fi

source "$SCRIPT_DIR/src/runtime/launcher-functions.sh"

STEAM_COMPAT_DATA_PATH="$PFX_DIR"
FUSION_WINE_DPI="${FUSION_WINE_DPI:-144}"
FUSION_WINE_SCALE_PERCENT="${FUSION_WINE_SCALE_PERCENT:-auto}"
FUSION_WINE_DPI_FALLBACK="${FUSION_WINE_DPI_FALLBACK:-144}"
FUSION_WINE_SCALE_FALLBACK_PERCENT="${FUSION_WINE_SCALE_FALLBACK_PERCENT:-150}"
FUSION_DPI_LOG_FILE="/tmp/fusion360-dpi.log"

apply_fusion_wine_dpi

echo "  [8/11] DPI configured in Wine registry."
