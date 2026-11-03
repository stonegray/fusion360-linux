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

# Reproduces how Fusion actually consumes IFileOpenDialog, as captured from a
# logging proxy around Wine's own dialog: Advise() comes FIRST, and the result
# is read from inside the OnFileOk callback rather than after Show() returns.
# Fusion never calls GetResult/GetResults after Show; a shim that only answers
# them post-Show silently delivers nothing (Fusion closes the dialog and logs
# no "Opening the document" at all). Regression test for that.
cat > "$WORK/fusionharness.c" <<'EOF'
#include <windows.h>
#include <shobjidl.h>
#include <stdio.h>

static char g_path[1024];

typedef struct { IFileDialogEvents iface; LONG ref; } Ev;
static HRESULT WINAPI e_qi(IFileDialogEvents *i, REFIID r, void **o){(void)i;(void)r;if(!o)return E_POINTER;*o=NULL;return E_NOINTERFACE;}
static ULONG WINAPI e_add(IFileDialogEvents *i){return (ULONG)InterlockedIncrement(&((Ev*)i)->ref);}
static ULONG WINAPI e_rel(IFileDialogEvents *i){return (ULONG)InterlockedDecrement(&((Ev*)i)->ref);}
static HRESULT WINAPI e_ok(IFileDialogEvents *i, IFileDialog *d){
  (void)i;
  IShellItemArray *a=NULL;
  IFileOpenDialog *od=(IFileOpenDialog*)d;   /* GetResults lives on the open-dialog vtable */
  if(SUCCEEDED(od->lpVtbl->GetResults(od,&a)) && a){
    DWORD n=0; a->lpVtbl->GetCount(a,&n);
    if(n>0){ IShellItem *it=NULL;
      if(SUCCEEDED(a->lpVtbl->GetItemAt(a,0,&it)) && it){
        LPWSTR p=NULL; it->lpVtbl->GetDisplayName(it,SIGDN_FILESYSPATH,&p);
        if(p){ WideCharToMultiByte(CP_UTF8,0,p,-1,g_path,sizeof g_path,NULL,NULL); CoTaskMemFree(p);}
        it->lpVtbl->Release(it);} }
    a->lpVtbl->Release(a);
  }
  return S_OK;
}
/* Stubs for the events the shim does not need to fire; only OnFileOk is
 * load-bearing for delivering a selection. */
static HRESULT WINAPI e_stub(void *a,void *b,void *c,void *e){(void)a;(void)b;(void)c;(void)e;return S_OK;}
static IFileDialogEventsVtbl EvVtbl={e_qi,e_add,e_rel,e_ok,
    (void*)e_stub,  /* OnFolderChanging */
    (void*)e_stub,  /* OnFolderChange */
    (void*)e_stub,  /* OnSelectionChange */
    (void*)e_stub,  /* OnShareViolation */
    (void*)e_stub,  /* OnTypeChange */
    (void*)e_stub}; /* OnOverwrite */

int main(void){
  CoInitialize(NULL);
  IFileOpenDialog *d=NULL;
  HRESULT hr=CoCreateInstance(&(GUID){0xDC1C5A9C,0xE88A,0x4DDE,{0xA5,0xA1,0x60,0xF8,0x2A,0x20,0xAE,0xF7}},
      NULL,CLSCTX_INPROC_SERVER,&IID_IFileOpenDialog,(void**)&d);
  if(FAILED(hr)){printf("CoCreate=0x%08lx\n",(unsigned long)hr);return 1;}
  Ev ev; ev.iface.lpVtbl=&EvVtbl; ev.ref=1;
  DWORD cookie=0;
  hr=d->lpVtbl->Advise(d,&ev.iface,&cookie);
  printf("Advise=0x%08lx cookie=%lu\n",(unsigned long)hr,(unsigned long)cookie);
  COMDLG_FILTERSPEC f[1]={{L"STL",L"*.stl"}};
  d->lpVtbl->SetFileTypes(d,1,f);
  hr=d->lpVtbl->Show(d,NULL);
  printf("Show=0x%08lx\n",(unsigned long)hr);
  /* Fusion reads the result inside OnFileOk, never afterwards. */
  printf("PathFromCallback=%s\n", g_path[0]?g_path:"(empty)");
  d->lpVtbl->Unadvise(d,cookie);
  d->lpVtbl->Release(d); CoUninitialize(); return 0;
}
EOF
x86_64-w64-mingw32-gcc -O2 -o "$WORK/fusionharness.exe" "$WORK/fusionharness.c" -lole32 -luuid -lshell32 || exit 1

to_wine() { printf 'Z:%s' "$(printf '%s' "$1" | tr '/' '\\')"; }

run() { # run <picker-path> [extra env]
  local picker="$1"
  WINEPREFIX="$PREFIX" FUSION_NATIVE_DIALOG_CMD="$picker" WINEDEBUG=-all \
    timeout 60 "$WINE" "$WORK/harness.exe" 2>/dev/null
}

runfusion() {
  local picker="$1"
  WINEPREFIX="$PREFIX" FUSION_NATIVE_DIALOG_CMD="$picker" WINEDEBUG=-all \
    timeout 60 "$WINE" "$WORK/fusionharness.exe" 2>/dev/null
}

# These tests must exercise the build sitting next to this script, not
# whatever happens to be registered in the prefix. An earlier version loaded
# the installed copy, so a reverted build still "passed" — the tests were
# validating a DLL nobody had just compiled.
#
# Install it, then verify the registry actually points at it. Wine keeps the
# registry in memory, so wineserver has to be down before system.reg is read.
#
# The artifacts are generated, so build them here rather than expecting a
# committed DLL: a checked-in binary silently drifts from its own source.
HERE="$(cd "$(dirname "$0")" && pwd)"
if ! make -C "$HERE" >/dev/null 2>&1; then
  echo "error: build failed — run 'make -C $HERE' to see why" >&2
  exit 1
fi
SHIM="$HERE/dlgshim.dll"
[[ -f "$SHIM" ]] || { echo "error: make did not produce dlgshim.dll" >&2; exit 1; }
FUSION_DIR="$PREFIX/drive_c/users/steamuser/AppData/Local/Autodesk/webdeploy/production/39e8a3d5e919c70b05ef3ebfe9c6bfc8d9ee001e"
cp "$SHIM" "$FUSION_DIR/dlgshim.dll" || exit 1
cp "$(dirname "$0")/hostrunner" "$FUSION_DIR/hostrunner" 2>/dev/null
if ! grep -qF 'dlgshim.dll' "$PREFIX/system.reg" 2>/dev/null; then
  echo "error: CLSID_FileOpenDialog is not registered to dlgshim.dll in $PREFIX" >&2
  echo "       run install.sh, or set InprocServer32 for {DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7}" >&2
  exit 1
fi

echo "== dialog shim regression tests =="
echo "prefix: $PREFIX"
echo "shim:   $SHIM"
echo

r=$(run "$(to_wine "$WORK/slowpicker")")
chk "slow pick (8s) still returns a path" "$r" "Show=0x00000000"
chk "slow pick path is correct"            "$r" "picked-file.stl"

r=$(run "$(to_wine "$WORK/fastpicker")")
chk "fast pick returns a path" "$r" "Show=0x00000000"

r=$(run "$(to_wine /usr/bin/true)")
chk "cancel still reports CANCELLED" "$r" "Show=0x800704c7"

r=$(runfusion "$(to_wine "$WORK/fastpicker")")
chk "Fusion pattern: Advise returns a real cookie"  "$r" "cookie=1"
chk "Fusion pattern: OnFileOk delivers the path"    "$r" "PathFromCallback=.*picked-file.stl"

echo
printf 'passed=%d failed=%d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
