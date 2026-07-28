# src/doctor/50-config.sh — Configuration checks

header "5. Configuration"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fusion360-linux"
CONFIG_FILE="$CONFIG_DIR/config"

if [[ -f "$CONFIG_FILE" ]]; then
  pass "Config file exists: $CONFIG_FILE"
  if source "$CONFIG_FILE" 2>/dev/null; then
    pass "Config file parses correctly"
  else
    fail "Config file has syntax errors"
  fi

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

app_dir="$HOME/.local/share/applications/fusion360-linux"
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

for scheme in adsk adskidmgr; do
  handler=$(xdg-mime query default "x-scheme-handler/$scheme" 2>/dev/null || true)
  if echo "$handler" | grep -qi "fusion360-callback-handler"; then
    pass "$scheme:// protocol → $handler"
  else
    fail "$scheme:// protocol not registered (current: ${handler:-none})"
  fi
done

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
