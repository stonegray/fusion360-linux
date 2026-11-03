# Build the runtime helpers used by launch-fusion.sh.
#
#   dlgshim.dll  comdlg32 replacement, loaded via WINEDLLOVERRIDES="comdlg32=n"
#                scoped to the Fusion launch only, never to prefix setup.
#   hostrunner   Unix helper that runs the picker and records its exit, so the
#                shim never polls for a file the user has not chosen yet.
#
# Both are generated and gitignored. install.sh builds them in
# src/install/26-runtime-patches.sh; this Makefile is for development and for
# test-dialogs.sh, which needs the artifacts to exist before it can run.

# := not ?= — make predefines CC, so ?= would silently keep the host gcc.
CC      := x86_64-w64-mingw32-gcc
# -O2 and -s: this sits on every Open dialog call, so keep it small.
CFLAGS  := -O2 -Wall -Wextra -Wno-cast-function-type -Wno-unused-parameter \
           -Wno-attributes -Wno-incompatible-pointer-types
LDFLAGS := -s -shared -lole32 -luuid

SRCS := comdlg32.c dialog_com.c shim_log.c

all: dlgshim.dll hostrunner

dlgshim.dll: $(SRCS) dlgshim.def
	$(CC) $(CFLAGS) -o $@ $(SRCS) dlgshim.def $(LDFLAGS)

hostrunner: hostrunner.c
	gcc -O2 -Wall -o hostrunner $<

test: all
	./test-dialogs.sh

clean:
	rm -f dlgshim.dll hostrunner hostrunner.exe

.PHONY: all test clean
