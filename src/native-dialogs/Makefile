# Build the comdlg32 shim as a 64-bit PE DLL.
#
# Used by launch-fusion.sh via WINEDLLOVERRIDES="comdlg32=n" scoped to the
# Fusion launch only, never to prefix setup.

# := not ?= — make predefines CC, so ?= would silently keep the host gcc.
CC      := x86_64-w64-mingw32-gcc
# -O2 and -s: this sits on every Open dialog call, and the shipped artifact is
# committed, so keep it small and optimised.
CFLAGS  ?= -O2 -Wall -Wextra -Wno-cast-function-type
LDFLAGS ?= -s -shared -Wl,--kill-at

all: comdlg32.dll

comdlg32.dll: comdlg32.c comdlg32.def
	$(CC) $(CFLAGS) -o $@ $< comdlg32.def $(LDFLAGS)

clean:
	rm -f comdlg32.dll

.PHONY: all clean
