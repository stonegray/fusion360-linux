# Fusion360 Installation - What Worked / What Didn't

## System
- OS: KDE Neon User Edition (Ubuntu 24.04 noble)
- Kernel: 6.17.0-35-generic x86_64
- GPU: Intel WhiskeyLake-U GT2 [UHD Graphics 620]
- Desktop: KDE Plasma 6 (Wayland)

## What Worked

- [x] GE-Proton11-3 extraction to `~/.local/share/Steam/compatibilitytools.d/`
- [x] Proton-based installer launch (OOM-isolated via hub start)
- [x] Fusion360 installation via Autodesk webdeploy streamer (5.8GB)
- [x] WebView2 runtime v150.0.4078.105 installation (679MB)
- [x] WineBrowser registration for browser bridge
- [x] xdg protocol handlers for adsk:// and adskidmgr://
- [x] Browser bridge captures sign-in URL from Fusion/Wine
- [x] Direct Firefox launch bypasses KDE kioexec issues
- [x] Callback handler receives OAuth code from browser
- [x] Listener sends callback to AdskIdentityManager.exe via Proton
- [x] **Full sign-in flow completed** (browser bridge→Firefox→login→callback→Fusion signed in)
- [x] DPI scaling via registry settings (144 DPI fallback)
- [x] Gray overlay killer (xprop-based window detection)

## What Didn't / Caveats

- [ ] `kde-open6`/`xdg-open` on KDE Plasma 6 Wayland fails with stripped env (falls back to kioexec which downloads URL as local file)
- [ ] Fixed by launching Firefox directly instead of via xdg-open
- [ ] Intel Vulkan ICD warning (one of the ICD files not found - cosmetic)
- [ ] KDE `applications.menu` not found warning (benign)

## Patches Applied

1. **GE-Proton default version**: GE-Proton10-32 -> GE-Proton11-3
2. **KDE/Plasma DPI detection**: Added `read_kde_forced_dpi()` function alongside existing Cinnamon detection
3. **Browser auto-detection**: CHROME default changed from hardcoded `/usr/bin/google-chrome` to detect `google-chrome > chromium-browser > chromium > firefox`
4. **BROWSER_LISTENER default path fix**: `load_config()` pointed at `$SCRIPT_DIR/` instead of `$SCRIPT_DIR/scripts/`
5. **KDE DPI in Python UI**: Added `read_kde_forced_dpi()` and `detected_kde_scale_percent()` to `launcher-config-user-interface.py`
6. **DPI logging**: Added KDE forced DPI logging
7. **Listener env fix**: Added `KDE_SESSION_VERSION`, `WAYLAND_DISPLAY`, proper `DBUS_SESSION_BUS_ADDRESS` to stripped env
8. **Listener async fix**: Backgrounded xdg-open with `&` and `disown` so listener doesn't block
9. **Direct browser launch**: Bypassed xdg-open/kde-open entirely, launch Firefox directly to avoid kioexec file download
10. **Callback handler fix**: Restored request file writing logic that was accidentally deleted during verbose logging edit
