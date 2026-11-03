# src/install/42-ld-streaming-fix.sh — Suppress LaunchDarkly streaming noise
#
# LaunchDarkly's streaming feature-flag connection fails under Wine's
# network stack (curl error 56).  The SDK retries with backoff then
# falls back to polling, but the retry noise pollutes logs.
#
# Mitigation: hosts entry resolves clientstream.launchdarkly.com to
# 0.0.0.0 so the connection fails instantly (ECONNREFUSED from loopback)
# instead of timing out or hitting real DNS.

proton=$(find_proton "$COMPAT_DIR")
if [[ -z "$proton" ]]; then
  log_info " GE-Proton not found — skipping LD streaming fix."
  return 1
fi

local hosts_file="$PFX_DIR/pfx/drive_c/windows/system32/drivers/etc/hosts"
if [[ -f "$hosts_file" ]] && ! grep -qs "clientstream.launchdarkly.com" "$hosts_file" 2>/dev/null; then
  # Append rather than inserting at a fixed anchor. The previous form
  # (`sed -i '/^::1 /i\...'`) only fires if the file already has an ::1
  # line; Wine's default hosts file does not, so the edit matched nothing,
  # returned 0, and the "Added" message below reported a change that never
  # happened. Trailing newline guard: Wine writes the file without one, and
  # a missing final newline would splice our entry onto the last line.
  [[ -n "$(tail -c1 "$hosts_file" 2>/dev/null)" ]] && echo >> "$hosts_file"
  printf '0.0.0.0 clientstream.launchdarkly.com\t# suppress LD streaming noise\n' >> "$hosts_file"
  if grep -qs "clientstream.launchdarkly.com" "$hosts_file"; then
    log_info " Added clientstream.launchdarkly.com -> 0.0.0.0 in prefix hosts"
  else
    log_warn " Could not write LD streaming entry to $hosts_file"
  fi
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
