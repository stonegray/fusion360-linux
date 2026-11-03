# Fusion360-Linux — Full Code Review

**7-agent deep review**
- **Reviewed**: 67 shell files (*.sh + *.fn), 5347 lines
- **Review date**: 2026-07-29
- **Agents**: shell-safety, wine-proton, install-pipeline, share-library, security, runtime-daemons, doctor-framework
- **Total findings**: 144+

---

## Findings by Severity

| Severity | Count |
|----------|-------|
| CRITICAL | 6 |
| HIGH | 24 |
| MEDIUM | 48 |
| LOW | 49 |
| INFO | 17 |

---

## CRITICAL

### C1. `exit 1` in sourced library (shell-safety, share-library)
- **File**: `share/daemon.fn:35`
- **Description**: `start_browser_listener()` calls `exit 1` when `BROWSER_LISTENER` is not found/executable. This file is a `.fn` library sourced by `share/load.sh`. As a sourced library, `exit` terminates the entire sourcing shell process, not just the function.
- **Risk**: If a user has an incorrect `BROWSER_LISTENER` path, the launcher process dies without cleanup — daemon PIDs not tracked, bridge temp files remain, abrupt exit.
- **Recommendation**: Replace `exit 1` with `return 1`. Callers already handle the return code.

### C2. Massive function duplication — share/ library overridden by launcher-functions.sh (shell-safety, share-library, runtime-daemons)
- **Files**: Multiple `share/*.fn` vs `src/runtime/launcher-functions.sh`
- **Description**: At least 21 functions exist in BOTH the new share/ library AND the legacy launcher-functions.sh with nearly identical implementations. The share/ definitions are loaded first, then immediately overridden. Duplications include: `is_enabled`, `load_config`, `save_config`, `clear_bridge_temp_files`, `read_gsettings_number`, `read_kde_forced_dpi`, `read_kde_primary_scale`, `read_gnome_text_scaling`, `scale_to_dpi`, `percent_to_dpi`, `resolve_fusion_wine_dpi`, `apply_fusion_wine_dpi`, `detect_system_dark_mode`, `apply_fusion_wine_dark_mode`, `install_callback_protocol_handlers`, `register_wine_browser_bridge`, `start_browser_listener`, `start_overlay_killer`, `start_toolwindow_fixer`, `kill_fusion_processes`, `cleanup`.
- **Risk**: Any bug fix in share/ is silently invisible at runtime. The two implementations have already drifted (share/ uses `log_error`/`log_warn`; legacy uses `echo`/`fail()`). Maintainers cannot know which copy is authoritative.
- **Recommendation**: Consolidate — remove duplicates from `launcher-functions.sh` and rely on share/ versions (more modern, `set -e` safe).

### C3. Config file `source`d as shell code — arbitrary code execution (security)
- **File**: `share/config.fn:73`, `src/runtime/launcher-functions.sh:25`, `share/load.sh:9-42`
- **Description**: `load_config()` uses `source "$CONFIG_FILE"` to load the user config file. This executes the config file as arbitrary shell code. The config file (`~/.config/fusion360-linux/config`) is world-readable by default.
- **Risk**: Any attacker with write access to this file gains arbitrary code execution in the install/launch context. Privileged code execution vector — config is sourced at startup of both `install.sh` and `launch-fusion.sh`.
- **Recommendation**: Either (a) restrict config file permissions to 600 at creation, or (b) parse the config file with a restricted key=value parser instead of `source`ing it.

### C4. `--uninstall` falls through to full install (install-pipeline)
- **File**: `install.sh:72-75`
- **Description**: The `--uninstall` case sources `uninstall-select.sh` but does not `exit` afterward. After the interactive uninstall completes, control falls through to the main install flow starting at Step 1/14.
- **Risk**: Silent re-install after explicit uninstall. User walks away after uninstalling and comes back to a fresh install.
- **Recommendation**: Add `exit 0` after the `source` call in the `--uninstall` case block.

### C5. Overlay killer event loop in pipeline subshell — `exit 0` doesn't exit the script (runtime-daemons)
- **File**: `src/runtime/fusion-gray-overlay-event-killer.sh:172-175`
- **Description**: Main event loop is `xprop -root -spy _NET_CLIENT_LIST | while read ...`. Inside the loop, `check_parent_still_exists()` calls `exit 0` when the tracked parent window disappears. Because `while read` is on the right side of a pipe, it runs in a subshell — `exit 0` exits only the subshell, not the main script.
- **Risk**: Termination is unreliable. `xprop -spy` may not get SIGPIPE immediately. The overlay killer appears to be running but is detached from its event source. Variable modifications inside the loop are lost.
- **Recommendation**: Use process substitution (`while ... done < <(xprop ...)`) to keep the loop in the main shell.

### C6. `((SECTION_*++))` under `set -e` aborts doctor on first check (doctor-framework)
- **File**: `src/doctor/00-common.sh:53-55`
- **Description**: `pass()`, `fail()`, and `warn()` use `((SECTION_PASS++))`, `((SECTION_FAIL++))`, `((SECTION_WARN++))` as their last command. Post-increment of a zero variable returns exit code 1 (the old value 0 evaluates as arithmetic false), which triggers `set -e`. The FIRST call to any of these functions aborts the script.
- **Risk**: The entire doctor framework is non-functional in any bash version that respects `set -e` on arithmetic false. No diagnostic report is ever produced.
- **Recommendation**: Change to `((++SECTION_*))` (pre-increment, returns non-zero after first increment) or add `|| true` to each.

---

## HIGH

### H1. Literal `\t` instead of tab character — hosts file corruption (shell-safety, share-library)
- **File**: `share/hosts.fn:22,26,28`
- **Description**: `local entry="$ip\t$hostname"` — in double-quoted strings, bash does not interpret `\t` as a tab. Line 26 (first creation) works because `printf`'s format string interprets `\t`. Line 28 (subsequent appends) writes literal backslash-t into the hosts file.
- **Risk**: Hosts file corruption on second call to `ensure_hosts_entry()`. The second entry has literal `\t` which the resolver does not parse.
- **Recommendation**: Use `$'\t'` or a literal tab.

### H2. No `mktemp` usage — all temp files use hardcoded `/tmp/` paths (shell-safety)
- **Files**: All 67 files across the codebase
- **Description**: Zero uses of `mktemp`. Every temp file uses a predictable `/tmp/` path: lock files, bridge IPC directories, log files, downloads. Examples: `/tmp/fusion360-browser-requests`, `/tmp/fusion360-install.lock`, `/tmp/MicrosoftEdgeWebview2Setup.exe`, `/tmp/${GE_PROTON_VERSION}.tar.gz`.
- **Risk**: Predictable temp filenames vulnerable to symlink-race attacks (CWE-367). Files persist on crash. On multi-user systems, `/tmp/` is world-writable — attacker can pre-create symlinks.
- **Recommendation**: Replace with `mktemp -d` for directories, `mktemp` for files. Register cleanup traps.

### H3. `wine_prefix_init()` and `winetricks_run()` in share/wine.fn are dead code (wine-proton)
- **File**: `share/wine.fn:46-83`
- **Description**: Two exported library functions with documentation. They are never called by any install or runtime script. The install scripts (30-prefix.sh) duplicate the logic inline.
- **Risk**: 40 lines of dead code creating maintenance burden. A future developer might rely on these library functions.
- **Recommendation**: Delete the dead functions or refactor 30-prefix.sh to call them.

### H4. Duplicated DPI detection functions (wine-proton)
- **File**: `share/detect-display.fn` vs `src/runtime/launcher-functions.sh`
- **Description**: `read_kde_forced_dpi`, `read_kde_primary_scale`, `read_gnome_text_scaling` defined in two places with identical logic.
- **Risk**: Maintenance trap — two divergent copies if one is fixed/enhanced.
- **Recommendation**: Remove duplicates from `launcher-functions.sh`; rely on `share/detect-display.fn`.

### H5. Duplicated Wine binary path derivation (wine-proton)
- **Files**: `share/dpi.fn:151`, `share/dark-mode.fn:82`, `src/install/30-prefix.sh:39`, `src/install/39-windows-version.sh:9`
- **Description**: All four derive `$(dirname "$PROTON")/files/bin/wine` independently. The library function `proton_wine_bin()` exists in `share/proton.fn:19-24` but is never called by these callers.
- **Risk**: A directory structure change requires editing 4+ files instead of one library function.
- **Recommendation**: Replace all inline derivations with calls to `proton_wine_bin "$PROTON"`.

### H6. `WINEDLLOVERRIDES` from install not carried to runtime (wine-proton)
- **File**: `src/install/30-prefix.sh:16` vs `src/runtime/launcher-functions.sh:662-672`
- **Description**: Install-time overrides (`regedit.exe,msiexec.exe=`) and runtime overrides (`bcp47langs=,winhttp=b`) are different. If a user sets `WINEDLLOVERRIDES` for debugging, their setting is silently overwritten.
- **Recommendation**: Append user-set `WINEDLLOVERRIDES` or log the final value.

### H7. Config file never updates existing keys on reinstall (install-pipeline)
- **File**: `src/install/37-config.sh:53-65`
- **Description**: When config already exists, script only appends missing keys via `grep -q "^${KEY}="`. It never overwrites or updates existing keys. If defaults change between versions, re-run leaves stale config.
- **Recommendation**: Add `CONFIG_VERSION` key; rewrite or update keys whose values differ from defaults.

### H8. Phantom "Step 8/14" — no-op step (install-pipeline)
- **File**: `install.sh:111-113`
- **Description**: Step 8 is printed via `log_step` but has no `run_step` call — just `echo ""`. Total count (14) no longer matches actual runnable steps (13 real + 1 no-op).
- **Recommendation**: Remove the phantom step and renumber.

### H9. `fusion360` CLI symlink claimed but never created (install-pipeline)
- **File**: `src/install/25-install-to-location.sh:37`
- **Description**: Log message says CLI symlinks include `fusion360`, but only `launch-fusion`, `fusion-doctor`, `fusion-uninstall` symlinks are created.
- **Recommendation**: Add `ln -sf "$F360_DATA_DIR/launch-fusion.sh" "$F360_BIN_DIR/fusion360"`.

### H10. `39-windows-version.sh` relies on side-effect variable `$proton` (install-pipeline)
- **File**: `src/install/39-windows-version.sh:9`
- **Description**: Script references `$proton` but never defines it. Relies on earlier step sourcing order. If run standalone, `dirname ""` yields `.` → `./files/bin/wine` → silent failure.
- **Recommendation**: Define `proton` locally at script start.

### H11. Unknown distro silently skips ALL package installation (install-pipeline)
- **Files**: `src/install/00-common.sh:56-59`, `src/install/10-deps.sh:4-7`
- **Description**: For unrecognized distros, `INSTALL_CMD=""` and package list is empty. Script silently returns "No packages to install." Critical packages (wget, zenity, winetricks, etc.) are never installed.
- **Recommendation**: When distro is unknown and `INSTALL_CMD` is empty, print a prominent error and abort, or list required packages.

### H12. `share/disk.fn` undocumented dependency on `constants.fn` (share-library)
- **File**: `share/disk.fn`
- **Description**: Header claims "Sources: (none)" but uses `$MIN_DISK_SPACE_MB` from `share/constants.fn`. If sourced before constants.fn, variable is undefined and arithmetic error occurs.
- **Recommendation**: Document dependency or add local default.

### H13. `share/network.fn` declares `check_urls_parallel()` but never defines it (share-library)
- **File**: `share/network.fn:5`
- **Description**: "Exports" header lists `check_urls_parallel()` alongside `check_url()`, but the function body is never defined.
- **Recommendation**: Either implement the function or remove it from the header.

### H14. `share/config.fn:is_enabled()` doesn't save/restore `nocasematch` state (share-library)
- **File**: `share/config.fn:13-23`
- **Description**: `shopt -s nocasematch` enables case-insensitive matching globally, then `shopt -u nocasematch` unconditionally disables it. If caller had nocasematch enabled, this function silently breaks that assumption.
- **Recommendation**: Save and restore the shopt state.

### H15. Predictable /tmp paths — world-readable IPC, symlink race (security)
- **Files**: `share/paths.fn:42-45`, `share/browser-request.fn:15-16`, `src/runtime/fusion-browser-listener.sh:7-11`, and others
- **Description**: All bridge IPC directories, lock files, downloads use hardcoded `/tmp/` paths. Directories created with `mkdir -p` and default umask. Files inherit umask (644 = world-readable).
- **Risk**: Local attacker can pre-create symlinks. OAuth tokens in request files are world-readable. Log files contain env vars including `DBUS_SESSION_BUS_ADDRESS`.
- **Recommendation**: Set `umask 077` before creating bridge dirs. Use `mktemp -d`. Consider `$XDG_RUNTIME_DIR` instead of `/tmp`.

### H16. Browser bridge IPC — no URL validation (security)
- **Files**: `src/runtime/fusion-browser-listener.sh:86-149`, `share/browser-request.fn:76-77`
- **Description**: File-based message passing reads URL with `cat "$request_file"` and passes it directly to browser openers and callback handler. No validation of request file contents.
- **Risk**: Any process that can write to `/tmp/fusion360-browser-requests/` can inject arbitrary URLs (phishing, local file access) or manipulate OAuth flow.
- **Recommendation**: Validate URL schemes (`https://`, `fusion360://`). Restrict bridge dir permissions. Add origin check for callback URLs.

### H17. Overlay killer event loop in subshell — see C5 (runtime-daemons)
- Already covered in Critical section above.

### H18. No PID files — orphaned daemons after crash (runtime-daemons)
- **Files**: `share/daemon.fn:26-28`, `src/runtime/launcher-functions.sh:546`
- **Description**: All daemon PIDs stored in shell variables only. No PID files written to disk. If `launch-fusion.sh` is killed with SIGKILL, orphaned daemon PIDs are unrecoverable. Subsequent launch creates duplicate daemons.
- **Recommendation**: Write PID files to `/tmp/fusion360-daemon-<name>.pid`. Check for live PID before starting.

### H19. No daemon process group isolation (runtime-daemons)
- **Files**: `share/daemon.fn:37-38`, `src/runtime/launcher-functions.sh:527-528`
- **Description**: Daemons started with simple `&` backgrounding. No `nohup`, no `setsid`, no `disown`. If `launch-fusion.sh` is terminated by SIGHUP (terminal close, SSH disconnect), daemons receive SIGHUP and may die.
- **Recommendation**: Use `(nohup setsid ... &)` or at minimum `disown` after backgrounding each daemon.

### H20. No module error isolation in doctor sourcing loop (doctor-framework)
- **File**: `src/doctor/doctor.sh:21-27`
- **Description**: doctor.sh sources all modules in a simple loop with no error handling. A syntax error or crash in one module kills the entire doctor due to `set -e`.
- **Risk**: One buggy module nukes the entire diagnostic session. User gets zero output.
- **Recommendation**: Wrap source: `source "$module" 2>/dev/null || warn "Failed to load module: $(basename "$module")"`.

### H21. No GPU hardware/driver check in doctor (doctor-framework)
- **Files**: None — missing module
- **Description**: Fusion360 is a 3D CAD application requiring GPU acceleration. The doctor checks for Vulkan ICD config files but does not detect actual GPU hardware, Mesa/Vulkan driver versions, or discrete GPU availability.
- **Recommendation**: Add a `15-gpu.sh` module checking: GPU via `lspci`, Vulkan loader via `vulkaninfo --summary`, Mesa/Vulkan packages, NVIDIA driver, `DRI_PRIME` setup.

### H22. `share/traps.fn` has no EXIT trap (shell-safety)
- **File**: `share/traps.fn:8-11`
- **Description**: `setup_traps` only registers handlers for `INT` and `TERM`, not `EXIT`. Normal script exit via `exit 0` or end-of-file does NOT trigger cleanup.
- **Recommendation**: Add `EXIT` to the trap list: `trap "$cleanup_func" EXIT INT TERM`.

### H23. `install.sh:35` — duplicate signal names in trap (shell-safety)
- **File**: `install.sh:35`
- **Description**: `trap 'rm -rf "$LOCK_DIR"' EXIT INT TERM INT TERM` — `INT TERM` duplicated. Harmless but indicates copy-paste error.
- **Recommendation**: Remove the duplicate: `trap 'rm -rf "$LOCK_DIR"' EXIT INT TERM`.

### H24. `share/config.fn:is_enabled()` — `shopt` without state save/restore (shell-safety)
- Already covered in H14.

---

## MEDIUM (48 findings — key items listed)

### Shell Safety
- M1. `share/load.sh` — inefficient per-file directory resolution (26 `cd $(dirname ...)/pwd` calls)
- M2. `share/icon.fn:60,64` — string-as-command pattern (`$ok` used as bare command)
- M3. Function duplication between share/ and launcher-functions.sh (covered in C2)

### Wine/Proton
- M4. `GE_PROTON_VERSION` pinned to specific minor release (`constants.fn:11`) — goes stale
- M5. `find_proton()` returns first match, no version selection (`proton.fn:11-14`)
- M6. Each install step re-discovers Proton independently — no shared resolution
- M7. No validation that wine binary is executable (`proton_wine_bin` returns path string only)
- M8. No prefix architecture validation (win64 vs win32) in 30-prefix.sh
- M9. Prefix init failure silently swallowed (`wineboot -u 2>/dev/null || true`)
- M10. Winetricks verbs may fail silently — dotnet48 failure swallowed
- M11. `DXVK_ASYNC=1` default tied to deprecated GE-Proton feature (`constants.fn:27`)
- M12. `wine_reg()` silently suppresses all errors (`share/wine.fn:22`)
- M13. Registry writes after wineboot use bare `$wine_bin` with vague fallback message
- M14. WebView2 installation version not verified (directory check only)
- M15. WebView2 installer exit code discarded (`|| true`)
- M16. `PROTON_NO_SECCOMP=1` applied unconditionally — no config knob to re-enable
- M17. `GE-Proton11-3` hardcoded in `launch-fusion.sh:35` independent of constants

### Install Pipeline
- M18. Step ordering: deps before preflight (wasteful on failure)
- M19. No rollback on step failure — partial install state
- M20. `--prefix-only` mode doesn't call `detect_distro`
- M21. GE-Proton upgrade never detected (skip if any proton binary exists)
- M22. Uninstall gaps: CLI symlinks, runtime data dir, protocol registrations not offered
- M23. Root uninstall.sh and uninstall-select.sh inconsistent behavior
- M24. Registry entries appended directly to system.reg without proper formatting
- M25. `00-common.sh` sources share/load.sh before 00-defaults.sh — init order risk

### Share Library
- M26. `detect_proton_version()` silently returns "unknown" on empty dir
- M27. `load.sh` sources report.fn and check-dep.fn together — fragile ordering
- M28. `src/install/00-common.sh` duplicates distro detection from share/os.fn
- M29. `00-common.sh` loads share/load.sh then redefines log_* functions locally
- M30. `config_validate_keys()` returns counter variable instead of boolean
- M31. `config_quote()` glob pattern `$\'*` is fragile
- M32. `install_callback_protocol_handlers()` uses unescaped grep pattern (grep -qF needed)
- M33. `check_url()` does not verify `wget` is installed
- M34. `install_mime_icon()` uses `! $ok` pattern where `$ok` is bare string

### Security
- M35. AT bridge disabled by default (`FUSION_NO_AT_BRIDGE=1`) — accessibility impact
- M36. WebView2 sandbox disabled by default (`FUSION_WEBVIEW_NO_SANDBOX=1`)
- M37. Downloaded binaries without integrity verification (GE-Proton tarball, WebView2)
- M38. `$INSTALL_CMD $PKGS` — unquoted expansion (set -f mitigates)
- M39. Config file world-readable on disk (default umask)

### Runtime Daemons
- M40. Stale PID in `wait` after process reaped (TOCTOU in stop_all_daemons)
- M41. No log rotation — unbounded growth in /tmp
- M42. Polling-based file watcher (200ms sleep) — no inotify
- M43. Subshell starvation in browser listener (env -i per-attempt)
- M44. Health check is pre-launch only, not continuous
- M45. No daemon double-start protection

### Doctor Framework
- M46. `20-deps.sh` redefines `check_dep` locally, shadowing share/ version
- M47. No dep check for several runtime deps (pgrep, find, etc.)
- M48. `90-install.sh` uses `|| true` on counters but core pass/fail/warn doesn't
- M49. No disk space check on FUSION_ROOT or prefix (only /tmp)
- M50. No RAM/memory check
- M51. No Steam installation check for GE-Proton

---

## LOW (49 findings — selected highlights)

### Shell Safety
- L1. `share/detect-display.fn:21` — no `|| true` guard on gsettings get command substitution
- L2. `share/proton.fn:12` — empty find directory falls back to `.`
- L3. `$sizes` unquoted in `for` loops — relies on word splitting
- L4. `$EUID` in `[[ ]]` without quoting (safe in `[[ ]]`, flagged by shellcheck)
- L5. `share/browser-request.fn:15` — bridge dir fallback to `/tmp/` without mktemp
- L6. `install.sh:31` — `mkdir` lock file race on non-atomic filesystems
- L7. `src/install/40-fusion-installer.sh:129` — redundant re-source of launcher-functions.sh

### Wine/Proton
- L8. Detection only finds files literally named `proton` (misses Lutris/Proton-tkg builds)
- L9. `detect_proton_version()` returns directory basename only (symlink issue)
- L10. No DXVK version check
- L11. DXVK_CONFIG string joined with commas — fragile with comma-containing values
- L12. DPI and dark-mode registry logging appends to /tmp with no cleanup
- L13. WebView2 bootstrap download not validated (no checksum)
- L14. Bootstrap EXE not cleaned up after install
- L15. LD streaming fix uses `sed -i` without backup
- L16. No debugging env vars forwarded (DXVK_HUD, WINEDEBUG, PROTON_LOG)
- L17. `apply_launch_environment` doesn't export PROTON itself

### Install Pipeline
- L18. `run_step()` error propagation is unchecked
- L19. `uninstall-select.sh` component path for icons uses verbose glob expansion
- L20. `run_step` sources scripts — double-sourcing risk
- L21. `--prefix-only` runs pre_flight directly, skipping detect_distro
- L22. Wget downloads lack resume hash verification

### Share Library
- L23. `_is_enabled()` in daemon.fn duplicates `is_enabled()` from config.fn
- L24. `install_desktop_entry_user()` uses lossy filename generation (collision risk)
- L25. `acquire_lock()` stale lock not cleaned up except by PID comparison
- L26. `wine_reg()` and wine.fn functions suppress all stderr
- L27. `kill_installer()` sends to tracked PID only, not process group
- L28. `clear_bridge_temp_files()` may run before paths are initialized
- L29. `stop_all_daemons()` doesn't clear PID variables after killing
- L30. `detect_distro()` in os.fn uses `grep -oP` — non-POSIX Perl regex
- L31. `ensure_hosts_entry()` creates hosts file with mixed content

### Security
- L32. Sudo password prompt timing — possible leak via `ps`
- L33. No `SUDO_USER` handling in install steps
- L34. `ensure_hosts_entry()` — no backup, TOCTOU between check and append
- L35. `rm -rf` on glob over `/tmp/fusion360-*` — re-evaluate
- L36. Log file unbounded growth in /tmp
- L37. Environment variable leakage in logs (DBUS_SESSION_BUS_ADDRESS)

### Runtime Daemons
- L38. Callback handler logs environment variables to world-readable log
- L39. `kill_fusion_processes` self-kill risk (process name matches own cmdline)
- L40. Overlay killer false positive matching (legitimate Fusion dialogs could be closed)
- L41. `check_parent_still_exists` terminates overlay killer when Fusion exits gracefully
- L42. Bridge cleanup deletes files while listener may be processing

### Doctor Framework
- L43. `10-env.sh` sources `/etc/os-release` without error guard
- L44. `50-config.sh` sources config file under `set -e`
- L45. `70-processes.sh` uses `echo | wc -l` — off-by-one on empty input
- L46. `40-fusion.sh` uses hardcoded `$PFX_DIR` from caller scope
- L47. Module headers manually numbered — reorder breaks numbering
- L48. No `--help` flag
- L49. No per-module counter breakdown in summary

---

## INFO (17 findings — selected highlights)

- I1. `share/config.fn:is_enabled()` vs `launcher-functions.sh:is_enabled()` — different behavior
- I2. `share/traps.fn` is unused when `src/install/00-common.sh` is loaded
- I3. `wine_run()` expects PROTON env var, not passed as parameter
- I4. `WINEDLLOVERRIDES` for bcp47langs uses empty override — undocumented
- I5. `run_step` double-source architecture note
- I6. share/load.sh dependency documentation good but incomplete in some files
- I7. share/ function naming is consistent with some exceptions
- I8. Function argument validation patterns vary across files
- I9. `PROTON_NO_SECCOMP=1` — Seccomp disabled (known trade-off)
- I10. `kill_fusion_processes` — Can match non-Fusion processes via `pgrep -f`
- I11. Lock file race in acquire_lock (correct in practice)
- I12. Overlay killer window matching is appropriately specific
- I13. `require_root()` suggests `sudo $0` but install.sh refuses root
- I14. Browser listener `_try_open` handles browser lifecycle correctly (positive finding)
- I15. Browser listener processes all requests sequentially — UX concern
- I16. No --json/machine-readable output mode in doctor
- I17. No width-aware formatting in doctor output

---

## Supplementary Statistics

### Files with Most Issues
1. `share/daemon.fn` — 5+ findings (exit violation, dead code, PID management, duplicate daemon code)
2. `src/runtime/launcher-functions.sh` — 8+ findings (21 shadowed functions, duplicate daemon code, no PID files, trap issues)
3. `src/doctor/00-common.sh` — 5+ findings (set -e counter bug, report format duplication, color detection)
4. `share/config.fn` — 4+ findings (nocasematch corruption, source injection, duplicate is_enabled)
5. `src/install/30-prefix.sh` — 4+ findings (prefix init slience, duplicate wine_prefix code, no WINEARCH)

### Most Common Pattern Categories
| Category | Count |
|----------|-------|
| Code duplication / dead code | 8 |
| Silent error swallowing (`|| true`, `2>/dev/null`) | 7 |
| Security (perms, injection, validation) | 6 |
| No mktemp / predictable temp paths | 5 |
| set -e safety violations | 4 |
| Missing validation (input, version, exit codes) | 4 |
| Configuration persistence issues | 3 |
| Process lifecycle (orphans, races, isolation) | 5 |

### Cross-Cutting Issues (Found by 2+ Agents)
| Issue | Agents |
|-------|--------|
| share/ library overridden by launcher-functions.sh | shell-safety, share-library, runtime-daemons, wine-proton |
| No mktemp usage | shell-safety, security, install-pipeline |
| Two competing output-formatting APIs | share-library, doctor-framework |
| Config file sourced as shell code | security, share-library |
| Browser bridge IPC file permissions | security, runtime-daemons |
| No PID files for daemons | runtime-daemons, share-library |
| Dead code in share/*.fn | share-library, wine-proton, runtime-daemons |
