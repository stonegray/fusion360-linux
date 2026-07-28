# Fusion360 Installation - Actions Log

## 2026-07-28

### Initial Setup
- Cloned https://github.com/ninicksicard/fusion360-fedora-fix to /tmp/fusion360-fedora-fix
- System: KDE Neon (Ubuntu 24.04 noble), kernel 6.17.0-35-generic
- Found existing GE-Proton11-3.tar.gz at /tmp/
- Installer: ~/Downloads/fusion360-linux-install/FusionClientDownloader.exe
- Dependencies installed: zenity, python3-tk, cabextract, xdotool, winetricks

### Patches Applied
1. `launch-fusion.sh`: GE-Proton10-32 -> GE-Proton11-3 default path
2. `launch-fusion.sh`: CHROME auto-detection (google-chrome > chromium-browser > chromium > firefox)
3. `scripts/launcher-functions.sh`: Fixed BROWSER_LISTENER/CALLBACK_HANDLER defaults in load_config to point at scripts/
4. `scripts/launcher-functions.sh`: Added `read_kde_forced_dpi()` function for KDE Plasma DPI detection
5. `scripts/launcher-functions.sh`: Added KDE DPI check to `resolve_fusion_wine_dpi()`
6. `scripts/launcher-functions.sh`: Added KDE forced DPI logging in `apply_fusion_wine_dpi()`
7. `scripts/launcher-config-user-interface.py`: Added `read_kde_forced_dpi()` and `detected_kde_scale_percent()`
8. `scripts/fusion-browser-listener.sh`: Added KDE_SESSION_VERSION and XDG_RUNTIME_DIR to cleaned env for xdg-open

### Installation
- GE-Proton11-3 extracted to ~/.local/share/Steam/compatibilitytools.d/
- Proton prefix created at ~/.fusion360-proton2
- Fusion360 installed via Proton run of FusionClientDownloader.exe
- WebView2 runtime 150.0.4078.105 installed via Microsoft bootstrapper (679MB)
- Wine bug workarounds applied: edgeupdate service set to manual, processes cleaned
- xdg protocol handlers registered for adsk:// and adskidmgr://
- Config written to ~/.config/fusion360-linux/config

### Launch
- Fusion360 launched via hub start for OOM isolation
- Browser listener and overlay killer started successfully
- DPI resolved to 144 (fallback), Win8DpiScaling=1
- WebView2 embedded browser renders Autodesk sign-in inside Fusion
- Browser bridge captures sign-in URL as fallback
- xdg-open fails when env is stripped (Wayland display issue) - logged

### Status
- Fusion360 installed and launching
- WebView2 sign-in functional
- Browser bridge partially functional (captures requests, xdg-open has Wayland env issue)
