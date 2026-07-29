# src/install/38-dpi.sh — Apply DPI registry settings to Wine prefix
# Runs before the Fusion installer so the installer GUI also uses correct DPI.

log_info " Applying display DPI settings..."

# Source config to get DPI values (written by step 6)
CONFIG_FILE="$F360_CONFIG_FILE"
if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
fi

if [[ ! -f "$PFX_DIR/pfx/user.reg" ]]; then
  log_info " Prefix not yet initialized — skipping DPI config."
  return 0
fi
source "$SCRIPT_DIR/src/runtime/launcher-functions.sh"

STEAM_COMPAT_DATA_PATH="$PFX_DIR"
FUSION_WINE_DPI="${FUSION_WINE_DPI:-144}"
FUSION_WINE_SCALE_PERCENT="${FUSION_WINE_SCALE_PERCENT:-auto}"
FUSION_WINE_DPI_FALLBACK="${FUSION_WINE_DPI_FALLBACK:-144}"
FUSION_WINE_SCALE_FALLBACK_PERCENT="${FUSION_WINE_SCALE_FALLBACK_PERCENT:-150}"
FUSION_DPI_LOG_FILE="/tmp/fusion360-dpi.log"

# Find Proton binary and apply DPI via reg add
local proton_bin
proton_bin=$(find_proton "$COMPAT_DIR")
if [[ -n "$proton_bin" ]]; then
  PROTON="$proton_bin" STEAM_COMPAT_DATA_PATH="$PFX_DIR" \
    apply_fusion_wine_dpi 2>/dev/null || true
  log_info " DPI configured in Wine registry."
else
  log_info " Warning: Proton not found — skipping DPI configuration."
fi
