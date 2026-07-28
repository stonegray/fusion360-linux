# Icon Installation Approach Review

**Assessment:** `spec-compliant`

## Overview

The Fusion 360 Linux installer installs application and MIME type icons into
`~/.local/share/icons/hicolor/` under standard-named subdirectories like
`48x48/apps/` and `48x48/mimetypes/`. It does **not** create a local
`index.theme` and does **not** run `gtk-update-icon-cache`. Instead, it relies
on the **system** hicolor theme at `/usr/share/icons/hicolor/index.theme` to
provide the canonical directory list, then deletes any stale local
`icon-theme.cache` and runs `kbuildsycoca6 --noincremental` to refresh KDE's
icon cache.

This approach is correct and avoids the catastrophic bug of the previous
approach (creating a local `index.theme` that listed only 8 mimetype
subdirectories, which shadowed the system hicolor theme and caused ALL system
app icons to vanish).

---

## Spec Conformance Analysis

### Section 3 — Directory Layout

| Requirement | Status | Evidence |
|---|---|---|
| Icons stored as subdirectories of base directories | ✅ PASS | `~/.local/share/icons/` is `$XDG_DATA_HOME/icons`, a valid base directory |
| Theme named "hicolor" exists | ✅ PASS | System provides `/usr/share/icons/hicolor/` |
| At least one `index.theme` describes the theme | ✅ PASS | System `/usr/share/icons/hicolor/index.theme` lists all standard directories including `48x48/apps` and `48x48/mimetypes` |
| Image files are PNG with `.png` extension | ✅ PASS | All installed files are `.png` (generated from Fusion360.ico via ImageMagick/ffmpeg) |

The key clause: *"A theme can be spread across several base directories by
having subdirectories of the same name."* By placing our PNGs in
`~/.local/share/icons/hicolor/<size>/apps/` and
`~/.local/share/icons/hicolor/<size>/mimetypes/`, we extend the system hicolor
theme into the user's data directory — exactly as the spec intends. The system
`index.theme` describes the directory structure; our files fill in missing
icons within that structure.

### Section 5 — Icon Lookup

The `LookupIcon` algorithm iterates:

```
for each subdir in $(theme subdir list)       # from index.theme
  for each directory in $(basename list)       # ~/.icons, XDG_DATA_HOME/icons, XDG_DATA_DIRS/icons, ...
    for extension in ("png", "svg", "xpm")
      filename = directory/themename/subdir/iconname.extension
      if exists filename → return it
```

**Example trace** — looking up `fusion360` at size 48:

1. `subdir = "48x48/apps"` (from system `index.theme`)
2. `directory = "~/.local/share/icons"` (from `$XDG_DATA_HOME/icons`)
3. Construct: `~/.local/share/icons/hicolor/48x48/apps/fusion360.png`
4. File exists → **found** ✅

The same applies for MIME type icons (`application-vnd.autodesk.fusion360` in
`48x48/mimetypes/`).

**CRITICAL**: The `subdir list` comes from the `index.theme` file. The first
`index.theme` found in the base directory search order **wins**. Since our
local `~/.local/share/icons/hicolor/` has **no** `index.theme`, the system
`/usr/share/icons/hicolor/index.theme` is used — and it lists ALL standard
subdirectories (16x16 through 512x512, with all contexts: apps, mimetypes,
actions, devices, etc.). This is exactly what we want.

### Section 7 — Installing Application Icons

| Requirement | Status | Evidence |
|---|---|---|
| Install a 48×48 icon in hicolor theme | ✅ PASS | `~/.local/share/icons/hicolor/48x48/apps/fusion360.png` |
| Install PNG in `$prefix/share/icons/hicolor/48x48/apps` | ✅ PASS | `$prefix` = `$XDG_DATA_HOME` = `~/.local/share` |
| Optionally install different sizes | ✅ PASS | Installs 16, 22, 24, 32, 48, 64, 128, 256 |
| Optionally install SVG in `scalable/apps` | ❌ MISSING | Enhancement opportunity, not a compliance issue |

### Section 8 — Implementation Notes

> "A good implementation is expected to read the directories once, and do all
> lookups in memory using that information."

> "any implementation that does caching is required to look at the mtime of
> the toplevel icon directories when doing a cache lookup"

By **deleting** `icon-theme.cache`, we force implementations to re-scan
directories. The mtime of `~/.local/share/icons/hicolor/` changes when we add
files, so caches that do exist (e.g., KDE's Sycoca) will detect the change and
re-validate. This is spec-compliant — the spec explicitly allows filesystem
lookups as the baseline, and the cache invalidation mechanism works through
directory mtimes.

---

## Questions Answered

### Q1: Is NOT having a local `index.theme` correct?

**Yes.** The spec says *"In at least one of the theme directories there must be
a file called index.theme."* The system provides one at
`/usr/share/icons/hicolor/index.theme`. This satisfies the requirement. More
importantly, NOT having a local one is **necessary** — the first `index.theme`
found in the base directory search order is used. Since `~/.local/share/icons`
is searched before `/usr/share/icons`, a local `index.theme` would **shadow**
the system one. This was the root cause of the original bug.

### Q2: Will our icon be found via the LookupIcon algorithm?

**Yes.** The algorithm iterates all base directories for each subdirectory
listed in the (system) `index.theme`. Our files at
`~/.local/share/icons/hicolor/48x48/apps/fusion360.png` match the constructed
path `directory/themename/subdir/iconname.extension` when `directory =
~/.local/share/icons`, `themename = hicolor`, `subdir = 48x48/apps`, `iconname
= fusion360`, `extension = png`.

### Q3: Is NOT running `gtk-update-icon-cache` correct?

**Yes.** Three reasons:

1. **`gtk-update-icon-cache` requires an `index.theme`** in the target
   directory. Without one, it exits with error: *"No theme index file."* Even
   if a user runs it manually, it won't create a cache — it simply fails. The
   `--ignore-theme-index` (`-t`) flag could force cache creation, but this is
   an explicit user action, not something that happens automatically.

2. **Performance is negligible.** Without a cache, GTK does filesystem lookups
   (one `stat()` per possible path). For a single app with ~16 icon files
   across 8 sizes, this is imperceptible. The spec's baseline algorithm IS
   filesystem lookup; caching is an optimization.

3. **The stale cache was the vector for the original bug.** Deleting it and
   not recreating it is the safest approach.

### Q4: What does `kbuildsycoca6` cache?

`kbuildsycoca6` rebuilds the KDE System Configuration Cache (KSycoca v6). It
caches:

- Desktop entry metadata (Name, Exec, Icon, Categories, MimeType, etc.)
- MIME type associations
- Service/protocol handlers
- **Icon file paths**: For each icon theme, it maps `(iconName, size) →
  filePath` by running the spec's `LookupIcon` algorithm and caching the
  result

`--noincremental` forces a full rebuild from scratch rather than only
processing changed directories. This is needed after icon installation because
the directory mtime of `~/.local/share/icons/hicolor/<size>/apps/` changed,
and an incremental rebuild may not detect new subdirectories within a parent
that was already cached.

### Q5: What about `$HOME/.icons/`?

The spec lists `$HOME/.icons` as the **first** base directory (for backwards
compatibility). Our installer uses `$XDG_DATA_HOME/icons`
(`~/.local/share/icons`), which is the **second** directory. Icons in
`~/.icons/hicolor/` would be found first, potentially shadowing ours.

**Current state**: A stale `~/.icons/hicolor/48x48/apps/fusion360.png` and
`~/.icons/fusion360.png` (untamed fallback) exist from a previous install
approach. The new installer does **not** clean these up.

**Recommendation**: Clean up stale `~/.icons/` entries during install or at
least document that they should be removed. They don't break anything (they
point to the same icon), but they're confusing.

### Q6: What about `scalable/apps/` SVG?

The spec recommends: *"installing a svg icon in
$prefix/share/icons/hicolor/scalable/apps means most desktops will have one
icon that works for all sizes."* We only install bitmap PNGs at fixed sizes.
KDE, GNOME, and most modern DEs support SVG icons. Adding an SVG would:

- Provide resolution-independent scaling on HiDPI displays
- Reduce disk usage (one SVG vs. 8 PNGs)
- Match the spec's recommendation

This is an enhancement, not a compliance issue.

---

## Edge Cases

### 1. No system hicolor theme (minimal install)

**Risk**: Low. The `hicolor-icon-theme` package (Priority: optional) is a hard
dependency of `libgtk-3-0`, `libqt5gui5`, and virtually every desktop
environment. It will be present on any system running a GUI.

**Impact if absent**: Without any `index.theme`, the theme has an empty
subdirectory list (`Directories=` is required). The `LookupIcon` algorithm
would iterate zero subdirectories and return `none`. Our icons would not be
found.

**Mitigation**: Could install a minimal fallback `index.theme` only if the
system one is absent. But this is the same pattern that caused the original
bug — if done incorrectly, it could shadow a later installation. The risk of
missing hicolor on a desktop system is near-zero, so the current approach
(skip if absent with a warning) is acceptable.

### 2. User runs `gtk-update-icon-cache -f ~/.local/share/icons/hicolor/`

**Risk**: Low.

- **Without `-t`**: Fails with *"No theme index file."* No cache created. ✅
- **With `-t`**: Would create a cache by scanning existing local directories.
  Our icons in standard-named directories would be indexed correctly. The only
  risk is if the cache is created BEFORE we install icons — then new icons
  would be missed until the cache is rebuilt. But our install script runs
  `rm -f icon-theme.cache` AFTER installing icons, so this is handled.

### 3. `$HOME/.icons` symlink to `$XDG_DATA_HOME/icons`

**Risk**: None. Some distros create this symlink. If it exists, our icons at
`~/.local/share/icons/hicolor/` are also accessible via `~/.icons/hicolor/`.
Both paths resolve to the same files. No duplication, no conflict.

### 4. Concurrent access / cache race

**Risk**: None. `rm -f icon-theme.cache` is atomic. `kbuildsycoca6` locks its
cache during rebuild. There's no window where a partially-written cache could
corrupt icon display.

### 5. NFS / network home directories

**Risk**: None. Filesystem lookups work the same way. The absence of a cache
file means one extra `stat()` per icon lookup, which is negligible even over
NFS.

---

## Issues Found

### Issue 1: MIME type icons not cleaned by uninstaller

- **Severity**: P2 (medium — resource leak, not functional bug)
- **Files**: `uninstall.sh`, `src/runtime/uninstall-select.sh`
- **Details**: Both uninstallers only remove `*/apps/fusion360.png` but do
  not remove `*/mimetypes/application-vnd.autodesk.fusion360.png`. After
  uninstall, 8 MIME type icon files remain orphaned on disk (~100KB total).
- **Fix**: Add a second loop or glob pattern:
  ```bash
  for icon in "$HOME"/.local/share/icons/hicolor/*/mimetypes/application-vnd.autodesk.fusion360.png; do
    [[ -f "$icon" ]] && rm -f "$icon" && echo "    Removed icon: $icon"
  done
  ```

### Issue 2: Legacy `~/.icons/` files not cleaned up

- **Severity**: P2 (medium — migration debt)
- **Files**: `src/install/45-filetypes.sh`
- **Details**: Previous install approaches created:
  - `~/.icons/hicolor/48x48/apps/fusion360.png`
  - `~/.icons/fusion360.png` (untamed fallback)
  
  These are not removed by the current installer. They don't cause functional
  problems (same icon, correct path), but they're stale and confusing during
  debugging. The untamed fallback at `~/.icons/fusion360.png` could also be
  picked up by `LookupFallbackIcon` before the themed lookup, though this
  would only happen if the hicolor theme lookup fails entirely.
- **Fix**: Add cleanup at the start of `_install_fusion_mime_icon()`:
  ```bash
  rm -f "$HOME/.icons/fusion360.png"
  rm -rf "$HOME/.icons/hicolor"/*/apps/fusion360.png 2>/dev/null || true
  ```

### Issue 3: Inconsistent `kbuildsycoca6` flags

- **Severity**: P3 (info — minor inconsistency)
- **Files**: `src/install/45-filetypes.sh:96` vs `src/install/40-fusion-installer.sh:200`
- **Details**: `45-filetypes.sh` uses `kbuildsycoca6 --noincremental` (full
  rebuild). `40-fusion-installer.sh` uses `kbuildsycoca6` (incremental) when
  installing just the desktop entry. Both are installing new icons/entries
  that need cache refresh. The incremental call should also use
  `--noincremental` for consistency, since the desktop entry references
  `Icon=fusion360` and the icon was just installed in the same execution
  flow.
- **Fix**: Change line 200 of `40-fusion-installer.sh` to
  `kbuildsycoca6 --noincremental 2>/dev/null || true`

### Issue 4: Doctor checks icon sizes we don't install

- **Severity**: P3 (info — false-negative risk)
- **Files**: `src/doctor/50-config.sh:76`, `src/install/45-filetypes.sh:36`
- **Details**: The doctor checks 12 sizes (16, 22, 24, 32, 48, 64, 72, 96,
  128, 192, 256, 512) but we only install 8 sizes (16, 22, 24, 32, 48, 64,
  128, 256). Missing: 72, 96, 192, 512. The doctor currently reports "pass"
  if ANY size is found, so this isn't a functional bug. But if a future
  change makes the doctor check specific sizes, it could falsely report
  missing icons.
- **Fix**: Align the doctor's size list with what we actually install, or add
  the missing sizes to `_install_fusion_mime_icon()`.

---

## Final Recommendation

**The current approach is correct and should be kept.** The key insight — not
creating a local `index.theme` to avoid shadowing the system theme — is both
spec-compliant and proven-safe.

**Recommended changes** (in priority order):

1. **Fix uninstaller icon leak** (P2) — remove MIME type icons alongside app
   icons
2. **Clean legacy `~/.icons/` files** (P2) — remove stale files from previous
   install approaches
3. **Consistent `--noincremental`** (P3) — use the same flag in both cache
   refresh calls
4. **Align doctor size list** (P3) — check only sizes we actually install
5. **Consider SVG** (enhancement) — add `scalable/apps/fusion360.svg` for
   resolution-independent scaling

None of these are blockers. The approach as designed works correctly and
conforms to the freedesktop.org Icon Theme Specification v0.13.

---

## Addendum: Critical Finding (P0)

### Stale `index.theme` not removed on upgrade from broken install

**Severity: P0** — blocks release, causes the same catastrophic system-wide icon
failure as the original bug.

**Details**: The previous broken install created
`~/.local/share/icons/hicolor/index.theme` listing only 8 mimetype
subdirectories (with `Context=MimeTypes`). The fix correctly stops creating
this file, but does **not** remove a pre-existing one. On upgrade:
1. `~/.local/share/icons/hicolor/index.theme` still exists from the old install
2. It is found FIRST (before `/usr/share/icons/hicolor/index.theme`)
3. It lists only mimetype directories — no `apps`, `actions`, `devices`, etc.
4. All system app icons disappear — the exact same catastrophic failure

**Evidence**: The comment at `src/install/45-filetypes.sh:80` acknowledges the
old index.theme, but line 82 only removes `icon-theme.cache`:

```bash
# (the old code created a local index.theme + ran gtk-update-icon-cache,
# which caches a stale directory listing that excludes our new icons).
rm -f "$hicolor/icon-theme.cache"
```

**Fix**: Add `rm -f "$hicolor/index.theme"` before or alongside line 82.

**Confidence**: 1.0 — the base directory search order
(`$HOME/.local/share/icons` before `/usr/share/icons`) is specified by the
freedesktop.org spec and confirmed by testing with the original broken
approach.
