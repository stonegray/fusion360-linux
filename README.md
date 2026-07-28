# Fusion 360 on Linux

Self-contained helper scripts for running Autodesk Fusion 360 on Linux through Proton/GE-Proton with working sign-in, browser bridge, and gray overlay fix.

## Quick Start (3 Phases)

### Phase 1: System Prep

Install system dependencies and create required directories:

```bash
./install.sh
```

This installs packages (icoutils, zenity, wget, xdg-utils, etc.), creates `~/.fusion360-proton2/` and `~/.local/share/Steam/compatibilitytools.d/`, then prints instructions for Phase 2.

### Phase 2: Install Fusion 360

Download GE-Proton and run the Fusion installer manually (the installer is GUI-only):

```bash
# Download GE-Proton
wget https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton11-3/GE-Proton11-3.tar.gz
tar -xf GE-Proton*.tar.gz -C ~/.local/share/Steam/compatibilitytools.d/

# Run the Fusion installer through Proton
STEAM_COMPAT_DATA_PATH="$HOME/.fusion360-proton2" \
STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam" \
~/.local/share/Steam/compatibilitytools.d/GE-Proton11-3/proton run \
  ~/Downloads/fusion360-linux-install/FusionClientDownloader.exe
```

Click through the installer GUI. When it shows "Finish", Phase 2 is done.

### Phase 3: Finalize Configuration

```bash
./setup-fusion.sh
```

This installs WebView2 into the Proton prefix, writes configuration, registers protocol handlers (`adsk://`, `adskidmgr://`), extracts application icons, and installs a desktop entry. Re-runnable any time.

### Launch

```bash
./launch-fusion.sh
# Or
make run
```

## Commands Reference

| Command | Description |
|---------|-------------|
| `make run` | Launch Fusion 360 |
| `make kill` | Force-kill all Fusion/Wine processes |
| `make ps` | Check if Fusion is running |
| `make log` | View Fusion log output |
| `./launch-fusion.sh --configure` | Interactive path configuration |
| `./status.sh` | Diagnostic: check all prerequisites |
| `./setup-fusion.sh` | Re-run post-install configuration |
| `./setup-fusion.sh --force` | Re-do all config steps |
| `./uninstall.sh` | Remove Fusion, config, icons, desktop entries |

## Platform Support

| Distro | Status | Notes |
|--------|--------|-------|
| KDE Neon 24.04 | Tested 2026-07-28 | All patches verified, all features working |
| Ubuntu 24.04 | Likely works | Same base; adjust env vars if not on KDE |
| Fedora | Upstream target | Original scripts designed for Fedora; may not need all patches |
| Arch | Untested | Package names may differ; see install.sh distro detection |
| openSUSE | Added | Package names included in install.sh |
| Other | Manual deps | install.sh exits with manual package list for unknown distros |

## How It Works

The launcher handles three separate jobs:

1. **Start Fusion 360** through Proton.
2. **Bridge sign-in** from Wine/Proton to your Linux browser.
3. **Bridge the callback** back into Proton's Identity Manager.

```
Fusion / Wine
  -> fusion-browser.sh
  -> /tmp/fusion360-browser-requests
  -> fusion-browser-listener.sh
  -> xdg-open Autodesk login URL
  -> browser login
  -> xdg protocol handler
  -> fusion-callback-handler.sh
  -> /tmp/fusion360-callback-requests
  -> fusion-browser-listener.sh
  -> Proton runs AdskIdentityManager.exe with callback URL
  -> Fusion receives sign-in
```

No passwords are written to files. The bridge writes short-lived URLs and callback tokens only.

## Repository Structure

```
├── install.sh                 # Phase 1: system deps, dirs, prints next steps
├── setup-fusion.sh            # Phase 3: WebView2, handlers, config, icons
├── status.sh                  # Diagnostic: checks all prerequisites
├── uninstall.sh               # Clean removal
├── launch-fusion.sh           # Main launcher (runtime)
├── Makefile                   # make run/kill/ps/log
├── README.md                  # This file
├── scripts/                   # Runtime scripts (used by launch-fusion.sh)
│   ├── fusion-browser.sh
│   ├── fusion-browser-listener.sh
│   ├── fusion-callback-handler.sh
│   ├── fusion-gray-overlay-event-killer.sh
│   ├── kill-wine-proton-fusion-nuclear.sh
│   ├── launcher-functions.sh
│   └── launcher-config-user-interface.py
└── docs/
    ├── troubleshooting.md     # All known issues and fixes
    ├── what-worked-what-didnt.md
    ├── actions-log.md
    └── fusion360-linux-install-guide.md
```

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md) for known issues and fixes.
