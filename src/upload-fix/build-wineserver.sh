#!/usr/bin/env bash
# src/upload-fix/build-wineserver.sh — Build a patched wineserver for a GE-Proton release.
#
# Fixes slow Fusion cloud uploads (~100 KB/s per connection) under Wine. See
# docs/troubleshooting.md ("Cloud saves upload very slowly") and WineHQ bug 59893.
#
# Usage: build-wineserver.sh <GE tag> <work dir> [<proton dir to test against>]
# On success, prints the path of the built wineserver as the last line of stdout.
#
# Recreates the exact Wine tree GE ships (Valve wine + wine-staging at the tag's
# submodule commits, GE's patch script), applies 0001-server-rearm-fd-write.patch,
# and builds only server/wineserver. Takes ~10 min and ~1 GB in <work dir>.
set -euo pipefail

TAG=${1:?usage: $0 <GE tag> <work dir> [<proton dir>]}
WORK=${2:?usage: $0 <GE tag> <work dir> [<proton dir>]}
PROTON_DIR=${3:-}
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH="$HERE/0001-server-rearm-fd-write.patch"
say() { printf '  %s\n' "$*" >&2; }

missing=()
for c in git gcc make python3 perl bison flex autoconf autoreconf x86_64-w64-mingw32-gcc; do
  command -v "$c" >/dev/null 2>&1 || missing+=("$c")
done
if (( ${#missing[@]} )); then
  say "Missing build tools: ${missing[*]}"
  exit 2
fi

say "Fetching proton-ge-custom $TAG sources..."
rm -rf "$WORK" && mkdir -p "$WORK" && cd "$WORK"
git -c advice.detachedHead=false clone -q --depth 1 --branch "$TAG" \
    https://github.com/GloriousEggroll/proton-ge-custom.git pgc
cd pgc
PREP=patches/protonprep-valve-staging.sh
[[ -f $PREP ]] || { say "GE's patch script ($PREP) not found in $TAG; layout changed."; exit 1; }
WINE_URL=$(git config -f .gitmodules submodule.wine.url)
STAGING_URL=$(git config -f .gitmodules submodule.wine-staging.url)
WINE_SHA=$(git ls-tree HEAD wine | awk '{print $3}')
STAGING_SHA=$(git ls-tree HEAD wine-staging | awk '{print $3}')

fetch_at() { # dir url sha
  rmdir "$1" 2>/dev/null || true
  git init -q "$1"
  git -C "$1" remote add origin "$2"
  git -C "$1" fetch -q --depth 1 origin "$3"
  git -C "$1" checkout -q "$3"
}
fetch_at wine "$WINE_URL" "$WINE_SHA"
fetch_at wine-staging "$STAGING_URL" "$STAGING_SHA"
# Commits GE's script reverts must exist locally, with their parents.
for c in $(grep -oE 'git revert --no-commit [0-9a-f]{7,40}' "$PREP" | awk '{print $4}'); do
  git -C wine fetch -q --depth 2 origin "$c"
done

say "Applying GE's Wine patches..."
{ sed -n '1,/^### (1) PREP SECTION ###/p' "$PREP" | sed '$d'
  sed -n '/^### (2) WINE PATCHING ###/,/^### END WINE PATCHING ###/p' "$PREP"
} > ../prep-wine.sh
if ! bash ../prep-wine.sh > ../prep.log 2>&1; then
  say "GE's patch step failed; see $WORK/prep.log"
  exit 1
fi
if find wine -name '*.rej' | grep -q .; then
  say "Patch rejects in the GE tree; see $WORK/prep.log"
  exit 1
fi
cd wine
[[ -f include/wine/vulkan.h ]] || XDG_CACHE_HOME="$WORK/cache" dlls/winevulkan/make_vulkan -x vk.xml -X video.xml >/dev/null
tools/make_specfiles >/dev/null 2>&1 || true

say "Applying upload fix patch..."
patch -Np1 < "$PATCH" >/dev/null

say "Building wineserver (a few minutes)..."
mkdir -p "$WORK/build" && cd "$WORK/build"
if ! "$WORK/pgc/wine/configure" --enable-archs=x86_64 --disable-tests --without-x --without-freetype \
     --without-gnutls --without-wayland --without-vulkan --without-opengl --without-gstreamer \
     --without-pulse --without-alsa --without-cups --without-sane --without-dbus --without-krb5 \
     --without-gphoto --without-usb --without-v4l2 --without-pcap --without-netapi --without-sdl \
     --without-capi --without-ffmpeg --without-osmesa > configure.log 2>&1; then
  say "configure failed; see $WORK/build/configure.log"
  exit 1
fi
if ! make -j"$(nproc)" server/wineserver > make.log 2>&1; then
  say "Build failed; see $WORK/build/make.log"
  exit 1
fi
NEW="$WORK/build/server/wineserver"

# Test: a curl-style upload loop (see shortwrite.c) must not hit 1 s FD_WRITE stalls.
if [[ -n $PROTON_DIR && -x $PROTON_DIR/files/bin/wine ]]; then
  say "Testing against $(basename "$PROTON_DIR") (throwaway prefix)..."
  x86_64-w64-mingw32-gcc -O2 -o "$WORK/shortwrite.exe" "$HERE/shortwrite.c" -lws2_32
  export WINEPREFIX="$WORK/testpfx" WINEDEBUG=-all
  mkdir -p "$WINEPREFIX"
  "$NEW" -p120   # the timeout must be attached: "-p 120" means persist forever
  timeout 300 "$PROTON_DIR/files/bin/wine" wineboot -u >/dev/null 2>&1 || true
  fails=0
  for port in 47101 47102 47103; do
    timeout 60 python3 -I "$HERE/slowsink.py" "$port" 6 & sleep 0.5
    # Pass only if the run exits 0 (no stalls, no send error) and moved all 8 MiB.
    rc=0
    out=$(timeout 60 "$PROTON_DIR/files/bin/wine" "$WORK/shortwrite.exe" "$port" 8 2>/dev/null) || rc=$?
    wait || true
    out=$(grep -E '^(sent|send err)' <<<"$out" || true)
    say "  ${out:-no output} (exit $rc)"
    if (( rc != 0 )) || [[ $out != "sent 8 MiB "*" 0 stalls"* ]]; then
      fails=$((fails + 1))
    fi
  done
  "$NEW" -k 2>/dev/null || true
  if (( fails )); then
    say "Test failed ($fails/3 runs stalled)."
    exit 1
  fi
fi

echo "$NEW"
