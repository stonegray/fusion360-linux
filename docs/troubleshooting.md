# Troubleshooting

Known issues and their fixes when running Autodesk Fusion 360 on Linux through Proton.

---

## "You need Microsoft WebView2 component"

**Root cause:** The WebView2 runtime is not installed in the Proton prefix.

**Fix:** Run `./setup-fusion.sh` which downloads and installs the WebView2 bootstrapper automatically through Proton. Or download [Evergreen Bootstrapper](https://go.microsoft.com/fwlink/p/?LinkId=2124703) and run it manually:
```
STEAM_COMPAT_DATA_PATH="$HOME/.fusion360-proton2" \
STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam" \
~/.local/share/Steam/compatibilitytools.d/GE-Proton*/proton run \
  /path/to/MicrosoftEdgeWebview2Setup.exe /silent /install
```

---

## Sign-in opens `file:///.../authorize` in Firefox instead of the real Autodesk login page

**Root cause:** KDE Plasma's `kde-open` falls back to `kioexec` which downloads the URL content as a local file rather than opening the actual URL.

**Fix:** Our patched `fusion-browser-listener.sh` launches Firefox directly instead of using `xdg-open` for the browser URL. If you see this issue, make sure you have the patched listener from this repository.

---

## Sign-in freezes, then nothing happens

**Root cause:** A verbose logging edit in a prior version of `fusion-callback-handler.sh` broke the callback request write logic — the handler was logging but never wrote the request file.

**Fix:** Use the patched `fusion-callback-handler.sh` from this repository. The request write logic is restored.

---

## "Intel Vulkan ICD flag is enabled, but one of the Intel ICD files was not found"

**Root cause:** The launcher checks for Fedora-style ICD filenames (`intel_icd.x86_64.json`, `intel_icd.i686.json`) but Ubuntu and other distros use `intel_icd.json`.

**Fix:** Our patched `launcher-functions.sh` checks both naming conventions. Use the version from this repository.

---

## Browser listener logs Wayland errors or fails silently

**Root cause:** The `env -i` call in the listener stripped `WAYLAND_DISPLAY` and other KDE session variables, causing the browser and protocol handler to fail.

**Fix:** Our patched listener passes `WAYLAND_DISPLAY`, `KDE_SESSION_VERSION=6`, and `DBUS_SESSION_BUS_ADDRESS` through the environment.

---

## Fusion crashes with status 1 on restart

**Root cause:** A wineserver lock from a prior Fusion process that was killed or exited uncleanly.

**Fix:** Run `make kill` or `pkill -f wineserver` before restarting. The `launch-fusion.sh` script includes the nuclear kill script for cleanup.

---

## "Compiling shaders" at startup

**Root cause:** DXVK is compiling DirectX shaders to Vulkan SPIR-V on first run.

**Fix:** This is normal. Shaders are cached to disk in `~/.fusion360-proton2/pfx/drive_c/users/steamuser/AppData/Local/nvidia/DXVK/`. Subsequent launches are faster.

---

## Sign-in click does nothing, no browser opens

**Root cause:** `xdg-open` blocks the browser listener's main loop until Firefox exits. If Firefox is called synchronously, the listener never returns to process further requests.

**Fix:** Our patched listener launches the browser with `&` + `disown` so the listener continues running.

---

## Fusion installer never finishes / shows "Finish" button

**Root cause:** The webdeploy installer downloads packages and shows a "Finish" button in the installer GUI. Some users expect it to auto-close.

**Fix:** Click "Finish" in the installer GUI window. It appears as "Autodesk Application Installer" in the taskbar.

---

## `kfmclient: not found` error from xdg-open

**Root cause:** KDE Plasma 6 replaced `kfmclient` with `kioclient5`. `xdg-open` falls back to `kfmclient` when `KDE_SESSION_VERSION` is unset.

**Fix:** Our patched listener passes `KDE_SESSION_VERSION=6` in the environment.

---

## Launcher says "Chrome was not found or is not executable"

**Root cause:** The default `CHROME` path was hardcoded to `/usr/bin/google-chrome` which doesn't exist on Ubuntu or systems that use `chromium-browser` or Firefox.

**Fix:** Our patched `launch-fusion.sh` auto-detects the browser in order: `google-chrome > chromium-browser > chromium > firefox`.

---

## "Failed to register WineBrowser" warning

**Root cause:** The Wine registry key for the browser bridge already exists or Proton is not fully initialized.

**Fix:** This warning is non-fatal. If sign-in works, ignore it. If not, delete the Proton prefix and re-run Phase 2.

---

## `wine: Call ... to unimplemented function icuuc.dll.??0Locale@icu_77@@QEAA@XZ, aborting`

**Root cause:** Fusion bundles real ICU 77 DLLs next to `Fusion360.exe`, but
`NODEJS/node.exe` (the Autodesk Assistant / FremontJs runtime) and the embedded
WebView2 resolve `icuuc.dll` to Wine's 32 KB stub, which has no `icu_77`
symbols.  The process aborts; `node.exe` dies silently at startup and the
WebView2 renderer crash later shows up as a hang → native crash in the Neutron
core (`nsplatform10` / `cer` stack on the main thread).

**Fix:** See "ICU 77 Native DLL Override" in the README — copy the real
`icuuc.dll` / `third_party_icu_icui18n.dll` from the Fusion production
directory into the prefix `system32/`, and keep `FUSION_FIX_ICU77=1` (default)
so the launcher forces `icuuc,icuin,icudt=n,b`.

---

## Fusion freezes ~1 min after launch, then UI appears after ~50 min (assistant)

**Root cause:** The saved window layout
(`.../Neutron Platform/Options/<user-hash>/NULastDisplayedLayout.xml`) contains
the Autodesk Assistant dock panels (`AAPalette`/`AAHostWindow` and
`ChatPalette`/`ChatSupport`).  Fusion recreates them at startup and the
embedded assistant host blocks the UI thread until it times out (~50 min) —
the log goes silent after `[ADP] PanelCreateAssistant` while LaunchDarkly
stream retries fail.

**Fix:** Strip the two assistant `<Area>` blocks from
`NULastDisplayedLayout.xml` (it is UTF-16 LE — convert to UTF-8, edit, convert
back, or regenerate by deleting the file).  Back the file up first.  Fusion
still logs `PanelCreateAssistant` but no longer hangs on it.

---

## `fusion-toolwindow-fixer.exe` processes accumulate (hundreds), then Fusion hangs

**Root cause:** `start_toolwindow_fixer()` spawns two Wine instances per call
but only records one PID; the health monitor (`daemon_health_check`, every 30 s)
restarts the daemon whenever the pidfile PID is dead, and each stale
`launch-fusion.sh` instance runs its own monitor.  Multiple launches or a
dying fixer turns into a respawn loop — hundreds of Wine processes, CPU
saturation, then Hang Detection → crash.

**Fix (workaround):** Set `FUSION_ENABLE_TOOLWINDOW_FIXER=0` in
`~/.config/fusion360-linux/config` to disable the z-order daemon.  The
"always on top" panel bug returns, but no process leak.  Also ensure only one
`launch-fusion.sh` is running before launching.

---

## Assistant scripts fail: `RuntimeError: 2 : InternalValidationError` on `SketchLines.addByTwoPoints`

**Root cause:** The script used the **legacy, undocumented Point2D overload**.
`SketchLines.addByTwoPoints(start, end)` (see the docstring in the bundled
`adsk/fusion.py`) documents **SketchPoint or Point3D** as the only input
types.  The Point2D form comes from old tutorials; the C++ binding still
*attempts* the Point2D → AcGePoint3D coercion, and that conversion path is
broken, so it fails on the first call with

```
RuntimeError: 2 : InternalValidationError :
Xl::Fusion::SketchCurves::getAcGePoint3D(startPoint, acStartPoint, &pStartPoint)
```

This is not a regression of the documented API — the **Point3D** (and
`SketchPoint`) inputs work fine.  (The error type is misleading: an
unsupported type should raise `TypeError`, not an internal validation
error — minor API hygiene issue.)

**Fix (workaround):** Use the documented input types.  Convert `Point2D` →
`Point3D` before calling `addByTwoPoints`:

```python
def p2d(x, y):
    return adsk.core.Point3D.create(x, y, 0.0)

lines.addByTwoPoints(p2d(0.0, 0.0), p2d(2.54, 0.0))
```

The unhandled script error can also destabilize the MCP/scripting thread
(crash stack `nsmcp10`/`nafusion10`/`v8`) — see the ICU 77 entry above; keep
`FUSION_FIX_ICU77=1` so the script-execution helpers don't abort on top of
the API error.
