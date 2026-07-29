# Autodesk Fusion 360 on Linux

Run Fusion 360 through GE-Proton/Wine with working sign-in, file associations,
MIME icons, and z-order fixes.  Tested daily on KDE Plasma 6 (Wayland).

## Quick Start

```bash
git clone https://github.com/stonegray/fusion360-linux.git
cd fusion360-linux
./install.sh
```

The installer walks through 12 steps automatically — installing system
dependencies, downloading GE-Proton, downloading Fusion 360 (no Autodesk
account needed), setting up the Wine prefix, configuring DPI, running the
Fusion installer, and registering file type associations.  Once complete,
Fusion appears in your application launcher as a native app.

## ✨ Features

| Feature | Details |
|---------|---------|
| **Auto-download without sign-in** | The installer fetches Fusion 360 directly from Autodesk's CDN — no Autodesk account required to download.  Just run `./install.sh`. |
| **File type associations** | `.f3d` / `.step` / `.stl` / `.3mf` / `.dxf` / `.obj` and 15 more — double-click opens in Fusion via NLauncher.exe, MIME icons in file manager |
| **Toolwindow z-order fix** | Custom Win32 daemon (`fusion-toolwindow-fixer.exe`, 40 KB) — adds `WS_EX_APPWINDOW` to docked panels so they stack behind other windows instead of floating on top |
| **Auto-detect install completion** | The installer watches Fusion's streamer log for "Configure app complete" and steps 10 → 11 automatically.  No manual "click next" intervention. |
| **WebView2 file dialog fix** | Bypasses seccomp (`PROTON_NO_SECCOMP=1`) to prevent SIGSYS on WebView2's Mojo named platform channel pipe — no custom Wine build required |
| **msedgewebview2.exe Windows version override** | Wine AppDefaults set `msedgewebview2.exe` to report as Windows 8 (not 7) to match WebView2 runtime expectations for Mojo IPC |
| **Reliable browser bridge** | 4-tier fallback: configured Chrome → `kde-open6`/`kde-open5` → `xdg-open` → known browsers.  Works with Snap Firefox on Ubuntu. |
| **Config UI** | Python Tkinter GUI (`launcher-config-user-interface.py`) for toggling overlay killer, toolwindow fixer, WebView2 GPU, async shaders — no config file editing required |
| **DPI detection** | Auto-detects display scale (KDE → GNOME → xrdb → default), writes Wine DPI registry before Fusion installer runs |
| **Cloud sign-in** | dotnet48 + winhttp winetricks, DLL overrides for telemetry suppression, callback protocol handlers |
| **Auto dark mode** | Detects KDE/GNOME/GTK dark scheme via `kreadconfig5`/`gsettings`/`settings.ini`, writes Windows registry `AppsUseLightTheme=0` — Fusion matches your desktop theme |
| **IE proxy fix** | Applies `winhttp=b` DLL override to skip Windows IE proxy detection API — saves ~10s of startup time on every launch |
| **Preflight checks** | Step 2 validates Vulkan driver, disk space, and existing prefix before proceeding |
| **Doctor diagnostic** | `./doctor.sh` — full system check with `--quick` summary, `--save` report, and color output |
| **Graceful process kill** | `kill_fusion_processes()` sends SIGTERM, waits 2s, escalates to SIGKILL — used by cleanup and uninstall |
| **Cross-distro packages** | Debian / Ubuntu, Fedora, Arch, OpenSUSE, Void, Solus |

## How the Browser Bridge Works

Fusion/Wine needs to open URLs (sign-in pages) and receive callbacks.  Since the
Wine sandbox can't reach the Linux host browser directly, a file-based relay
handles it:

```
Fusion 360 / Wine
  ↓ sets BROWSER → fusion-browser.sh → URL file written to /tmp
fusion-browser-listener.sh  (background daemon)
  ↓ attempts in order:
  1. CHROME (from config) —— fastest path
  2. kde-open6 / kde-open5 (KDE native, most reliable)
  3. xdg-open (last resort on KDE, broken under Wayland; universal elsewhere)
  4. google-chrome / chromium / firefox (direct binaries)
Browser opens Autodesk sign-in page
  ↓ user logs in, browser redirects to fusion360-callback-handler.desktop
fusion-callback-handler.sh → callback URL → /tmp
fusion-browser-listener.sh → runs AdskIdentityManager.exe with callback
Fusion receives sign-in ✓
```

No passwords are written to files.  Short-lived URLs in `/tmp` only.

## Toolwindow Z-Order Fix

Fusion creates docked panels (browser, data panel, toolbar areas) as
`WS_POPUP` windows.  Under Wine's X11 driver, `WS_POPUP` without
`WS_EX_APPWINDOW` becomes an **override-redirect** X11 window — the
compositor treats it as unmanaged, keeps it above every other application,
and skips it for minimize-to-taskbar.

`fusion-toolwindow-fixer.exe` is a 40 KB Win32 background daemon compiled
from C (`src/toolwindow-fixer/fusion-toolwindow-fixer.c`) via `mingw-w64`,
built from source at install time.  It runs in a 5-second scan loop:

1. Finds the Fusion 360 process (`CreateToolhelp32Snapshot`)
2. Enumerates all Fusion-owned windows (`EnumWindows`)
3. For each `WS_POPUP` window with an owner (child panel):
   - Skips windows already having `WS_EX_APPWINDOW`
   - Skips dialogs (those with `WS_CAPTION`, `WS_DLGFRAME`, or `WS_SYSMENU`)
   - Skips invisible and zero-size helper windows
4. Adds `WS_EX_APPWINDOW` to the extended style via `SetWindowLongPtrW`
5. Calls `SetWindowPos` with `SWP_FRAMECHANGED` to transition the
   window from override-redirect → managed, preserving its position

This is equivalent to what the Wine source patch in Lolig4's
`GE-Proton11-Fusion` fork does in `window_set_managed()`, but applied at
runtime — no custom Wine build required.

## WebView2 Mojo IPC & Seccomp Bypass

Fusion 360's embedded browser (WebView2 / Edge Chromium) uses Mojo IPC —
Chromium's internal inter-process communication system — for communication
between the browser process and its renderer, GPU, and utility processes.
On Linux, Mojo can use **named platform channels** (named pipes under the
hood) for this IPC.

Other solutions (e.g. `GE-Proton11-Fusion`) require building a custom
GE-Proton binary with a Wine server patch that keeps named pipe
namespace entries alive across Mojo reconnect gaps.  Our approach
achieves the same result without modifying Wine.

### Our Approach (No Wine Patch Needed)

Instead of patching Wine, we apply three complementary workarounds:

1. **`PROTON_NO_SECCOMP=1`** — Tells `wine64-preloader` to skip seccomp
   filter installation entirely.  The blocked syscall is now allowed,
   so Mojo named pipes work.  Seccomp in Proton is a compatibility
   mechanism, not a security boundary — removing it adds no practical risk.
2. **`msedgewebview2.exe` AppDefaults `Version=win8`** — Forces the
   WebView2 process to report as Windows 8 instead of the Wine default
   (Windows 7).  The WebView2 runtime uses different Mojo IPC paths
   depending on the reported Windows version; Windows 7 triggers a
   compatibility code path that doesn't interact well with Wine's named
   pipe implementation.
3. **`WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--no-sandbox`** — Disables
   Chromium's own sandbox, which would otherwise conflict with Wine's
   process model and cause additional Mojo connection failures.

These settings are applied at install time (Wine prefix registry) and
re-applied at every launch, ensuring they survive prefix resets.

## File Type Associations

The installer registers Fusion 360 as the default handler for **20 CAD
formats**.  Double-clicking a `.f3d` file (or `.step`, `.stl`, `.3mf`,
etc.) in your file manager opens it in Fusion.

### How It Works

```
File manager / xdg-open
  ↓ looks up default for application/vnd.autodesk.fusion360
autodesk-fusion360.desktop
  ↓ Exec → launch-fusion.sh %F
launch-fusion.sh
  ↓ passes file path to Proton
Proton → NLauncher.exe "%1"
  ↓ connects to running Fusion via Forge IPC
Fusion opens the file  ✓
```

Key details:

- **NLauncher.exe** is Fusion's lightweight bridge process.  It's registered
  as the handler for both `.f3d` (via `Fusion360.AssocDocument`) and the
  `fusion360://` protocol in the Wine prefix's `system.reg`.  When invoked,
  it communicates with the running Fusion process through Autodesk's "Forge"
  IPC — avoiding the multiple-instances error.
- **MIME XML** (`src/install/data/fusion360-mime.xml`) defines the mapping
  between file extensions and MIME types.  Installed to
  `~/.local/share/mime/packages/` and indexed via `update-mime-database`.
- **MIME + app icons** — the Fusion logo is extracted from the Wine prefix's
  `Fusion360.ico` (or via `wrestool` from `Fusion360.exe`), converted to PNG,
  and installed at 8 standard sizes (16–256 px) into both
  `hicolor/*/apps/` (launcher, taskbar) and `hicolor/*/mimetypes/`
  (file manager icons).  No copyrighted assets in the repo — extracted at
  install time.
- **`xdg-mime default`** sets Fusion as the default for
  `application/vnd.autodesk.fusion360` so `xdg-open` routes `.f3d` files
  to the desktop entry.
- **Desktop entry** is placed in `~/.local/share/applications/fusion360-linux/`
  with `MimeType=` listing all 20 formats, so application menus and file
  managers discover the associations without manual config.

## Commands

| Command | Description |
|---------|-------------|
| `./install.sh` | Full install (all 12 steps) |
| `./install.sh --deps-only` | System packages only |
| `./install.sh --ge-proton-only` | Download + extract GE-Proton only |
| `./install.sh --prefix-only` | Init prefix + winetricks |
| `./install.sh --run-installer` | Launch Fusion installer only |
| `./install.sh --installer-path /path/to/exe` | Launch installer with local EXE |
| `./install.sh --kill` | Kill all Fusion/Wine/Proton processes |
| `./install.sh --uninstall` | Interactive selective uninstall |
| `./doctor.sh` | Full diagnostic |
| `./doctor.sh --quick` | Summary check |
| `./doctor.sh --save` | Write report to file |
| `./uninstall.sh` | Remove everything |
| `./uninstall.sh --select` | Choose components to remove interactively |

## Repository Structure

```
├── install.sh                     # Full installer (12 steps)
├── doctor.sh                      # Diagnostic tool
├── uninstall.sh                   # Clean removal
├── src/
│   ├── install/                   # Install step scripts
│   │   ├── 00-common.sh           #   Shared helpers, color output
│   │   ├── 05-preflight.sh        #   Vulkan / disk space checks
│   │   ├── 10-deps.sh             #   System packages
│   │   ├── 20-ge-proton.sh        #   GE-Proton download + extract
│   │   ├── 25-install-to-location.sh  #   Copy to XDG data dirs
│   │   ├── 30-prefix.sh           #   Prefix init + winetricks
│   │   ├── 35-webview2.sh         #   WebView2 runtime
│   │   ├── 37-config.sh           #   Config file generation
│   │   ├── 38-dpi.sh              #   DPI detection + Wine registry
│   │   ├── 40-fusion-installer.sh #   Fusion installer + completion detect
│   │   ├── 45-filetypes.sh        #   Desktop entry, MIME icons, NLauncher reg
│   │   ├── distro/                #   Per-distro package lists
│   │   └── data/
│   │       └── fusion360-mime.xml #   MIME type definitions (20 formats)
│   ├── runtime/                   # Deployed runtime scripts
│   │   ├── launcher-config-user-interface.py
│   │   ├── fusion-browser.sh
│   │   ├── fusion-browser-listener.sh
│   │   ├── fusion-callback-handler.sh
│   │   ├── fusion-gray-overlay-event-killer.sh
│   │   ├── register-protocols.sh
│   │   ├── health-check.sh
│   │   ├── uninstall-select.sh
│   │   └── audit-fusion-prefix.sh
│   ├── toolwindow-fixer/          # C source for z-order fix daemon
│   │   ├── fusion-toolwindow-fixer.c
│   │   └── Makefile
│   └── doctor/                    # Diagnostic checks
└── docs/
    ├── troubleshooting.md
    └── compatibility.md
```

## Supported Distros

| Distro | Status | Notes |
|--------|--------|-------|
| KDE Neon 24.04 | ✅ Daily testing | All features verified |
| Ubuntu 24.04 | ✅ Supported | Same base, GNOME DPI detection via gsettings |
| Fedora 40+ | ✅ Supported | Package lists included |
| Arch Linux | ✅ Supported | Package lists included |
| OpenSUSE Tumbleweed | ✅ Supported | Package lists included |
| Debian 12+ | ✅ Supported | Uses debian.txt packages |
| Void Linux | ✅ Supported | Package lists included |
| Solus | ✅ Supported | Package lists included |

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md) for known issues:
GPU driver setup, Vulkan troubleshooting, scale/DPI configuration, and
WebView2 behavior under Wine.
