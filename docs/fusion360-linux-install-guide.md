# Fusion360 on Linux (KDE Neon / Ubuntu) — Installation Guide

## Overview

Fusion360 runs on Linux through **GE-Proton** (a Wine/Proton fork with gaming/graphics patches). The installer is a Windows `.exe` that downloads the actual Fusion360 packages from Autodesk's CDN via the webdeploy streamer.

The critical challenge is the **browser sign-in bridge**: Fusion's identity manager (AdskIdentityManager.exe) runs inside Wine/Proton and needs to open a browser for OAuth login, then receive the callback. The browser bridge in this repo handles that.

## System Requirements

- Linux x86_64 with XWayland or X11
- ~10GB free disk space for the Proton prefix + Fusion360
- Vulkan-capable GPU (or use `PROTON_USE_WINED3D=1` for OpenGL fallback)
- Patience: the installer downloads several GB over the network

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  Linux Desktop (KDE Plasma 6 / Wayland)                      │
│                                                               │
│  hub start (OOM-isolated process)                             │
│  └─ launch-fusion.sh                                          │
│     ├─ DPI detection (Cinnamon, KDE, or fallback)            │
│     ├─ register_wine_browser_bridge (WineBrowser registry)    │
│     ├─ install_callback_protocol_handlers (adsk:// handler)   │
│     ├─ start_browser_listener (background)                    │
│     ├─ start_overlay_killer (background)                      │
│     └─ Proton run Fusion360.exe                               │
│          └─ Wine prefix: ~/.fusion360-proton2/pfx/            │
│              ├─ Fusion360.exe                                 │
│              ├─ AdskIdentityManager.exe (login)               │
│              └─ msedgewebview2.exe (embedded sign-in UI)      │
│                                                               │
│  Browser Bridge (when WebView2 sign-in fails/needs browser):  │
│  ┌──────────────────────────────────────────────────────┐     │
│  │ 1. Fusion/Wine calls fusion-browser.sh (WineBrowser) │     │
│  │ 2. Writes URL to /tmp/fusion360-browser-requests/    │     │
│  │ 3. Listener picks it up, launches Firefox directly   │     │
│  │ 4. User signs in browser                             │     │
│  │ 5. Browser hits adskidmgr:// callback URL            │     │
│  │ 6. xdg-open → fusion-callback-handler.sh             │     │
│  │ 7. Writes callback to /tmp/fusion360-callback-req/   │     │
│  │ 8. Listener sends callback to AdskIdentityManager    │     │
│  │ 9. Proton runs identity manager with callback        │     │
│  │10. Fusion receives sign-in                            │     │
│  └──────────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────────┘
```

## Files & Config

### Repo layout (`/tmp/fusion360-fedora-fix/`)
```
launch-fusion.sh                     — Main launcher
scripts/
├── fusion-browser.sh                — Called by Wine to write sign-in URL
├── fusion-browser-listener.sh       — Linux-side listener (polls bridge dirs)
├── fusion-callback-handler.sh       — Handles adsk:// callback from browser
├── fusion-gray-overlay-event-killer.sh — Kills grey modal overlays
├── launcher-functions.sh            — Shared functions (DPI, env, cleanup)
├── launcher-config-user-interface.py — Tkinter config GUI
├── audit-fusion-prefix.sh           — Prefix diagnostic tool
└── kill-wine-proton-fusion-nuclear.sh — Nuclear kill switch
docs/
├── what-worked-what-didnt.md         — Status log
└── actions-log.md                    — Action history
Makefile                               — make run/kill/ps/log
```

### Config (`~/.config/fusion360-linux/config`)
Key variables:
- `PROTON` — Path to Proton executable
- `STEAM_COMPAT_DATA_PATH` — Proton prefix dir (NOT pfx itself)
- `STEAM_COMPAT_CLIENT_INSTALL_PATH` — Steam install dir
- `FUSION_ROOT` — Production dir containing Fusion360.exe
- `BROWSER` — WineBrowser script path
- `CHROME` — Linux browser binary for direct launch
- `FUSION_ENABLE_OVERLAY_KILLER` — Kill grey overlays (default 1)
- `FUSION_WINE_DPI` / `FUSION_WINE_SCALE_PERCENT` — HiDPI settings

### Bridge temp files (in `/tmp/`)
```
/tmp/fusion360-browser-requests/      — Sign-in URLs from Wine
/tmp/fusion360-browser-processed/     — Processed sign-in URLs
/tmp/fusion360-callback-requests/     — Callback URLs from browser
/tmp/fusion360-callback-processed/    — Processed callbacks
/tmp/fusion-browser-listener.log      — Listener log
/tmp/fusion-browser-bridge.log        — Wine browser script log
/tmp/fusion-callback-handler.log      — Callback handler log
/tmp/fusion360-dpi.log                — DPI resolution log
```

## Installation Steps

### 1. GE-Proton
```bash
mkdir -p ~/.local/share/Steam/compatibilitytools.d
tar -xzf GE-Proton11-3.tar.gz -C ~/.local/share/Steam/compatibilitytools.d/
```

### 2. Install Fusion360
```bash
export STEAM_COMPAT_DATA_PATH="$HOME/.fusion360-proton2"
export STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam"
"$HOME/.local/share/Steam/compatibilitytools.d/GE-Proton11-3/proton" run \
  "$HOME/Downloads/fusion360-linux-install/FusionClientDownloader.exe"
```

### 3. Install WebView2 (needed for embedded sign-in)
```bash
# Download bootstrapper: https://go.microsoft.com/fwlink/p/?LinkId=2124703
export STEAM_COMPAT_DATA_PATH="$HOME/.fusion360-proton2"
export STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam"
"$HOME/.local/share/Steam/compatibilitytools.d/GE-Proton11-3/proton" run \
  /tmp/MicrosoftEdgeWebview2Setup.exe
```

### 4. Register protocol handlers
```bash
xdg-mime default fusion360-callback-handler.desktop x-scheme-handler/adsk
xdg-mime default fusion360-callback-handler.desktop x-scheme-handler/adskidmgr
```

### 5. Launch
```bash
cd /tmp/fusion360-fedora-fix && ./launch-fusion.sh
```

## Patches Applied (KDE Neon / Ubuntu Specific)

### 1. GE-Proton version default
`launch-fusion.sh`: Changed from `GE-Proton10-32` to `GE-Proton11-3`.

### 2. Browser auto-detection
`launch-fusion.sh`: CHROME defaults probe `google-chrome > chromium-browser > chromium > firefox` instead of hardcoded `/usr/bin/google-chrome`.

### 3. Browser listener defaults path
`scripts/launcher-functions.sh` `load_config()`: BROWSER_LISTENER, CALLBACK_HANDLER, etc. defaulted to `$SCRIPT_DIR/` but scripts are in `$SCRIPT_DIR/scripts/`. Fixed.

### 4. KDE Plasma DPI detection
`scripts/launcher-functions.sh`: Added `read_kde_forced_dpi()` using `kreadconfig5` to read `forceFontDPI` from `~/.config/kdeglobals`.
Integrated into `resolve_fusion_wine_dpi()` — checked before Cinnamon, after explicit user settings.
Also added KDE DPI to `apply_fusion_wine_dpi()` logging.

### 5. KDE DPI in Python config UI
`scripts/launcher-config-user-interface.py`: Added `read_kde_forced_dpi()` and `detected_kde_scale_percent()`, called from `initial_scale_percent()`.

### 6. KDE/Plasma env vars for browser listener
`scripts/fusion-browser-listener.sh`: The listener uses `env -i` to strip environment (to prevent Wine contamination). On KDE Plasma 6 Wayland, `xdg-open`/`kde-open6` requires:
- `KDE_SESSION_VERSION=6` (Plasma 6, not 5)
- `WAYLAND_DISPLAY=wayland-0`
- `DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus`
- `XDG_RUNTIME_DIR=/run/user/1000`
- `XDG_CURRENT_DESKTOP=KDE`
- `XDG_SESSION_TYPE=wayland`

### 7. Direct browser launch (bypass xdg-open/kde-open)
**Critical fix.** On KDE Plasma 6, `xdg-open` calls `kde-open` which uses KDE's KIO infrastructure. With a stripped environment, `kde-open` falls back to `kioexec`, which **downloads the URL's content to a local file** and opens that file. For an OAuth URL like `https://.../authorize?client_id=...`, this means Firefox opens `file:///.../krun/.../authorize` instead of navigating to the real URL.

**Fix**: Launch Firefox directly with the URL instead of going through `xdg-open`. The listener now reads `$CHROME` from the environment (defaulting to `firefox`) and runs:
```bash
"$browser_bin" "$url" &
```

### 8. Async browser launch (non-blocking listener)
`xdg-open`/`kde-open` and even direct Firefox launch block until the browser exits. The listener's main loop processes browser AND callback requests sequentially. If the browser launch is synchronous, the listener can't process the sign-in callback.

**Fix**: Background the browser launch with `&` + `disown`.

### 9. Callback handler request writing
`scripts/fusion-callback-handler.sh`: During verbose logging edits, the `printf "%s\n" "$1" > "$partial_file"` and `mv "$partial_file" "$request_file"` lines were accidentally deleted. The handler logged the callback URL but never wrote the request file, so the listener never saw it.

## Common Issues & Fixes

### "You need the Microsoft WebView2 component"
Install the WebView2 Evergreen Runtime in the Proton prefix. Download the bootstrapper from Microsoft and run through Proton. Also apply Wine bug workarounds:
```bash
# Set edgeupdate service to manual start
regedit /tmp/edgeupdate-service.reg
# Kill MicrosoftEdgeUpdate processes
pkill -f "MicrosoftEdgeUpdate.exe"
```

### "Sign-in opens file:///.../authorize instead of the real URL"
See patch #7 above. `kde-open` uses `kioexec` which downloads URLs as local files. Bypass by launching Firefox directly.

### "Fusion freezes when clicking sign in"
The browser listener was blocked on `xdg-open` waiting for Firefox to close. See patch #8. Use `&` + `disown`.

### "Fusion says signed in but doesn't proceed"
Either the callback handler didn't write the request file (see patch #9) or the listener couldn't find `AdskIdentityManager.exe` in the Proton prefix. Check `fusion-browser-listener.log` for `identity_manager_executable` path and `callback_status`.

### OOM kills
The Fusion360.exe process itself uses ~3.3GB RAM. Always launch through `hub start` (or `setsid`/`nohup`) to keep it in a separate process group from your agent/shell. If the kernel OOM-kills the Fusion process, it won't cascade.

## Verification

Check the bridge is working end-to-end by monitoring these files:

1. **Sign-in requested**: `/tmp/fusion360-browser-requests/` should get a `.request` file
2. **Browser opened**: `/tmp/fusion-browser-listener.log` shows `type=browser` and the URL
3. **Callback received**: `/tmp/fusion-callback-handler.log` shows the `adskidmgr:/login?...` URL
4. **Callback written**: `/tmp/fusion360-callback-requests/` gets a `.request` file
5. **Callback processed**: `/tmp/fusion360-callback-processed/` gets the processed file, log shows `callback_status=0`
6. **Neutron log**: `~/.fusion360-proton2/.../Neutron Platform/logs/` shows `IDSDK immediatly returned success`

## Makefile Commands
```bash
make run   # Launch Fusion360
make kill  # Kill all Fusion/Proton processes
make ps    # List running Fusion processes
make log   # Tail latest Neutron log
```
