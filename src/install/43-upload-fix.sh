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

local fix_dir="$FUSION_DATA_DIR/upload-fix"
local proton; proton=$(find_proton "$COMPAT_DIR")
if [[ -z "$proton" ]]; then
  log_error " GE-Proton not found. Run ./install.sh first."
  return 1
fi
local proton_dir; proton_dir="$(dirname "$proton")"
local tag; tag="$(basename "$proton_dir")"
local target="$proton_dir/files/bin/wineserver"
local backup="$fix_dir/wineserver.$tag.orig"

if [[ -n "$(list_fusion_processes | grep -i -E 'Fusion360|wineserver' || true)" ]]; then
  log_error " Fusion / Wine is running. Close Fusion (or ./install.sh --kill) and retry."
  return 1
fi

if [[ "${UPLOAD_FIX_ACTION:-apply}" == "revert" ]]; then
  if [[ -f "$backup" ]]; then
    cp "$backup" "$target.new" && chmod 755 "$target.new" && mv "$target.new" "$target"
    rm -f "$fix_dir/patched.sha256"
    log_pass " Restored original wineserver for $tag."
  else
    log_warn " No backup for $tag in $fix_dir; nothing to revert."
  fi
  return 0
fi

mkdir -p "$fix_dir"
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

[[ -f "$backup" ]] || cp -a "$target" "$backup"
cp "$built" "$target.new" && chmod 755 "$target.new" && mv "$target.new" "$target"
echo "$(sha256sum "$target" | awk '{print $1}')  $tag" > "$fix_dir/patched.sha256"
rm -rf "$work"
log_pass " Upload fix installed for $tag (original saved as $backup)."
log_detail "   Undo with: ./install.sh --upload-fix-revert"
