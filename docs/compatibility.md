# Ubuntu Compatibility — Fusion 360 on Linux

## Minimum System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **OS** | Ubuntu 22.04 LTS | Ubuntu 24.04 LTS |
| **CPU** | x86_64, 4 cores | 6+ cores |
| **RAM** | 8 GB | 16 GB |
| **GPU** | Intel UHD 620 / AMD Radeon RX 460 / NVIDIA GTX 960 | Intel Iris Xe / AMD Radeon RX 6600 / NVIDIA RTX 2060 |
| **VRAM** | 2 GB | 4+ GB |
| **Disk** | 15 GB free | 30 GB+ (SSD recommended) |
| **Vulkan** | Vulkan 1.3 | Vulkan 1.3 + VK_EXT_graphics_pipeline_library |
| **Display** | 1280x720 | 1920x1080+ (HiDPI supported) |

## Supported Ubuntu Versions

| Version | Codename | Status | Notes |
|---------|----------|--------|-------|
| 24.04 LTS | Noble | ✅ Full | Primary target; all deps available |
| 22.04 LTS | Jammy | ✅ Full | May need newer Mesa from kisak PPAs |
| 20.04 LTS | Focal | ⚠ Partial | Vulkan driver version may be too old |

### Derivative Support

All Debian-based distros sharing the same package manager:

| Distro | Status | Notes |
|--------|--------|-------|
| KDE neon | ✅ Full | Tested daily |
| Pop!_OS | ✅ Full | Uses Ubuntu repos |
| Linux Mint | ✅ Full | Uses Ubuntu repos |
| elementary OS | ✅ Full | Uses Ubuntu repos |
| Zorin OS | ✅ Full | Uses Ubuntu repos |
| Debian 12+ | ✅ Full | May need backported Mesa |

## GPU & Driver Compatibility

### Intel Integrated Graphics

| GPU | Vulkan Driver | Status | Notes |
|-----|--------------|--------|-------|
| UHD 620 / 630 | Mesa ANV (`intel_icd.json`) | ✅ Works | Tested; ~30 FPS viewport |
| Iris Xe (11th gen+) | Mesa ANV (`intel_icd.json`) | ✅ Works | Significantly faster |
| Arc A-series | Mesa ANV (`intel_icd.json`) | ✅ Works | Newer Mesa required (24.0+) |

Package: `sudo apt install mesa-vulkan-drivers intel-media-va-driver`

### AMD

| GPU | Vulkan Driver | Status | Notes |
|-----|--------------|--------|-------|
| RX 400/500 series | Mesa RADV (`radeon_icd.json`) | ✅ Works | |
| RX 5000 series+ | Mesa RADV (`radeon_icd.json`) | ✅ Works | Best tested option |
| RX 7000 series | Mesa RADV (`radeon_icd.json`) | ✅ Works | Mesa 23.3+ |

Package: `sudo apt install mesa-vulkan-drivers`

### NVIDIA

| GPU | Vulkan Driver | Status | Notes |
|-----|--------------|--------|-------|
| GTX 900+ | Proprietary nvidia (`nvidia_icd.json`) | ✅ Works | Driver 535+ recommended |
| GTX 600-800 | Proprietary nvidia | ⚠ Partial | Driver 470 (EOL); Vulkan 1.2 only |
| Nouveau (open) | Mesa NVK | ⚠ Experimental | Not recommended |

Package: `sudo apt install nvidia-driver-535` (or `nvidia-driver-550` on 24.04)

> **Note:** On NVIDIA, Fusion may perform better with `PROTON_USE_WINED3D=0` (DXVK enabled). The launcher defaults to this.

### Driver Troubleshooting

```bash
# Verify Vulkan support
sudo apt install vulkan-tools
vulkaninfo --summary

# Check which ICD is active
ls /usr/share/vulkan/icd.d/

# Install Intel Vulkan (if missing)
sudo apt install mesa-vulkan-drivers libvulkan1 libvulkan1:i386

# Install 32-bit Vulkan (needed for DXVK)
sudo apt install mesa-vulkan-drivers:i386

# For NVIDIA on Wayland
sudo apt install nvidia-driver-550  # Wayland support improved in 545+
```

## Desktop Environment Notes

### GNOME (Ubuntu default)

- **Wayland:** Fusion runs under XWayland. Most features work.
- **Mutter watchdog:** GNOME's `check-alive-timeout` may show "not responding" dialog during Fusion startup. Our launcher sets `G_MESSAGES_DEBUG=none` to suppress related spam.
- **Window management:** No known issues with standard workflows.
- **HiDPI:** Detected via `gsettings get org.gnome.desktop.interface text-scaling-factor`.

### KDE Plasma (Neon, Kubuntu)

- **Wayland:** Best-supported configuration. Tested daily.
- **DPI detection:** Uses `kreadconfig5` for forced DPI, `kscreen-doctor -o` per-output scale detection.
- **Window rules:** Our toolwindow fixer (`fusion-toolwindow-fixer.exe`) handles z-order stacking.
- **File manager:** Dolphin shows Fusion file icons via MIME theme integration.

### Sway / Hyprland (wlroots-based)

- **Status:** Not formally tested. Community reports mixed results.
- **Window management:** XWayland → XDND limitations may affect drag-drop.
- **DPI:** May need manual `FUSION_WINE_DPI` setting.

## Known Limitations

| Issue | Status | Workaround |
|-------|--------|------------|
| **UI rendering slow** | Known | WebView2 → ANGLE → D3D11 → DXVK double-translation on iGPU. Use `--ignore-gpu-blocklist` (enabled by default). |
| **Drag & drop** | Not working | Fusion rejects drops via XDND → OLE. No known fix without Wine patch. |
| **Native file dialog** | Not available | GE-Proton lacks `FILEOPEN_DIALOG` portal support. Wine's built-in dialog is used. |
| **Window z-order (Wayland)** | ✅ Fixed | Our `fusion-toolwindow-fixer.exe` adds `WS_EX_APPWINDOW` to floating panels at runtime. |
| **System tray icon** | Lost on Wayland | X11 system tray not supported under KWin Wayland. No impact on usage. |
| **Notifications** | Not bridged | Fusion uses in-app notifications. No Windows toast integration needed. |
| **Suspend/resume** | ⚠ May need restart | Fusion's streamer service may not reconnect after resume. Close and relaunch. |
| **Multi-monitor HiDPI** | ⚠ Per-monitor ratio | DPI applied uniformly. Open/save dialogs may appear at wrong scale. |
| **opensnitch / firewall** | ⚠ Blocks license check | Fusion must reach `dl.appstreaming.autodesk.com` and `identity.api.autodesk.com` |
| **Snap Firefox** | ⚠ Browser bridge | Snap Firefox cannot use xdg-open correctly. Install deb/RPM Firefox instead. |

## Troubleshooting

### Install Issues

```bash
# Re-run specific steps
./install.sh --deps-only           # Step 1 only
./install.sh --ge-proton-only      # Step 3 only
./install.sh --prefix-only         # Step 5 only

# OR delete flag and re-run full install
rm ~/.local/share/fusion360-linux/flags/fusion-installed
./install.sh
```

### Vulkan / GPU Issues

```bash
# Check if DXVK is working
grep -i "dxvk\|vulkan" ~/.fusion360-proton2/pfx/drive_c/users/steamuser/AppData/Local/Autodesk/Autodesk\ Fusion\ 360/*/logs/AppLogFile*.log

# Expected output:
#   "Initializing OGS Device: VirtualDeviceDx11, Device Type: Hardware. Success!"

# Force DXVK async (enabled by default)
grep DXVK_ASYNC ~/.config/fusion360-linux/config

# Switch to OpenGL fallback (slower but stable)
sed -i 's/FUSION_PROTON_USE_WINED3D=0/FUSION_PROTON_USE_WINED3D=1/' ~/.config/fusion360-linux/config
```

### WebView2 / UI Slow

The UI WebView2 processes use an ANGLE→D3D11→DXVK translation pipeline, adding overhead on iGPUs. This is a known hardware limitation. Our launcher enables:

- `--ignore-gpu-blocklist` — forces GPU acceleration despite Wine-wrapped GPU
- `--enable-gpu-rasterization` — GPU compositing for WebView2 tiles
- `--use-angle=d3d11` — D3D11 backend through DXVK
- `dxgi.syncInterval=0` — disables vsync on swapchain
- `dxvk.tearFree=1` — smooth presentation

To disable GPU acceleration (may help on very old GPUs):

```bash
sed -i 's/FUSION_WEBVIEW_DISABLE_GPU=0/FUSION_WEBVIEW_DISABLE_GPU=1/' ~/.config/fusion360-linux/config
```

### Sign-In / Authentication

```bash
# Check if callback handler is working
cat /tmp/fusion-callback-handler.log

# Check browser bridge
cat /tmp/fusion-browser-listener.log

# Ensure Chrome/Chromium is available (our bridge prefers Chrome)
# Firefox works but Snap Firefox can't use xdg-open
```

### Doctor Diagnostic

```bash
# Run full diagnostic
./doctor.sh

# Save report to file
./doctor.sh --save

# Quick summary
./doctor.sh --quick
```

## Ubuntu Package Dependencies

Installed automatically by step 1:

```
icoutils        # wrestool — icon extraction from Fusion360.exe
zenity          # GUI dialogs for first-run config
python3-tk      # Python Tkinter for config UI
cabextract      # Cabinet file extraction
wget            # Downloader
xdg-utils       # xdg-mime, xdg-open
desktop-file-utils  # update-desktop-database
winetricks      # .NET/VC++ runtime installer
ImageMagick     # convert — icon format conversion
mingw-w64       # Cross-compiler for fusion-toolwindow-fixer.exe
```

## File System Layout

```
~/.config/fusion360-linux/config              # User config (sourced by launcher)
~/.local/share/fusion360-linux/
  launch-fusion.sh                            # Main launcher
  doctor.sh                                   # Diagnostic tool
  runtime-scripts/                            # Runtime scripts
  icons/                                      # Extracted Fusion icon
  flags/
    fusion-installed                          # Install completion flag
~/.local/share/applications/fusion360-linux/  # Desktop entries
~/.local/share/icons/hicolor/*/mimetypes/     # MIME icons for .f3d
~/.fusion360-proton2/                         # Proton/Wine prefix
  pfx/drive_c/                               # Windows C: drive
  pfx/user.reg                               # HKCU registry
  pfx/system.reg                             # HKLM registry
/tmp/fusion-toolwindow-fixer.log             # Toolwindow fixer log
/tmp/fusion-browser-listener.log             # Browser bridge log
/tmp/fusion360-dpi.log                       # DPI detection log
/tmp/fusion360-gray-overlay-event-killer.log # Overlay killer log
```
