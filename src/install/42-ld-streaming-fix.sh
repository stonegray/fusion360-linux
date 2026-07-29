# src/install/42-ld-streaming-fix.sh — Suppress LaunchDarkly streaming noise
#
# LaunchDarkly's streaming feature-flag connection fails under Wine's
# network stack (curl error 56).  The SDK retries with backoff then
# falls back to polling, but the retry noise pollutes logs.
#
# Two mitigations:
#   1. hosts entry — resolves clientstream.launchdarkly.com to 0.0.0.0
#      so the connection fails instantly instead of timing out.
#   2. Registry env var — LD_DISABLE_STREAMING=1 tells the SDK to skip
#      streaming entirely on startup.

proton=$(find "$COMPAT_DIR" -name proton -type f 2>/dev/null | head -1 || true)
if [[ -z "$proton" ]]; then
  log_info " GE-Proton not found — skipping LD streaming fix."
  return 1
fi

# --------------------------------------------------
# 1. Hosts entry
# --------------------------------------------------
local hosts_file="$PFX_DIR/pfx/drive_c/windows/system32/drivers/etc/hosts"
if [[ -f "$hosts_file" ]] && ! grep -qs "clientstream.launchdarkly.com" "$hosts_file" 2>/dev/null; then
  # Add above the loopback section (before the "::1" line) for clarity
  sed -i '/^::1 /i\
0.0.0.0 clientstream.launchdarkly.com\t# suppress LD streaming noise' "$hosts_file"
  log_info " Added clientstream.launchdarkly.com -> 0.0.0.0 in prefix hosts"
elif [[ -f "$hosts_file" ]]; then
  log_info " LD streaming host entry already present."
else
  log_info " Prefix hosts file not found — creating."
  mkdir -p "$(dirname "$hosts_file")"
  {
    echo "# Wine hosts file (suppress LD streaming noise)"
    echo "0.0.0.0 clientstream.launchdarkly.com"
    echo ""
    echo "127.0.0.1 localhost"
    echo "::1 localhost"
  } > "$hosts_file"
  log_info " Created hosts file with LD streaming entry."
fi

# --------------------------------------------------
# 2. Registry env var (HKCU\Environment)
# --------------------------------------------------
local wine_bin
wine_bin="$(dirname "$proton")/files/bin/wine"
if [[ -x "$wine_bin" ]]; then
  WINEPREFIX="$PFX_DIR/pfx" "$wine_bin" reg add "HKCU\\Environment" \
    /v LD_DISABLE_STREAMING /t REG_SZ /d 1 /f &>/dev/null \
    && log_info " Set LD_DISABLE_STREAMING=1 in prefix environment registry" \
    || log_info " Warning: could not set LD_DISABLE_STREAMING registry key"
else
  log_info " Warning: Wine binary not found — skipping registry step."
fi
