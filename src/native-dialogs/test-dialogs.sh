#!/bin/bash
# test-dialogs.sh — regression tests for the comdlg32 COM shim.
#
# These exist because the shim's failures are silent: a broken build opens a
# dialog, returns "cancelled", and Fusion shows nothing in its log. Every test
# here asserts on an observable outcome (returned path, returned HRESULT),
# not on "the dialog appeared".
#
# The slow-pick test is the most important one. kdialog writes nothing until a
# file is chosen, so any bounded wait in the capture path races the user. It
# was added after a 6-second poll shipped and broke picks slower than 6s.
#
# Usage: ./test-dialogs.sh [--prefix DIR]
set -u

PROTON="${PROTON:-$HOME/.local/share/Steam/compatibilitytools.d/GE-Proton11-3}"
PREFIX="${1:-}"
if [[ "${1:-}" == "--prefix" ]]; then PREFIX="${2:-}"; else PREFIX=""; fi
PREFIX="${PREFIX:-$HOME/.fusion360-proton2/pfx}"
HERE="$(cd "$(dirname "$0")" && pwd)"
WINE="$PROTON/files/bin/wine"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0 fail=0
chk() {
  if echo "$2" | grep -q "$3"; then printf 'PASS  %s\n' "$1"; pass=$((pass+1))
  else printf 'FAIL  %s\n      expected: %s\n      got: %s\n' "$1" "$3" "$(echo "$2" | head -3)"; fail=$((fail+1)); fi
}

if [[ ! -x "$WINE" ]]; then echo "error: wine not found at $WINE" >&2; exit 1; fi

# A picker that takes 8s to return — longer than any human-plausible timeout.
cat > "$WORK/slowpicker.c" <<'EOF'
#include <stdio.h>
#include <unistd.h>
int main(void){ sleep(8); printf("/tmp/picked-file.stl\n"); return 0; }
EOF
gcc -O2 -o "$WORK/slowpicker" "$WORK/slowpicker.c" || exit 1
cat > "$WORK/fastpicker.c" <<'EOF'
#include <stdio.h>
int main(void){ printf("/tmp/picked-file.stl\n"); return 0; }
EOF
gcc -O2 -o "$WORK/fastpicker" "$WORK/fastpicker.c" || exit 1
touch /tmp/picked-file.stl

# Mimics how Qt consumes IFileOpenDialog: CoCreateInstance, Set* calls, Show,
# then GetResults -> GetItemAt -> GetDisplayName.
cat > "$WORK/harness.c" <<'EOF'
#include <windows.h>
#include <shobjidl.h>
#include <stdio.h>
int main(void){
  CoInitialize(NULL);
  IFileOpenDialog *d=NULL;
  HRESULT hr=CoCreateInstance(&(GUID){0xDC1C5A9C,0xE88A,0x4DDE,{0xA5,0xA1,0x60,0xF8,0x2A,0x20,0xAE,0xF7}},
      NULL,CLSCTX_INPROC_SERVER,&IID_IFileOpenDialog,(void**)&d);
  if(FAILED(hr)){ printf("CoCreate hr=0x%08lx\n",(unsigned long)hr); return 1; }
  COMDLG_FILTERSPEC f[1]={{L"STL",L"*.stl"}};
  d->lpVtbl->SetFileTypes(d,1,f);
  hr=d->lpVtbl->Show(d,NULL);
  printf("Show=0x%08lx\n",(unsigned long)hr);
  if(SUCCEEDED(hr)){
    IShellItemArray *a=NULL;
    if(SUCCEEDED(d->lpVtbl->GetResults(d,&a)) && a){
      DWORD n=0; a->lpVtbl->GetCount(a,&n);
      printf("Count=%lu\n",(unsigned long)n);
      IShellItem *it=NULL;
      if(SUCCEEDED(a->lpVtbl->GetItemAt(a,0,&it)) && it){
        LPWSTR p=NULL; it->lpVtbl->GetDisplayName(it,SIGDN_FILESYSPATH,&p);
        wprintf(L"Path=%ls\n",p?p:L"(null)"); CoTaskMemFree(p); it->lpVtbl->Release(it);
      }
      a->lpVtbl->Release(a);
    }
  }
  d->lpVtbl->Release(d); CoUninitialize(); return 0;
}
EOF
x86_64-w64-mingw32-gcc -O2 -o "$WORK/harness.exe" "$WORK/harness.c" -lole32 -luuid -lshell32 || exit 1
cp "$HERE/hostrunner" "$WORK/hostrunner"

to_wine() { printf 'Z:%s' "$(printf '%s' "$1" | tr '/' '\\')"; }

run() { # run <picker-path> [extra env]
  local picker="$1"
  WINEPREFIX="$PREFIX" FUSION_NATIVE_DIALOG_CMD="$picker" WINEDEBUG=-all \
    timeout 60 "$WINE" "$WORK/harness.exe" 2>/dev/null
}

# The harness loads comdlg32 from the prefix; the runner must sit beside it,
# which is what the launcher does. Point FUSION_NATIVE_DIALOG into place by
# copying nothing — instead ensure the shim is installed where the launcher
# puts it, and let these tests exercise the installed copy.
echo "== dialog shim regression tests =="
echo "prefix: $PREFIX"
echo

r=$(run "$(to_wine "$WORK/slowpicker")")
chk "slow pick (8s) still returns a path" "$r" "Show=0x00000000"
chk "slow pick path is correct"            "$r" "picked-file.stl"

r=$(run "$(to_wine "$WORK/fastpicker")")
chk "fast pick returns a path" "$r" "Show=0x00000000"

r=$(run "$(to_wine /usr/bin/true)")
chk "cancel still reports CANCELLED" "$r" "Show=0x800704c7"

echo
printf 'passed=%d failed=%d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
