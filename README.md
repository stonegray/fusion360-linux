# Autodesk Fusion 360 on Linux

Run Fusion 360 through GE-Proton/Wine with working sign-in, file associations,
MIME icons, and z-order fixes.  Tested daily on KDE Plasma 6 (Wayland).

## Quick Start

```bash
./install.sh       # Full install (deps → Proton → prefix → Fusion)
./launch-fusion.sh # Launch Fusion 360
```

The installer walks through 12 numbered steps automatically.  The Fusion GUI
installer will pop up — click through it, then step 10 detects completion and
continues.

## ✨ What's New

| Feature | Details |
|---------|---------|
| **File type associations** | `.f3d` / `.step` / `.stl` / `.3mf` / `.dxf` / `.obj` and 15 more — double-click opens in Fusion via NLauncher.exe, MIME icons in file manager |
| **Toolwindow z-order fix** | `fusion-toolwindow-fixer.exe` (cross-compiled C daemon) — adds `WS_EX_APPWINDOW` to docked panels so they stack behind other windows instead of floating on top |
| **WebView2 GPU acceleration** | `--ignore-gpu-blocklist`, `--enable-gpu-rasterization`, `--use-angle=d3d11` — smoother browser panels on iGPU |
| **DXVK tuning** | `syncInterval=0`, `tearFree=1`, `numBackBuffers=3` — reduced swapchain latency |
| **Reliable browser bridge** | 4-tier fallback: configured Chrome → `xdg-open` → `kde-open6`/`kde-open5` → known browsers. Works with Snap Firefox. |
| **Application + MIME icons** | Fusion logo extracted from prefix at install time, installed to 8 sizes in both `apps/` and `mimetypes/` for launcher, taskbar, and file manager |
| **DPI before installer** | DPI registry keys applied before the Fusion installer runs — correct scaling from first launch |
| **dotnet48 + winhttp** | Winetricks for licensing & cloud sign-in |
| **Doctor diagnostic** | `./doctor.sh` — full system check with color output, `--quick` summary, `--save` report |
| **Unified install output** | Consistent `log_step / log_info / log_pass / log_warn / log_fail` formatting across all 12 steps |
| **Preflight check** | Step 2 validates Vulkan, disk space, existing prefix before proceeding |
| **Cross-distro packages** | Debian, Fedora, Arch, OpenSUSE, Void, Solus |

## Install Steps

| # | Step | File | Description |
|---|------|------|-------------|
| 1 | System dependencies | `10-deps.sh` | Install packages (icoutils, zenity, mingw-w64, ImageMagick, etc.) |
| 2 | Preflight | `05-preflight.sh` | Vulkan check, disk space, existing prefix detection |
| 3 | GE-Proton | `20-ge-proton.sh` | Download + extract GE-Proton |
| 4 | Install to system | `25-install-to-location.sh` | Copy scripts to XDG data dir, MIME database |
| 5 | Proton prefix | `30-prefix.sh` | Init prefix, winetricks (dotnet48, winhttp, vcrun2022) |
| 6 | WebView2 | `35-webview2.sh` | Download + install WebView2 runtime |
| 7 | Configuration | `37-config.sh` | Generate `~/.config/fusion360-linux/config` |
| 8 | Protocol handlers | `register-protocols.sh` | `fusion360://`, `adsk://`, `adskidmgr://` for sign-in |
| 9 | DPI | `38-dpi.sh` | Detect display scale → write Wine DPI registry |
| 10 | Fusion installer | `40-fusion-installer.sh` | Download + run Fusion installer, detect completion |
| 11 | File types | `45-filetypes.sh` | Desktop entry, MIME icons, NLauncher registry, toolwindow fixer build |
| 12 | Health check | `health-check.sh` | Verify prefix, Proton, config |

## How the Browser Bridge Works

Fusion/Wine needs to open URLs (sign-in pages) and receive callbacks.  Since the
Wine sandbox can't reach the Linux host browser directly, a file-based bridge
relays the requests:

```
Fusion 360 / Wine
  ↓ sets BROWSER to fusion-browser.sh
  ↓ writes URL to /tmp/fusion360-browser-requests/
fusion-browser-listener.sh  (background daemon)
  ↓ attempts in order:
  1. CHROME (from config) —— fastest path
  2. xdg-open (universal, handles Snap Firefox)
  3. kde-open6 / kde-open5 (KDE native)
  4. google-chrome / chromium / firefox (direct binaries)
  ↓
Browser opens the Autodesk sign-in page
  ↓ user logs in
  ↓ redirects to fusion360-callback-handler.desktop
fusion-callback-handler.sh
  ↓ writes callback URL to /tmp/fusion360-callback-requests/
fusion-browser-listener.sh
  ↓ runs AdskIdentityManager.exe with callback URL
Fusion receives sign-in ✓
```

No passwords are written to files.  Short-lived URLs in `/tmp` only.

## Toolwindow Z-Order Fix

Fusion creates docked panels (browser, data panel, toolbar areas) as
`WS_POPUP` windows.  Under Wine's X11 driver these become override-redirect /
unmanaged, so the compositor keeps them above every other application.

`fusion-toolwindow-fixer.exe` is a background daemon compiled from C
(`src/toolwindow-fixer/fusion-toolwindow-fixer.c`) via `mingw-w64`.  It finds
Fusion-owned popup windows and adds `WS_EX_APPWINDOW` to their extended style,
making Wine's driver create them as *managed* windows that stack correctly
behind other apps and respect minimize-to-taskbar.

Build at install time (no pre-built binary in repo):

```bash
x86_64-w64-mingw32-gcc -Os -s -o fusion-toolwindow-fixer.exe fusion-toolwindow-fixer.c -luser32
```

## Commands

| Command | Description |
|---------|-------------|
| `./install.sh` | Full 12-step install |
| `./install.sh --deps-only` | System packages only |
| `./install.sh --ge-proton-only` | Download + extract GE-Proton only |
| `./install.sh --prefix-only` | Init prefix + winetricks |
| `./install.sh --run-installer` | Launch Fusion installer only |
| `./launch-fusion.sh` | Launch Fusion 360 |
| `./launch-fusion.sh --configure` | Interactive path configuration |
| `./doctor.sh` | Full diagnostic |
| `./doctor.sh --quick` | Summary check |
| `./doctor.sh --save` | Write report to file |
| `./uninstall.sh` | Remove everything |
| `./uninstall.sh --select` | Choose components to remove |
| `make run` | Launch (alias) |
| `make kill` | Force-kill all Fusion/Wine processes |
| `make ps` | Check if running |
| `make log` | View Fusion log |

## Repository Structure

```
├── install.sh                     # Full installer (12 steps)
├── launch-fusion.sh               # Main launcher
├── uninstall.sh                   # Clean removal
├── doctor.sh                      # Diagnostic entry point
├── Makefile                       # run/kill/ps/log
├── src/
│   ├── bin/
│   │   └── launch-fusion.sh       # Deployed launcher
│   ├── install/
│   │   ├── 00-common.sh           # Shared helpers, colors
│   │   ├── 00-defaults.sh         # XDG path constants
│   │   ├── 05-preflight.sh        # Preflight checks
│   │   ├── 10-deps.sh            # System packages
│   │   ├── 20-ge-proton.sh       # GE-Proton download
│   │   ├── 25-install-to-location.sh  # Copy to XDG dirs
│   │   ├── 30-prefix.sh          # Prefix init + winetricks
│   │   ├── 35-webview2.sh        # WebView2 runtime
│   │   ├── 37-config.sh          # Config file generation
│   │   ├── 38-dpi.sh             # DPI detection + application
│   │   ├── 40-fusion-installer.sh # Fusion installer + completion detect
│   │   ├── 45-filetypes.sh       # Desktop entry, MIME icons, toolwindow fixer
│   │   ├── distro/               # Per-distro package lists
│   │   └── data/
│   │       └── fusion360-mime.xml # MIME type definitions for 20 formats
│   ├── runtime/                    # Scripts used at launch
│   │   ├── launcher-functions.sh  # DPI, browser bridge, icon extraction
│   │   ├── launcher-config-user-interface.py  # Python config UI
│   │   ├── fusion-browser.sh      # URL request writer (called by Wine)
│   │   ├── fusion-browser-listener.sh  # URL → browser daemon
│   │   ├── fusion-callback-handler.sh    # Sign-in callback receiver
│   │   ├── fusion-gray-overlay-event-killer.sh  # Stale overlay cleanup
│   │   ├── register-protocols.sh  # Protocol handler desktop entries
│   │   ├── health-check.sh        # Post-install verification
│   │   ├── uninstall-select.sh    # Selective uninstall menu
│   │   └── audit-fusion-prefix.sh # Prefix inspection
│   ├── toolwindow-fixer/           # C source for z-order fix daemon
│   │   ├── fusion-toolwindow-fixer.c
│   │   └── Makefile
│   └── doctor/                     # Diagnostic modules (10 checks)
│       ├── doctor.sh
│       ├── 00-common.sh
│       └── 10-*.sh
└── docs/
    ├── troubleshooting.md
    ├── compatibility.md           # Ubuntu & distro compatibility
    └── install-guide.md
```

## Supported Distros

| Distro | Status | Notes |
|--------|--------|-------|
| KDE Neon 24.04 | ✅ Daily testing | All features verified |
| Ubuntu 24.04 | ✅ Supported | Same base; our MIME icons use spec-compliant hicolor theme, DPI detects GNOME scaling |
| Fedora 40+ | ✅ Supported | Package lists included |
| Arch Linux | ✅ Supported | Package lists included |
| OpenSUSE Tumbleweed | ✅ Supported | Package lists included |
| Debian 12+ | ✅ Supported | Uses debian.txt packages |
| Void Linux | ✅ Supported | Package lists included |
| Solus | ✅ Supported | Package lists included |

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md) for known issues:
GPU driver setup, Vulkan troubleshooting, WebView2 performance, and
scale/DPI configuration.
