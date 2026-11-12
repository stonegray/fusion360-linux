# src/install/43-upload-fix.sh — Opt-in: patched wineserver for fast cloud uploads
#
# Fusion's uploader (libcurl) stalls for 1 s at a time under Wine. After a
# send() that succeeds but leaves the socket full, Wine never re-arms FD_WRITE,
# so curl's wait always runs to its 1 s timeout. Uploads crawl at ~100 KB/s per
# connection. See docs/troubleshooting.md and WineHQ bug 59893.
#
# The fix is a small wineserver patch (src/upload-fix/). This step rebuilds
# wineserver from the installed GE-Proton release's own sources with the patch,
# tests it, backs up the original and installs it.
#
#   ./install.sh --upload-fix          # apply
#   ./install.sh --upload-fix-revert   # restore the original wineserver
#
# State: $FUSION_DATA_DIR/upload-fix/ (original backups + patched.sha256, used by
# the health check to notice when a Proton reinstall/update removed the fix).

# NOTE: install.sh runs this step as `run_step ... || exit 1`, which turns off
# errexit inside it. Every step that changes files is checked explicitly.

local fix_dir="$FUSION_DATA_DIR/upload-fix"
# Patch the Proton the launcher actually uses (config PROTON / launcher default).
local proton; proton="$(configured_proton "$F360_CONFIG_FILE" || true)"
if [[ -z "$proton" ]]; then
  log_error " The Proton configured for Fusion was not found (PROTON in $F360_CONFIG_FILE)."
  log_detail "   Run ./install.sh first, or fix PROTON with: fusion360 --config"
  return 1
fi
local proton_dir; proton_dir="$(dirname "$proton")"
local tag; tag="$(basename "$proton_dir")"
local target="$proton_dir/files/bin/wineserver"
local backup="$fix_dir/wineserver.$tag.orig"

# Capture the list first: piping it straight into grep lets pgrep match that
# grep's own command line (it contains "wineserver") and block every run.
local procs; procs="$(list_fusion_processes)"
if grep -q -i -E 'Fusion360|wineserver' <<<"$procs"; then
  log_error " Fusion / Wine is running. Close Fusion (or ./install.sh --kill) and retry."
  return 1
fi

# Refresh the installed health check so an existing install can detect a
# Proton update that replaces the patched wineserver (normally installed by
# 25-install-to-location.sh, which this standalone step does not run).
_upload_fix_refresh_health_check() {
  local rt="$FUSION_DATA_DIR/runtime-scripts" sh="$FUSION_DATA_DIR/share"
  [[ -d "$rt" ]] || return 0
  cp "$SCRIPT_DIR/src/runtime/health-check.sh" "$rt/health-check.sh" \
    && chmod 755 "$rt/health-check.sh" \
    || { log_warn " Could not update $rt/health-check.sh"; return 0; }
  [[ -d "$sh" ]] && { cp "$SCRIPT_DIR/share/proton.fn" "$sh/proton.fn" \
    || log_warn " Could not update $sh/proton.fn"; }
  return 0
}

if [[ "${UPLOAD_FIX_ACTION:-apply}" == "revert" ]]; then
  if [[ -f "$backup" ]]; then
    if ! { cp "$backup" "$target.new" && chmod 755 "$target.new" && mv "$target.new" "$target"; }; then
      rm -f "$target.new"
      log_error " Could not restore $target from $backup; nothing changed."
      return 1
    fi
    rm -f "$fix_dir/patched.sha256"
    log_pass " Restored original wineserver for $tag."
  else
    log_warn " No backup for $tag in $fix_dir; nothing to revert."
  fi
  return 0
fi

if ! mkdir -p "$fix_dir"; then
  log_error " Could not create $fix_dir"
  return 1
fi
local current; current="$(sha256sum "$target" | awk '{print $1}')"
if grep -qs "^$current  $tag\$" "$fix_dir/patched.sha256"; then
  log_pass " Upload fix already installed for $tag."
  return 0
fi

local missing=()
local c
for c in git gcc make python3 perl bison flex autoconf autoreconf x86_64-w64-mingw32-gcc; do
  command -v "$c" >/dev/null 2>&1 || missing+=("$c")
done
if (( ${#missing[@]} )); then
  log_error " Missing build tools: ${missing[*]}"
  case "$(detect_distro)" in
    debian) log_detail "   sudo apt-get install git gcc make python3 perl bison flex autoconf automake gcc-mingw-w64-x86-64" ;;
    fedora) log_detail "   sudo dnf install git gcc make python3 perl bison flex autoconf automake mingw64-gcc" ;;
    arch)   log_detail "   sudo pacman -S --needed git gcc make python perl bison flex autoconf automake mingw-w64-gcc" ;;
    *)      log_detail "   Install: git, gcc, make, python3, perl, bison, flex, autoconf, automake, MinGW-w64 x86_64 gcc" ;;
  esac
  return 1
fi

log_info " Building patched wineserver for $tag (~10 min)..."
local work="$FUSION_CACHE_DIR/upload-fix/$tag"
local built
if ! built="$("$SCRIPT_DIR/src/upload-fix/build-wineserver.sh" "$tag" "$work" "$proton_dir")"; then
  log_error " Build or test failed; the installed wineserver was not changed."
  return 1
fi
built="$(tail -n1 <<<"$built")"
if [[ ! -x "$built" ]]; then
  log_error " Build did not produce a wineserver; the installed one was not changed."
  return 1
fi

if [[ ! -f "$backup" ]]; then
  if ! cp -a "$target" "$backup" || ! cmp -s "$target" "$backup"; then
    rm -f "$backup"
    log_error " Could not back up $target; the installed wineserver was not changed."
    return 1
  fi
fi
if ! { cp "$built" "$target.new" && chmod 755 "$target.new" && mv "$target.new" "$target"; }; then
  rm -f "$target.new"
  log_error " Could not install the patched wineserver; $target was not changed."
  return 1
fi
local new_sum; new_sum="$(sha256sum "$target" | awk '{print $1}')"
if [[ "$new_sum" != "$(sha256sum "$built" | awk '{print $1}')" ]]; then
  log_error " Installed wineserver does not match the build. Restore with: ./install.sh --upload-fix-revert"
  return 1
fi
if ! echo "$new_sum  $tag" > "$fix_dir/patched.sha256"; then
  log_error " Could not write $fix_dir/patched.sha256 (the health check will not track the fix)."
  return 1
fi
_upload_fix_refresh_health_check
rm -rf "$work"
log_pass " Upload fix installed for $tag (original saved as $backup)."
log_detail "   Undo with: ./install.sh --upload-fix-revert"
