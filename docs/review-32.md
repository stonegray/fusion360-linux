# Codebase Architecture Review — Fusion 360 on Linux
## Our Codebase vs. Lolig4/Cryinkfly Fork

**Date**: 2026-07-28  
**Reviewer**: Automated deep-dive comparison  

---

## 1. Executive Summary

Our codebase and Lolig4's fork of Cryinkfly solve the same problem — running Autodesk Fusion 360 on Linux via Wine/Proton — with radically different architectural philosophies.

| Dimension | Our Codebase | Lolig4 Fork |
|-----------|-------------|-------------|
| **Size** | ~3,284 lines across 37 `.sh` files + 1 `.py` + 1 `.c` | ~4,128 lines, dominated by one 2,331-line monolithic installer |
| **Architecture** | Modular 12-step pipeline; each step a small sourced script | Monolithic script; self-copying to `~/.local/share` |
| **Wine approach** | GE-Proton (prebuilt); toolwindow fix via C daemon | Custom patched Wine/Proton builds; toolwindow fix via source patch |
| **Winetricks verbs** | 1 (vcrun2022) | 8 (gdiplus, corefonts, cjkfonts, dotnet48, fontsmooth, winhttp, dxvk, vkd3d) |
| **Error handling** | `set -euo pipefail` on standalone scripts; trap cleanup | No `set -e`; `kill -9` everywhere; sleeps as error recovery |
| **Config UI** | Python Tkinter GUI with auto-detection | Terminal-only; no config UI |
| **Multi-install** | No | Yes (multiple prefixes, desktop file swapping) |
| **i18n** | English only | 9 languages (incomplete) |
| **Inventor** | Not supported | Supported |

**Verdict**: Our codebase is safer, more maintainable, and has more Linux-native features (doctor, config UI, filetypes, protocol handlers). Lolig4 has deeper Wine integration (patched builds, GPU detection, multi-install) and a broader scope (Inventor, i18n) but at the cost of code quality and reliability.

---

## 2. Winetricks & Prefix Comparison

### 2.1 Winetricks Verbs

**Lolig4** (`init_pfx()`, line 1827):
1. `sandbox` — Isolates prefix from host filesystem
2. `gdiplus` — Windows GDI+ rendering library  
3. `corefonts` — Arial, Times New Roman, etc.
4. `cjkfonts` — Chinese/Japanese/Korean font support (**run twice** due to known interop issue)
5. `dotnet48` — .NET Framework 4.8
6. `fontsmooth=rgb` — Subpixel font antialiasing
7. `winhttp` — Windows HTTP stack (needed for Autodesk licensing/cloud)
8. `win11` — Sets Windows version to 11 (reset after dotnet48 downgrades it)
9. `dxvk` — Vulkan-based DirectX 9/10/11 translation
10. `vkd3d` — Vulkan-based DirectX 12 translation

**Our codebase** (`src/install/30-prefix.sh`, line 22):
1. `vcrun2022` — Visual C++ 2022 runtime

### 2.2 Missing Verbs — Impact Analysis

| Verb | Critical? | Why |
|------|-----------|-----|
| `dotnet48` | **YES** | Fusion's licensing subsystem (AdskLicensingService.exe) requires .NET. Without it, offline mode may fail silently. Lolig4 installs it; we don't. |
| `winhttp` | **YES** | Autodesk's cloud login and license validation use Windows HTTP APIs. Without native winhttp, TLS and proxy support may break. |
| `gdiplus` | **Likely** | UI rendering for some older Fusion dialogs and font rendering. |
| `corefonts` | **Maybe** | Fusion ships its own fonts, but some UI elements reference system fonts. Missing corefonts can cause fallback to ugly bitmap fonts. |
| `dxvk` / `vkd3d` | **No** | GE-Proton bundles its own DXVK/VKD3D; winetricks versions may conflict. Lolig4's approach is actually *wrong* here — installing winetricks DXVK over Proton's can break things. |
| `cjkfonts` | **No** | Only needed for CJK locale users. |
| `fontsmooth=rgb` | **No** | Cosmetic only. |
| `sandbox` | **No** | Proton already isolates the prefix. |

**Recommendation**: We should add `dotnet48` and `winhttp` to our prefix initialization. The current `vcrun2022`-only approach is insufficient for reliable Fusion operation, especially for licensing.

### 2.3 DLL Overrides

**Lolig4** (lines 1859-1863):
```
adpclientservice.exe = native   → Prevents telemetry/metrics from loading
AdCefWebBrowser.exe = builtin   → Uses Wine's builtin browser engine for nav bar (DX9)
bcp47langs = (empty/disabled)   → Fixes locale string crash
```

**Our codebase**:
- No DLL overrides in `30-prefix.sh`
- `bcp47langs` handled via `WINEDLLOVERRIDES="bcp47langs="` environment variable in `apply_launch_environment()` (launcher-functions.sh, line ~502)
- `adpclientservice.exe` and `AdCefWebBrowser.exe` — not addressed

**Recommendation**: Add `adpclientservice.exe=native` and `AdCefWebBrowser.exe=builtin` overrides to our prefix setup. These are low-risk, well-tested improvements.

### 2.4 Registry Settings

**Lolig4** (lines 1864-1865):
```
HKCU\Software\Wine\X11 Driver\Managed = Y
HKCU\Software\Wine\X11 Driver\Decorated = Y
```

**Our codebase**:
- `Managed=Y` and `Decorated=Y` not explicitly set (rely on Wine defaults)
- We write `LogPixels` and `Win8DpiScaling` in `apply_fusion_wine_dpi()` (launcher-functions.sh, lines 310-345)
- We register `WineBrowser` for the bridge (line ~298)

**Additional Lolig4 registry (DXVK.reg)**:
```
*d3d10core = native
*d3d11 = native  
*d3d9 = builtin
*dxgi = native
```
These force DXVK for DirectX. GE-Proton does this automatically, so we don't need them.

### 2.5 GPU-Specific Configuration

**Lolig4**: Copies GPU-specific `NMachineSpecificOptions.xml` to three AppData locations based on detected GPU driver (DXVK or OpenGL). The DXVK version sets `VirtualDeviceDx11` while OpenGL sets `VirtualDeviceDx9`. Both set `SSLVerifyPeerOptionId=TrustAllServers` (disables SSL certificate validation — a security concern).

**Our codebase**: No GPU-specific configuration. We set `PROTON_USE_WINED3D` (OpenGL fallback), `DXVK_ASYNC`, and Intel Vulkan ICD paths via environment variables in `apply_launch_environment()`.

**Recommendation**: Consider adding `NMachineSpecificOptions.xml` configuration for GPUs where DXVK performs poorly. The `TrustAllServers` setting should NOT be adopted — it is a security anti-pattern.

### 2.6 Wine Source Patches

**Lolig4** applies two source patches to Wine/Proton:
- **`wine-captionless-popups.patch`**: Modifies `dlls/winex11.drv/window.c` `is_window_managed()` to return TRUE for owned WS_POPUP|WS_EX_TOOLWINDOW windows. This is the *same bug* our toolwindow fixer solves, but at the Wine source level instead of runtime.
- **`named-pipe-namespace-fix.patch`**: Fixes `server/named_pipe.c` race conditions where named pipes unlink too aggressively, breaking Autodesk's `adexmtsv` service.

**Our approach**: We solve the toolwindow z-order bug via a 172-line C daemon (`fusion-toolwindow-fixer.exe`) that runs under Wine and adds `WS_EX_APPWINDOW` to qualifying windows at runtime. No Wine rebuild needed.

**Trade-off**: Lolig4's source patch is more elegant (fix the root cause), but requires building Wine from source — fragile and time-consuming. Our runtime daemon works with any Wine/Proton version but adds a background process.

---

## 3. Usability Analysis

### 3.1 Desktop File Quality

**Lolig4** (`Autodesk Fusion.desktop`):
```
StartupWMClass=fusion360.exe          ← Correct; window manager can group windows
Categories=Education;Engineering;...  ← Good breadth
Icon=ECF6_Fusion360.0                 ← Uses Wine-extracted icon
Exec=bash -c '...'                    ← Launcher invocation
No MimeType=                          ← No file associations
GenericName[cs]=...                   ← 9 translated GenericNames
Comment[cs]=...                       ← 9 translated Comments
```

**Our codebase** (created in `40-fusion-installer.sh`):
- Desktop entry created at install time, not shipped as a file
- Includes MIME type associations for .f3d/.f3z
- No `StartupWMClass` set — window manager can't group Fusion windows
- No i18n
- Icon sourced from Fusion install directory

**Recommendation**: Add `StartupWMClass=fusion360.exe` to our desktop entry.

### 3.2 CLI Interface

**Our codebase** (`install.sh`):
```
--deps-only        Step 1 only
--ge-proton-only   Step 2 only
--prefix-only      Step 3 only
--uninstall        Interactive selective uninstall
--installer-path   Use local installer file
```
Clean, orthogonal flags. Good for CI/automation and partial recovery.

**Lolig4** (`autodesk_fusion_installer_x86-64.sh`):
```
$1 = --install | --uninstall | --build | --debug
$2 = fusion | inventor (software selection)
$3 = --wine | --fusion-wine | --proton=<version> (runner selection)
$4 = --full | (extension names)
```
Positional arguments, no `--help`, no self-documenting usage.

**Verdict**: Our CLI is much more user-friendly and automation-ready.

### 3.3 Install Flow

**Our codebase**: 12 sequential steps with clear labeling ("Step 3/12: GE-Proton"), progress reporting, idempotency checks at each step (skip if already done). User sees a Windows installer window with instructions.

**Lolig4**: Single large function chain. Has hardware checks (Secure Boot, RAM, VRAM, disk space, GPU driver, Firefox version) that we lack. These checks have descriptive user feedback. The installer self-copies to `~/.local/share/Autodesk-Unofficial/bin/` so it persists after install.

**Gap**: We should adopt hardware prerequisite checks (especially disk space and GPU driver detection).

### 3.4 Launcher Behavior

**Our launcher** (`src/bin/launch-fusion.sh`):
1. Health check (optional)
2. Load config (Python UI if first run)
3. Apply DPI settings to Wine registry
4. Register protocol handlers
5. Register Wine browser bridge
6. Start browser listener (background)
7. Start overlay killer (background)
8. Start toolwindow fixer (background)
9. Launch Fusion via Proton
10. Cleanup on exit (trap EXIT INT TERM)

Error recovery: `fail()` function with descriptive messages. `trap cleanup` ensures background processes are killed.

**Lolig4 launcher** (`autodesk_fusion_launcher.sh`):
1. Read prefix config file
2. Start AdskLicensingService (for Inventor)
3. Launch Fusion via Wine or Proton
4. Kill wineserver on exit

No DPI handling, no browser bridge, no background services, no cleanup trap.

**Verdict**: Our launcher has dramatically richer functionality and safety.

### 3.5 Protocol Handling

**Our codebase**: Registers three handlers:
- `adsk://` → `fusion360-callback-handler.desktop` (our callback handler script)
- `adskidmgr://` → Same handler
- `fusion360://` → `autodesk-fusion360.desktop` (our main desktop entry)
- **NLauncher.exe** registered inside Wine prefix for `.f3d` and `fusion360://` (enables ShellExecute from within Wine)

**Lolig4**: Registers one handler:
- `adskidmgr://` → `adskidmgr-opener.desktop` (launches AdskIdentityManager.exe via Wine)

**Verdict**: Our protocol handling is more complete. The NLauncher.exe registration is a unique feature that enables proper Windows-side file opening from within Fusion.

### 3.6 File Opening Flow

**Our codebase**: Full chain:
1. Linux user double-clicks `.f3d` file → `xdg-open` → `autodesk-fusion360.desktop` → `launch-fusion.sh /path/to/file.f3d`
2. `launch-fusion.sh` converts path to `Z:\path\to\file.f3d` and passes to Fusion360.exe
3. Inside Wine, if another Fusion process uses ShellExecute for `.f3d`, NLauncher.exe handles it

**Lolig4**: No file type associations. Files must be opened from within Fusion.

### 3.7 Multi-Install Support

**Lolig4**: Full multi-install support. Each install gets a timestamped prefix name (`fusion-20260728_123045`). Desktop files are stored in numbered subdirectories under `wine/Programs/Autodesk/`. `swap_desktop_files.sh` cycles between active installations. `active_<software>.log` tracks which is active.

**Our codebase**: Single install only. Fixed prefix path (`~/.fusion360-proton2`). No multi-install awareness.

**Recommendation**: Multi-install is useful for testing newer Fusion versions alongside stable ones. Consider adopting this pattern (but simpler — perhaps just named prefixes).

---

## 4. Performance Analysis

### 4.1 Unnecessary Sleeps

**Lolig4** has pervasive `sleep` calls throughout:
- `sleep 1` after color scheme setup
- `sleep 2` after package installation
- `sleep 2` before siappdll patching
- `sleep 5` after starting Steam
- `sleep 5` after Fusion installer completion
- `sleep 3` after starting licensing service
- `sleep 2` after deleting desktop files
- `sleep 1` before showing extension list
- ...and many more

These are used as synchronization primitives instead of proper polling/event detection.

**Our codebase**: Minimal sleeps. The installer polling loop (30 iterations × 10 seconds) uses `sleep 10` between checks, which is reasonable for a 5-minute timeout window. The toolwindow fixer sleeps 5 seconds between scan passes (necessary for a polling daemon).

### 4.2 Process Overhead

**Our codebase** starts three background processes during launch:
1. **Browser listener** (`fusion-browser-listener.sh`): Polls `/tmp/fusion360-browser-requests/` and `/tmp/fusion360-callback-requests/` directories. Inotify-based event loop → low CPU.
2. **Overlay killer** (`fusion-gray-overlay-event-killer.sh`): Monitors X11 client list events via `xprop -spy`. Reactive, not polling → low CPU.
3. **Toolwindow fixer** (`fusion-toolwindow-fixer.exe`): Polls every 5 seconds inside Wine via `EnumWindows`. Low overhead (40KB binary, `-Os` compiled).

All three are killed on Fusion exit via `cleanup()` trap.

**Lolig4**: No background processes. Simpler but lacks the fixes our daemons provide.

### 4.3 Startup Time

**Our launcher**: Serial initialization (~1-2 seconds total):
- DPI detection (fast gsettings/xrdb calls)
- Protocol handler registration (fast file writes)
- Browser bridge registration (fast grep + printf)
- Background process startup (non-blocking `&`)

**Lolig4 launcher**: Reads config files, starts licensing service (3s sleep), launches Fusion. Similar or faster startup.

### 4.4 Binary Size

Our `fusion-toolwindow-fixer.exe` is 40KB, compiled with `-Os -s` (optimize for size, strip symbols). This is negligible. It's a Win32 GUI app that runs inside the Wine prefix.

### 4.5 Hot Path Operations

**Our DPI application** (`apply_fusion_wine_dpi`): Uses `sed -i` on the Wine `user.reg` file. On each launch, this rewrites the registry file. For a ~200KB user.reg, this is sub-millisecond — not a concern.

**Our config loading**: Reads a simple `key=value` config file via `source`. Instant.

---

## 5. Safety & Error Handling

### 5.1 `set -euo pipefail` Coverage

**Our codebase**:
| Category | Has `set -euo pipefail` | Notes |
|----------|------------------------|-------|
| `install.sh` | YES | Line 13 |
| `uninstall.sh` | YES | Line 6 |
| `launch-fusion.sh` | NO | Uses `source launcher-functions.sh`; caller sets flags? **BUG**: line 13 has no `set -e` |
| `launcher-functions.sh` | NO | Intentionally sourced — caller manages flags |
| `health-check.sh` | NO | **BUG**: Standalone script, should have `set -euo pipefail` |
| Doctor modules | NO | Sourced by `doctor.sh` which has `set -euo pipefail` (L11) |
| Install step modules | NO | Sourced by `install.sh` which has `set -euo pipefail` |
| Runtime scripts | YES | All standalone runtime scripts have it |

**Lolig4**: **No `set -e` anywhere**. The entire 2,331-line installer and all support scripts run without any shell error detection. A failed `wget`, a missing file, a typo in a variable name — all silently ignored.

**Recommendation**: Add `set -euo pipefail` to `launch-fusion.sh` and `health-check.sh`.

### 5.2 Trap Handlers

**Our codebase**:
- `install.sh`: `trap 'rm -rf "$LOCK_DIR"' EXIT INT TERM` — lock file cleanup
- `launch-fusion.sh`: `trap cleanup EXIT INT TERM` — kills all three background processes + clears temp files
- `uninstall.sh`: No trap (one-shot operation)

**Lolig4**: No trap handlers anywhere.

### 5.3 Input Validation

**Our codebase**:
- `install.sh`: Root guard, lock file to prevent concurrent runs
- `uninstall.sh`: Root guard, `HOME` guard, timed confirmation prompt (120s)
- `launcher-functions.sh`: DPI value regex validation (`[[ "$dpi_value" =~ ^[0-9]+$ ]]`)
- `uninstall-select.sh`: Regex validation of user selection, confirmation before `rm -rf`

**Lolig4**: 
- `check_option()` validates the `--install/--uninstall/--build/--debug` flag
- No validation of runner argument, extension names, or paths
- `rm -rf` on user input without sanity checks in some paths

### 5.4 Race Conditions

**Our codebase**: The browser listener uses a `.partial` → `.request` atomic rename pattern to avoid readers seeing incomplete files. The callback handler also uses this pattern.

**Lolig4**: The named pipe namespace fix patch specifically addresses a race condition in Wine's named pipe implementation. Without this patch, Autodesk's `adexmtsv` service can experience intermittent connection failures.

### 5.5 Signal Handling

**Our codebase**: `cleanup()` in `launcher-functions.sh` properly handles SIGTERM escalation: sends TERM, waits, then sends KILL for survivors. The overlay killer monitors `_NET_CLIENT_LIST` changes and exits when the tracked Fusion window disappears.

**Lolig4**: `kill_process()` uses `kill -9` directly with no escalation. No signal propagation to child processes.

### 5.6 Log File Management

**Our codebase**:
- DPI log (`/tmp/fusion360-dpi.log`): Appended on each launch (`>>`). No rotation or size limit. **Risk**: grows unbounded over months of daily launches.
- Browser listener log: Appended. Same risk.
- Callback handler log: Appended. Same risk.
- Overlay killer log: Appended. Same risk.

**Lolig4**: Logs go to `$AUTODESK_ROOT_DIRECTORY/logs/$WINE_PFX_NAME/`. Each winetricks run creates a separate log file. `save_logfile()` copies these to a timestamped directory after install. Better organization.

**Recommendation**: Add log rotation or size limits to our persistent log files. Consider Lolig4's per-prefix log directory structure.

---

## 6. Code Quality

### 6.1 Modularity

**Our codebase**: Excellent modularity. The 12-step install pipeline means any step can be run independently for recovery. Runtime is split into focused scripts (browser listener, callback handler, overlay killer, toolwindow fixer). Functions are grouped in `launcher-functions.sh` with clear section headers.

**Lolig4**: Poor modularity. One 2,331-line monolithic file contains package management, Wine building, GPU detection, Fusion installation, Inventor installation, licensing setup, extension management, and uninstall logic. Functions are coupled through global variables. Impossible to test individual components.

### 6.2 Comment/Doc Quality

**Our codebase**: Good. Each file has a header describing its purpose. Functions have doc comments explaining behavior. Complex DPI resolution has inline comments explaining the detection chain. The toolwindow fixer C file has a thorough 14-line header explaining the problem and fix.

**Lolig4**: Heavy commenting but low signal. ASCII-art banner separators consume ~15% of the file. Function headers are boilerplate. Inline comments sometimes contradict code (e.g., "Still in progress!!!" markers on production paths).

### 6.3 Variable Naming

**Our codebase**: Consistent uppercase for config (`FUSION_WINE_DPI`), lowercase for locals, `SCREAMING_SNAKE_CASE` for exports. Clear separation between global config and local variables.

**Lolig4**: Mix of `UPPER_CASE`, `lower_case`, and `CamelCase`. Inconsistent across functions. Some names are misleading (e.g., `NEW_ID` is a fresh date-based ID every time, not a user choice).

### 6.4 Duplicated Code

**Our codebase**:
- Desktop entry creation duplicated in `40-fusion-installer.sh` (lines ~120 and ~165)
- `SCRIPT_DIR` calculation duplicated across runtime scripts (though `register-protocols.sh` and `launch-fusion.sh` use slightly different approaches)
- DPI detection logic duplicated between `launcher-functions.sh` (bash) and `launcher-config-user-interface.py` (Python) — the Python UI reimplements the same KDE/GNOME/Cinnamon/Xft detection chain

**Lolig4**: Massive duplication. The `set_wine_variables()` function pattern (Wine vs Proton binary detection) is repeated in both the installer and launcher. The `check_option()` function is essentially a giant case statement that could be separate functions.

### 6.5 ShellCheck Findings

Running `shellcheck` on our key files:

- `install.sh`: Clean (SC1091 for sourced files — expected)
- `launcher-functions.sh`: SC2086 (unquoted variables in `[[ ]]` — false positives for bash), SC2155 (declare+assign — minor style)
- `30-prefix.sh`: SC2015 (A && B || C pattern — should use if/then)
- `health-check.sh`: Missing `set -euo pipefail`, SC2086 on unquoted `$@`
- `uninstall-select.sh`: SC2086 on glob expansions, SC2207 (array assignment)

**Lolig4**: Not shellcheck-clean. Heavy use of unquoted variables, `echo -e` (bashism), missing error handling. Would generate hundreds of warnings.

### 6.6 Function Complexity

**Our codebase**:
- Most complex function: `resolve_fusion_wine_dpi()` (~80 lines, 7-branch cascade) — well-structured but long
- `apply_launch_environment()` (~90 lines, mostly repetitive env var assignments) — could be data-driven
- `save_config()` (~40 lines, string manipulation) — reasonable

**Lolig4**:
- `check_option()`: ~200 lines, deeply nested case statements
- `install_autodesk_fusion()`: Calls 10 sub-functions, deeply coupled
- `check_and_install_wine()`: ~200 lines of package manager detection

---

## 7. Features Gap Analysis

### 7.1 What Lolig4 Has That We Don't

| Feature | Priority | Effort | Notes |
|---------|----------|--------|-------|
| **GPU driver detection** | P1 | Medium | Checks nvidia/nouveau/amdgpu/radeon/i915; selects DXVK or OpenGL config. Critical for users with problematic GPU drivers. |
| **Hardware prerequisite checks** | P1 | Low | RAM (8GB min), VRAM (2GB min), disk space (15GB), Secure Boot status. Prevents "it doesn't work" support issues. |
| **Multi-install support** | P2 | High | Multiple prefixes, desktop file swapping. Nice-to-have for power users. |
| **dotnet48 and winhttp** | P0 | Low | See §2.2. Licensing and cloud features may fail without these. |
| **DLL overrides (adpclientservice, AdCefWebBrowser)** | P1 | Low | Simple registry additions. Suppresses telemetry, fixes nav bar rendering. |
| **i18n / localization** | P3 | High | 9-language support. Large effort; only if we have non-English users. |
| **Inventor support** | P3 | Very High | Full Inventor 2027 installation. Out of scope for now. |
| **Firefox version check** | P3 | Low | Ensures Snap Firefox isn't used (browser bridge). We already use Chrome/Chromium. |
| **SpaceMouse patching** | P2 | Medium | Patches siappdll.dll for 3D mouse support. |
| **NMachineSpecificOptions.xml** | P1 | Low | GPU-specific Fusion config. Prevents crashes on OpenGL-only setups. |
| **Wine source patches** | P2 | Very High | Captionless popups + named pipe fixes. Our toolwindow fixer handles the first; the second is a deeper Wine bug. |

### 7.2 What We Have That Lolig4 Doesn't

| Feature | Notes |
|---------|-------|
| **Python config UI** | Tkinter GUI with slider for DPI, path browser, flag toggles, countdown auto-launch. Huge usability win over editing config files. |
| **Doctor diagnostic tool** | 12-module health check covering env, deps, Proton, Fusion, config, bridge, processes, logs, install, network. Invaluable for support. |
| **Toolwindow fixer (C daemon)** | Runtime fix for z-order bug. Works with any Wine/Proton version. No source rebuild needed. |
| **File type associations** | MIME XML for .f3d/.f3z/.step/.stl/.iges; NLauncher.exe registration in Wine prefix; xdg-mime integration. |
| **Browser bridge** | Complete listener/callback system. Fusion's embedded browser → native Chrome/Firefox. |
| **Overlay killer** | Event-driven gray overlay closer. Watches X11 client list for the broken modal and closes it. |
| **NLauncher.exe registration** | Windows-side protocol/file handler inside the Wine prefix. Enables proper ShellExecute chains. |
| **Selective uninstall** | Interactive component-by-component removal with disk usage display. |
| **Cli/automation flags** | `--deps-only`, `--ge-proton-only`, `--prefix-only`, `--installer-path` — enables CI and recovery. |
| **Idempotent install steps** | Each step checks if already done and skips. Safe to re-run. |
| **DPI auto-detection chain** | KDE → GNOME → Cinnamon → Xft.dpi → fallback. Better than hardcoded DPI. |

### 7.3 What We Should Adopt from Lolig4

Ranked by impact/effort:

1. **`dotnet48` + `winhttp` winetricks verbs** (P0, 1 line change) — Fixes licensing/cloud
2. **GPU driver detection** (P1, ~50 lines) — Prevents OpenGL crashes on certain hardware
3. **DLL overrides** (P1, ~5 lines) — Telemetry suppression + nav bar fix
4. **NMachineSpecificOptions.xml deployment** (P1, ~20 lines) — GPU-specific Fusion config
5. **Hardware prerequisite checks** (P1, ~60 lines) — Better user experience
6. **Per-prefix log directories** (P2, ~10 lines) — Better log organization
7. **SpaceMouse siappdll patching** (P2, ~20 lines) — 3D mouse support
8. **Multi-install support** (P2, significant effort) — Useful but complex

---

## 8. Recommendations

### Priority 0 (Critical — Fix before next release)

1. **Add `dotnet48` and `winhttp` to prefix initialization**  
   File: `src/install/30-prefix.sh`, after line 33  
   Impact: Licensing and cloud features may fail silently without these  
   Effort: 3 lines

2. **Add `set -euo pipefail` to `launch-fusion.sh`**  
   File: `src/bin/launch-fusion.sh`, after line 2  
   Impact: Currently runs without error detection — a failed DPI application or missing config goes unnoticed  
   Effort: 1 line

3. **Add `set -euo pipefail` to `health-check.sh`**  
   File: `src/runtime/health-check.sh`, after line 3  
   Impact: Standalone script without error detection  
   Effort: 1 line

### Priority 1 (High — Fix next cycle)

4. **Add DLL overrides to prefix setup**  
   File: `src/install/30-prefix.sh`, add at end  
   ```bash
   # Suppress Autodesk telemetry, fix nav bar rendering
   STEAM_COMPAT_DATA_PATH="$PFX_DIR" \
   STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam" \
   "$proton" run wine reg add "HKCU\\Software\\Wine\\DllOverrides" /v "adpclientservice.exe" /t REG_SZ /d native /f 2>/dev/null || true
   STEAM_COMPAT_DATA_PATH="$PFX_DIR" \
   STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam" \
   "$proton" run wine reg add "HKCU\\Software\\Wine\\DllOverrides" /v "AdCefWebBrowser.exe" /t REG_SZ /d builtin /f 2>/dev/null || true
   ```
   Effort: 8 lines

5. **Add GPU driver detection to preflight**  
   File: `src/install/05-preflight.sh` or new `06-gpu.sh`  
   Detect nvidia/amdgpu/radeon/i915/nouveau and warn if on a known-problematic driver.  
   Effort: ~30 lines

6. **Add `StartupWMClass=fusion360.exe` to desktop entry**  
   File: `src/install/40-fusion-installer.sh`, desktop entry creation  
   Effort: 1 line

7. **Add log rotation or size limits**  
   Files: All scripts writing to `/tmp/fusion360-*.log`  
   Use `>>` with a size check or periodic truncation.  
   Effort: ~15 lines

### Priority 2 (Medium — Fix eventually)

8. **Deduplicate DPI detection between bash and Python**  
   Both `launcher-functions.sh` and `launcher-config-user-interface.py` implement the same KDE/GNOME/Cinnamon/Xft detection chain. Extract shared logic or have Python call the bash functions.  
   Effort: ~50 lines

9. **Add NMachineSpecificOptions.xml deployment**  
   Create GPU-specific config templates and deploy based on detected driver during install.  
   Effort: ~40 lines + config files

10. **Improve log directory structure**  
    Adopt Lolig4's per-prefix log directories under `~/.local/share/fusion360-linux/logs/`.  
    Effort: ~20 lines

### Priority 3 (Nice to have)

11. **Multi-install support** — Named prefixes, active-install tracking, desktop file swapping  
12. **Hardware prerequisite checks** — RAM, VRAM, disk space before install  
13. **i18n** — Only if non-English user demand exists  
14. **SpaceMouse siappdll patching** — Download and deploy patched DLL  
15. **Wine named-pipe-namespace-fix.patch** — Evaluate if `adexmtsv` failures occur on our setup; if so, contribute patch upstream to Wine

---

## Appendix A: Winetricks Verb Comparison Table

| Verb | Lolig4 | Our Codebase | Critical | Notes |
|------|--------|-------------|----------|-------|
| `sandbox` | ✓ | — | No | Proton isolates prefix already |
| `gdiplus` | ✓ | — | Likely | UI rendering for some dialogs |
| `corefonts` | ✓ | — | Maybe | System font fallback |
| `cjkfonts` | ✓ (×2) | — | No | CJK users only |
| `dotnet48` | ✓ | — | **YES** | Licensing subsystem |
| `fontsmooth=rgb` | ✓ | — | No | Cosmetic |
| `winhttp` | ✓ | — | **YES** | Cloud login, TLS |
| `win11` | ✓ | — | Maybe | Version check bypass |
| `dxvk` | ✓ | — | **No** | Proton bundles own; conflict risk |
| `vkd3d` | ✓ | — | **No** | Same as dxvk |
| `vcrun2022` | — | ✓ | Yes | VC++ runtime (already have) |

## Appendix B: File Count Summary

| | Our Codebase | Lolig4 Fork |
|---|-------------|-------------|
| Shell scripts | 37 | 25 |
| Total `.sh` lines | 3,284 | 4,128 |
| Largest file | 579 lines | 2,331 lines |
| Python files | 1 (432 lines) | 1 (speech toolkit, experimental) |
| C source files | 1 (172 lines) | 0 |
| Source patches | 0 | 9 (2 Fusion, 7 Inventor) |
| Prebuilt binaries | 1 (40KB .exe) | 1 (69.5KB .dll) |
| Desktop entries | 2 (generated) | 3 (shipped) |
| Locale files | 0 | 9 |
| Test files | 0 | 0 |
