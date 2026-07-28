# Fusion 360 on Linux

Helper scripts for running Autodesk Fusion 360 on Linux through Proton/GE-Proton with working sign-in, browser bridge, and gray overlay fix.

## Install

```bash
./install.sh
```

This installs system dependencies, downloads GE-Proton, initializes the Proton prefix, runs post-install configuration (WebView2, handlers, desktop entries), then launches the Fusion installer. The Fusion GUI installer will pop up — click through it.

After install completes, launch with:

```bash
./launch-fusion.sh
# or
make run
```

## Individual steps

| Command | What it does |
|---------|-------------|
| `./install.sh --deps-only` | System packages only |
| `./install.sh --ge-proton-only` | Download + extract GE-Proton only |
| `./install.sh --prefix-only` | Init Proton prefix + winetricks |
| `./install.sh --run-installer` | Launch Fusion installer only |
| `./install.sh --installer-path /path/to/exe` | Use manually-downloaded installer |
| `./setup-fusion.sh` | Re-run post-install config (WebView2, handlers, icons, desktop entry) |
| `./setup-fusion.sh --force` | Re-do all config steps |
| `./launch-fusion.sh --configure` | Interactive path configuration |
| `./status.sh` | Quick prerequisite check |
| `./doctor.sh` | Full diagnostic report |
| `./uninstall.sh` | Remove Fusion, config, icons, desktop entries |

## Commands reference

| Command | Description |
|---------|-------------|
| `make run` | Launch Fusion 360 |
| `make kill` | Force-kill all Fusion/Wine processes |
| `make ps` | Check if Fusion is running |
| `make log` | View Fusion log output |

## Platform Support

| Distro | Status | Notes |
|--------|--------|-------|
| KDE Neon 24.04 | Tested 2026-07-28 | All patches verified |
| Ubuntu 24.04 | Likely works | Same base; adjust env vars if not on KDE |
| Fedora | Upstream target | Original scripts designed for Fedora |
| Arch | Untested | Package names may differ |
| openSUSE | Supported | Package names included |

## How It Works

The launcher handles three jobs: start Fusion through Proton, bridge sign-in from Wine to your Linux browser, and bridge the callback back into Proton's Identity Manager.

```
Fusion / Wine
  -> runtime-scripts/fusion-browser.sh
  -> /tmp/fusion360-browser-requests
  -> runtime-scripts/fusion-browser-listener.sh
  -> xdg-open Autodesk login URL
  -> browser login
  -> xdg protocol handler
  -> runtime-scripts/fusion-callback-handler.sh
  -> /tmp/fusion360-callback-requests
  -> runtime-scripts/fusion-browser-listener.sh
  -> Proton runs AdskIdentityManager.exe with callback URL
  -> Fusion receives sign-in
```

No passwords are written to files. The bridge writes short-lived URLs only.

## Repository Structure

```
├── install.sh                 # Thin wrapper over install-scripts/
├── install-scripts/           # Numbered install steps
│   ├── 00-common.sh           #   shared vars and helpers
│   ├── 10-deps.sh             #   system packages
│   ├── 20-ge-proton.sh        #   download/extract GE-Proton
│   ├── 30-prefix.sh           #   init prefix + winetricks
│   └── 40-fusion-installer.sh #   download + run Fusion installer
├── setup-fusion.sh            # Re-runnable post-install config
├── runtime-scripts/           # Scripts used by launch-fusion.sh
│   ├── fusion-browser.sh
│   ├── fusion-browser-listener.sh
│   ├── fusion-callback-handler.sh
│   ├── fusion-gray-overlay-event-killer.sh
│   ├── kill-wine-proton-fusion-nuclear.sh
│   ├── launcher-functions.sh
│   └── launcher-config-user-interface.py
├── doctor.sh                  # Thin wrapper over doctor/*.sh
├── doctor/                    # Diagnostic modules
│   ├── 00-common.sh
│   ├── 10-env.sh
│   ├── 20-deps.sh
│   └── ...
├── status.sh                  # Quick prerequisite check
├── uninstall.sh               # Clean removal
├── launch-fusion.sh           # Main launcher
├── Makefile                   # make run/kill/ps/log
└── docs/
    ├── troubleshooting.md
    ├── what-worked-what-didnt.md
    ├── actions-log.md
    └── fusion360-linux-install-guide.md
```

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md) for known issues.
