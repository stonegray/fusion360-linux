# Code Review Summary — Fusion360-Linux

**7-agent review · 67 files · 5347 lines · 144+ findings**

---

## Cross-Cutting Patterns

1. **share/ library vs `launcher-functions.sh` duplication** — 21+ functions exist in BOTH the new share/ library and the legacy `src/runtime/launcher-functions.sh`. The share/ definitions are silently overridden. Bug fixes in share/ have zero effect at runtime.
2. **Zero `mktemp` usage** — Every temp file across the entire codebase uses hardcoded `/tmp/` paths. No symlink-race protection, no automatic cleanup on crash.
3. **Two output-formatting APIs** — `share/report.fn` and `src/doctor/00-common.sh` both define `pass`/`fail`/`warn`/`log_*` with different color variables. The share/ versions are immediately overridden and dead.
4. **`set -e` discipline mostly good** — Only one clear `exit` in a sourced library (`share/daemon.fn:35`). However, the doctor framework's `((SECTION_*++))` pattern triggers `set -e` abort on the first check.
5. **Config world-readable, sourced as shell code** — The config file is `source`d (arbitrary code execution) and has default 644 permissions.

---

## Quick Wins (easy fixes, high impact)

- Replace `exit 1` with `return 1` in `share/daemon.fn:35`
- Add `exit 0` after `--uninstall` block in `install.sh:75`
- Fix `((SECTION_*++))` → `((++SECTION_*))` or add `|| true` in `src/doctor/00-common.sh:53-55`
- Fix literal `\t` in `share/hosts.fn:22` — use `$'\t'`
- Remove duplicate `INT TERM` from `install.sh:35` trap

---

## Per-Agent Findings

### Shell Safety — 14 findings (1 CRITICAL, 3 HIGH)

- `share/daemon.fn:35` calls `exit 1` in a sourced library — kills the launcher process
- `share/hosts.fn:22` literal `\t` instead of tab — hosts file corruption on second call
- 21 functions in `launcher-functions.sh` shadow share/ counterparts — entire share/ library is dead code through the normal launch path
- No `mktemp` anywhere — all 67 files use hardcoded `/tmp/` paths

### Wine/Proton — 33 findings (3 HIGH, 14 MEDIUM)

- `wine_prefix_init()` and `winetricks_run()` in `share/wine.fn` are dead code — never called
- DPI detection functions duplicated between `share/detect-display.fn` and `launcher-functions.sh`
- Wine binary path derived 4+ different ways instead of using `proton_wine_bin()`
- `DXVK_ASYNC=1` default tied to deprecated GE-Proton feature
- Prefix init failure silently swallowed (`wineboot -u || true`)
- WebView2 installer exit code discarded, version never verified

### Install Pipeline — 19 findings (1 CRITICAL, 6 HIGH)

- `--uninstall` fall-through to full re-install (CRITICAL)
- Config file never updates existing keys on reinstall
- Phantom "Step 8/14" is a no-op
- `fusion360` CLI symlink claimed but never created
- `39-windows-version.sh` relies on side-effect variable `$proton`
- Unknown distros silently skip ALL package installation
- No rollback on step failure

### Share Library — 22 findings (2 CRITICAL, 4 HIGH)

- `exit` in `share/daemon.fn:35` — only `exit` violation in 25 fn files
- Massive duplication: 18+ functions in share/ overridden by launcher-functions.sh
- `share/hosts.fn:22` literal `\t` (HIGH)
- `share/disk.fn` claims "Sources: (none)" but depends on `constants.fn`
- `share/network.fn` declares `check_urls_parallel()` but never defines it
- `share/config.fn:is_enabled()` doesn't save/restore `nocasematch` state

### Security — 20 findings (1 CRITICAL, 2 HIGH)

- Config file `source`d as shell code (CRITICAL) — arbitrary code execution vector
- All bridge IPC paths in `/tmp/` are world-readable — OAuth token exposure (HIGH)
- Browser bridge IPC has no URL validation — injection via request files (HIGH)
- AT bridge disabled by default — accessibility impact (MEDIUM)
- WebView2 sandbox disabled by default (MEDIUM)
- No input validation on bridge IPC file contents

### Runtime Daemons — 17 findings (1 CRITICAL, 3 HIGH)

- Overlay killer event loop runs in pipeline subshell — `exit 0` doesn't exit the script (CRITICAL)
- No PID files — orphaned daemons after crash, double-start possible (HIGH)
- Daemon process group isolation missing — SIGHUP kills daemons (HIGH)
- Duplicate daemon management code (share/ vs launcher-functions.sh) (HIGH)
- No log rotation — `/tmp` fills over long sessions (MEDIUM)
- Polling-based file watcher (200ms latency) — use `inotifywait` (MEDIUM)
- No continuous health monitoring — daemon death undetected mid-session (MEDIUM)

### Doctor Framework — 19 findings (1 CRITICAL, 3 HIGH)

- `((SECTION_*++))` under `set -e` aborts doctor on first check (CRITICAL) — framework is non-functional
- No module error isolation — single module crash kills entire doctor (HIGH)
- No GPU hardware/driver check (HIGH)
- `20-deps.sh` shadows `share/check-dep.fn` with a simpler version (MEDIUM)
- No disk space, RAM, or Steam installation checks (MEDIUM)
- Two competing output APIs (share/report.fn vs 00-common.sh) (MEDIUM)

---

## Findings by Severity

| Severity | Count | Agents |
|----------|-------|--------|
| CRITICAL | 6 | shell-safety, install-pipeline, share-library, security, runtime-daemons, doctor-framework |
| HIGH | 24 | all 7 agents |
| MEDIUM | 48+ | all 7 agents |
| LOW/INFO | 66+ | all 7 agents |

- **Critical**: 6 findings across 6 of 7 agents
- **High**: 24 findings across all 7 agents
- **Total**: 144+ findings across all severity levels
