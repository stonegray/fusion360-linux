# src/install/26-runtime-patches.sh — Build the PE helpers the runtime needs
#
# Runs after 25-install-to-location.sh (which lays down the tree) and before
# 30-prefix.sh (which does not need them) so a failure here surfaces early,
# while the user is still looking at the installer.
#
# Nothing here is shipped prebuilt. The dialog shim has to match the headers
# of whatever mingw-w64 the machine has, and a committed .dll is a binary blob
# that silently drifts from its own source: this repo has already shipped a
# stale fusion-toolwindow-fixer.exe for exactly that reason.

log_info " Building runtime helpers..."

# Build from the sources 25-install-to-location.sh staged into the data
# directory, not from this repo: the installed tree is then self-contained and
# this step works even when run on its own.
F360_ND_OUT="$F360_DATA_DIR/native-dialogs"
F360_ND_SRC="$F360_ND_OUT"

# 25 creates this while staging; make it here too so the step does not depend
# on running order. Falling back to the repo keeps `make test`-style use
# working from a checkout that was never installed.
if [[ ! -d "$F360_ND_SRC" ]]; then
  F360_ND_SRC="$SCRIPT_DIR/src/native-dialogs"
fi
mkdir -p "$F360_ND_OUT" "$F360_DATA_DIR/toolwindow-fixer"

if [[ ! -f "$F360_ND_SRC/comdlg32.c" ]]; then
  log_error " Dialog shim sources not found in $F360_ND_SRC."
  log_error " Run 25-install-to-location.sh first, or re-run install.sh."
  return 1
fi

# The shim is an optional convenience: without it Fusion still opens files
# through Wine's own dialog. So a missing toolchain degrades rather than
# aborting, but says exactly what to install.
missing=()
command -v x86_64-w64-mingw32-gcc &>/dev/null || missing+=("mingw-w64 (provides x86_64-w64-mingw32-gcc)")
command -v gcc &>/dev/null || missing+=("gcc")
if (( ${#missing[@]} )); then
  log_warn " Missing build tools: ${missing[*]}"
  log_warn " Native file dialogs will be unavailable — Fusion will use Wine's dialog."
  log_warn " Install the packages above and re-run install.sh to enable them."
  rm -rf "$F360_ND_OUT"
  return 0
fi

# hostrunner: a Unix binary that runs the picker and records its exit, so the
# shim never has to poll for a file the user has not chosen yet.
log_info " Building host runner..."
if ! gcc -O2 -Wall -o "$F360_ND_OUT/hostrunner" "$F360_ND_SRC/hostrunner.c"; then
  log_error " hostrunner build failed."
  return 1
fi
chmod 755 "$F360_ND_OUT/hostrunner"
# Two warnings are expected and benign:
#   -wattributes: mingw's shlobj.h already declares the legacy comdlg32
#     exports with dllimport, which conflicts with our dllexport definition.
#   -Wincompatible-pointer-types: IShellItem2's PROPERTYKEY accessors are
#     declared unsigned-long vs unsigned-int in these headers; the ABI is
#     identical.
# Everything else stays fatal, so a real compile error cannot be buried.
if ! x86_64-w64-mingw32-gcc \
      -O2 -Wall -Wextra -Wno-cast-function-type -Wno-unused-parameter \
      -Wno-attributes -Wno-incompatible-pointer-types \
      -o "$F360_ND_OUT/dlgshim.dll" \
      "$F360_ND_SRC/comdlg32.c" \
      "$F360_ND_SRC/dialog_com.c" \
      "$F360_ND_SRC/shim_log.c" \
      "$F360_ND_SRC/dlgshim.def" \
      -s -shared -lole32 -luuid; then
  log_error " dlgshim.dll build failed."
  return 1
fi

# A silently empty or truncated PE would fail at Fusion launch with no useful
# message, so check the build actually produced something loadable.
for artifact in "$F360_ND_OUT/dlgshim.dll" "$F360_ND_OUT/hostrunner"; do
  if [[ ! -s "$artifact" ]]; then
    log_error " ${artifact##*/} was not produced."
    return 1
  fi
done
if ! x86_64-w64-mingw32-objdump -f "$F360_ND_OUT/dlgshim.dll" 2>/dev/null | grep -q 'pei-x86-64'; then
  log_error " dlgshim.dll is not a 64-bit PE — the build produced the wrong format."
  return 1
fi

# toolwindow-fixer: a Win32 daemon that marks Fusion's WS_POPUP panels as
# WS_EX_APPWINDOW so the compositor can stack them (the "always on top"
# z-order bug). 45-filetypes.sh installs it into the prefix; it is built here
# because this is the step that verifies the cross-compiler exists.
# Prefer the staged copy (25 installs it) so the data tree is self-contained.
F360_TWF_SRC="$F360_DATA_DIR/toolwindow-fixer"
[[ -f "$F360_TWF_SRC/fusion-toolwindow-fixer.c" ]] || F360_TWF_SRC="$SCRIPT_DIR/src/toolwindow-fixer"
F360_TWF_OUT="$F360_DATA_DIR/toolwindow-fixer"

log_info " Building toolwindow fixer..."
if ! x86_64-w64-mingw32-gcc -Os -s \
      -o "$F360_TWF_OUT/fusion-toolwindow-fixer.exe" \
      "$F360_TWF_SRC/fusion-toolwindow-fixer.c" -luser32; then
  log_error " fusion-toolwindow-fixer.exe build failed."
  return 1
fi
if ! x86_64-w64-mingw32-objdump -f "$F360_TWF_OUT/fusion-toolwindow-fixer.exe" \
      2>/dev/null | grep -q 'pei-x86-64'; then
  log_error " fusion-toolwindow-fixer.exe is not a 64-bit PE."
  return 1
fi

log_info " Runtime helpers built: dlgshim.dll, hostrunner, fusion-toolwindow-fixer.exe"
