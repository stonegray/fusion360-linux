# Build the comdlg32 shim as a 64-bit PE DLL.
#
# Used by launch-fusion.sh via WINEDLLOVERRIDES="comdlg32=n" scoped to the
# Fusion launch only, never to prefix setup.

# := not ?= — make predefines CC, so ?= would silently keep the host gcc.
CC      := x86_64-w64-mingw32-gcc
# -O2 and -s: this sits on every Open dialog call, and the shipped artifact is
# committed, so keep it small and optimised.
CFLAGS  := -O2 -Wall -Wextra -Wno-cast-function-type -Wno-unused-parameter
LDFLAGS := -s -shared -lole32 -luuid

SRCS := comdlg32.c dialog_com.c

all: dlgshim.dll

dlgshim.dll: $(SRCS) dlgshim.def
	$(CC) $(CFLAGS) -o $@ $(SRCS) dlgshim.def $(LDFLAGS)

clean:
	rm -f dlgshim.dll

.PHONY: all clean
