#!/usr/bin/env bash
# File: kill-wine-proton-fusion-nuclear.sh
set -euo pipefail

USER_NAME="$(id -un)"

# Wine/Proton wrappers (safe to kill)
WRAPPER_PATTERN='(wine|wine64|wineserver|wine-preloader|wine64-preloader|proton|pressure-vessel)'

# Fusion / Autodesk stuff (often Windows-side names)
FUSION_PATTERN='Fusion360|Autodesk|Adsk|AdSSO|Identity|CefSharp'

# "Chromium helper" names ONLY when clearly under Wine/Proton (prevents killing Opera/Chrome native)
WRAPPED_CHROMIUM_HELPERS_PATTERN="${WRAPPER_PATTERN}.*(crashpad|BrowserSubprocess|chrome\\.exe|msedge\\.exe)"

# First pass: TERM
pkill -u "$USER_NAME" -f "$FUSION_PATTERN" 2>/dev/null || true
pkill -u "$USER_NAME" -f "$WRAPPED_CHROMIUM_HELPERS_PATTERN" 2>/dev/null || true
pkill -u "$USER_NAME" -f "$WRAPPER_PATTERN" 2>/dev/null || true

sleep 0.3

# Second pass: KILL
pkill -9 -u "$USER_NAME" -f "$FUSION_PATTERN" 2>/dev/null || true
pkill -9 -u "$USER_NAME" -f "$WRAPPED_CHROMIUM_HELPERS_PATTERN" 2>/dev/null || true
pkill -9 -u "$USER_NAME" -f "$WRAPPER_PATTERN" 2>/dev/null || true
