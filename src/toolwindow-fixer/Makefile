# Makefile for fusion-toolwindow-fixer.exe
# Cross-compile a Win32 PE binary that runs under Wine/Proton.
#
# Requirements: x86_64-w64-mingw32-gcc (apt install mingw-w64)
#
# Targets:
#   make          — build fusion-toolwindow-fixer.exe
#   make clean    — remove build artifacts
#   make install  — copy to ../../src/runtime/  (for the repo layout)

CC    = x86_64-w64-mingw32-gcc
CFLAGS = -Os -s
LIBS  = -luser32

TARGET = fusion-toolwindow-fixer.exe

.PHONY: all clean install

all: $(TARGET)

$(TARGET): fusion-toolwindow-fixer.c
	$(CC) $(CFLAGS) -o $@ $^ $(LIBS)

clean:
	rm -f $(TARGET)

install: $(TARGET)
	cp $(TARGET) ../../src/runtime/
