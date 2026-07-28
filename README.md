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
dependencies, downloading GE-Proton, setting up the Wine prefix, configuring
DPI, running the Fusion installer, and registering file type associations.
Once complete, Fusion appears in your application launcher as a native app.

## ✨ Features

| Feature | Details |
|---------|---------|
| **File type associations** | `.f3d` / `.step` / `.stl` / `.3mf` / `.dxf` / `.obj` and 15 more — double-click opens in Fusion via NLauncher.exe, MIME icons in file manager |
| **Toolwindow z-order fix** | Custom Win32 daemon (`fusion-toolwindow-fixer.exe`, 40 KB) — adds `WS_EX_APPWINDOW` to docked panels so they stack behind other windows instead of floating on top |
| **WebView2 GPU acceleration** | `--ignore-gpu-blocklist`, `--enable-gpu-rasterization`, `--use-angle=d3d11` — smoother browser panels on iGPU |
| **DXVK tuning** | `syncInterval=0`, `tearFree=1`, `numBackBuffers=3` — reduced swapchain latency |
| **Reliable browser bridge** | 4-tier fallback: configured Chrome → `xdg-open` → `kde-open6`/`kde-open5` → known browsers.  Works with Snap Firefox on Ubuntu. |
| **Application + MIME icons** | Fusion logo extracted from the Wine prefix at install time, installed at 8 sizes for launcher, taskbar, and file manager |
| **DPI detection** | Auto-detects display scale (KDE → GNOME → xrdb → default), writes Wine DPI registry before Fusion installer runs |
| **Cloud sign-in** | dotnet48 + winhttp winetricks, DLL overrides for telemetry suppression, callback protocol handlers |
| **Doctor diagnostic** | `./doctor.sh` — full system check with `--quick` summary and `--save` report |
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
  2. xdg-open (universal, handles Snap Firefox)
  3. kde-open6 / kde-open5 (KDE native)
  4. google-chrome / chromium / firefox (direct binaries)
  ↓
Browser opens Autodesk sign-in page
  ↓ user logs in, browser redirects to fusion360-callback-handler.desktop
fusion-callback-handler.sh → callback URL → /tmp
fusion-browser-listener.sh → runs AdskIdentityManager.exe with callback
Fusion receives sign-in ✓
```

No passwords are written to files.  Short-lived URLs in `/tmp` only.

## Toolwindow Z-Order Fix

Fusion creates docked panels (browser, data panel, toolbar areas) as
`WS_POPUP` windows.  Under Wine's X11 driver these become override-redirect /
unmanaged, so the compositor keeps them above every other application.

`fusion-toolwindow-fixer.exe` is a background daemon compiled from C
(`src/toolwindow-fixer/fusion-toolwindow-fixer.c`) via `mingw-w64`.  It finds
Fusion-owned popup windows and adds `WS_EX_APPWINDOW` to their extended style.
This forces Wine to create them as *managed* windows that stack correctly behind
other apps and respond to minimize-to-taskbar.

Built from source at install time (no pre-built binary in the repo).

## Commands

| Command | Description |
|---------|-------------|
| `./install.sh` | Full install (all 12 steps) |
| `./install.sh --deps-only` | System packages only |
| `./install.sh --ge-proton-only` | Download + extract GE-Proton only |
| `./install.sh --prefix-only` | Init prefix + winetricks |
| `./install.sh --run-installer` | Launch Fusion installer only |
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
GPU driver setup, Vulkan troubleshooting, WebView2 performance, and
scale/DPI configuration.
