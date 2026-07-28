# Icon & DE Compatibility Audit

**Date:** 2026-07-28
**Scope:** MIME icon installation, desktop entry icons, KDE-specific code paths
**Method:** Read-only analysis of all install scripts, runtime scripts, and distro package lists

---

## Issues Found

### P1: App icon (`Icon=fusion360`) never installed

**What:** The desktop entry in `40-fusion-installer.sh` sets `Icon=fusion360`, but no code copies or creates an icon at `~/.local/share/icons/hicolor/*/apps/fusion360.png`.

**Where:** `src/install/40-fusion-installer.sh` lines 22 and 188 (desktop entry creation)

**Why it fails:** The MIME icon pipeline (`_install_fusion_mime_icon()` in `45-filetypes.sh`) only installs to `hicolor/*/mimetypes/` — not `hicolor/*/apps/`. The app icon is never placed. All desktop environments show a generic/missing placeholder in the application launcher.

**Fix:** Either:
- Symlink the master MIME icon: `ln -sf ../mimetypes/application-vnd.autodesk.fusion360.png hicolor/256x256/apps/fusion360.png`
- Or extract a separate app icon in `45-filetypes.sh` and install to `hicolor/*/apps/`

---

### P1: ImageMagick `convert` only in Debian deps — resize loop fails silently on other distros

**What:** The MIME icon resize loop in `45-filetypes.sh` uses `convert` to resize the master PNG to 8 standard sizes. Only `debian.txt` lists `imagemagick` as a dep. Fedora, Arch, OpenSUSE, Void, Solus all lack it.

**Where:** `src/install/45-filetypes.sh` resize loop
**Where also:** `src/install/distro/{fedora,arch,opensuse,void,solus}.txt`

**Why it fails:** On non-Debian systems the `convert` command is absent. The loop runs without error but produces zero sized icons. Only the master PNG (at 256x256) is left in the target dir, missing all smaller resolutions.

**Fix:** Either:
- Add `imagemagick` to all distro package lists
- Or add a fallback: try `convert`, then `ffmpeg -i input -s NxN output`, then `python3 -c 'from PIL import Image'`, then warn

---

### P2: No ffmpeg fallback in icon extraction

**What:** The master PNG creation step (`_install_fusion_mime_icon()`) tries `convert "$src_ico" "$master_png"` and falls back to `ffmpeg -i "$src_ico" "$master_png"` if convert fails. But the **resize loop** (lines ~80-100) only uses `convert` with no ffmpeg fallback.

**Where:** `src/install/45-filetypes.sh` — master PNG extraction has ffmpeg fallback, but the subsequent resize-to-sizes loop does not.

**Fix:** Wrap each resize call: `convert ... || ffmpeg -i "$master_png" -s NxN "$out" || warn`

---

### P2: `kbuildsycoca6` called unguarded in `40-fusion-installer.sh`

**What:** Line 30 in `40-fusion-installer.sh` calls `kbuildsycoca6 --noincremental` without a `command -v` guard. Line 196 has the guard correctly.

**Where:** `src/install/40-fusion-installer.sh` line 30

**Why it fails:** On non-KDE systems (GNOME Ubuntu, Sway, etc.), `kbuildsycoca6` doesn't exist. The command fails with a `command not found` error. While `set -e` isn't active at that point in the script, the error message is alarming and the exit code is non-zero.

**Fix:** Add `if command -v kbuildsycoca6 &>/dev/null; then ... fi` — same pattern as line 196.

---

### P2: `kde-open5` in browser listener is KDE5-specific

**What:** The browser listener's fallback chain includes `kde-open5`. KDE Plasma 6 uses `kde-open6`.

**Where:** `src/runtime/fusion-browser-listener.sh` — `kde-open5` in attempt 3

**Why it fails:** On KDE Plasma 6 with no KDE5 compatibility shim installed, `kde-open5` doesn't exist. The fallback to known browser binaries still works, but the KDE6 native path is missed.

**Fix:** Try `kde-open6` first, then `kde-open5`, then continue the existing fallback chain.

---

## Verified Working

These aspects of the icon/DE integration are correct:

- **DPI detection fallback chain** — KDE (kreadconfig5/kscreen-doctor) → GNOME (gsettings) → Cinnamon → xrdb → hardcoded default. All KDE-specific calls guarded by `command -v`.
- **MIME XML (`fusion360-mime.xml`)** — XDG-compliant, installed to correct `$XDG_DATA_HOME/mime/packages/`.
- **`update-mime-database`** — called in `25-install-to-location.sh` correctly.
- **`gtk-update-icon-cache`** — guarded by `command -v`, works on all distros with GTK.
- **Protocol handlers** — pure XDG standards (`xdg-mime default`, `xdg-open`, desktop files with `MimeType=x-scheme-handler/`), no DE assumptions.
- **`index.theme`** — spec-compliant with `Directories=` listing all mimetype subdirectories.
- **wrestool/icoutils** — declared in all distro package lists.
- **`NO_COLOR` handling** — correct: checks `-t 1` and `$NO_COLOR` env var.
- **No `$XDG_CURRENT_DESKTOP` branching** — DE detection is purely diagnostic.

---

## Overall Assessment

**Needs fixes for cross-distro icon support.** The KDE-specific code degrades gracefully, but the icon pipeline has two real bugs (missing app icon, Imagemagick-only resize) that leave non-Debian users without proper icons and all users without an application launcher icon.
