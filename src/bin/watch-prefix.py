#!/usr/bin/env python3
"""watch-prefix.py — Discover what Fusion 360 touches in its Proton prefix.

Purpose: reverse-engineering. Answers "what does Fusion actually read and
write?" rather than "is Fusion healthy?" — so it does not filter churn. It
reports every change and lets you decide what is signal.

Two things it gives you that inotify does not:

  * The initial inventory. A first pass records everything already in the
    tree, so you learn the layout without relying on Fusion to touch it.
  * Changes that happened before you started. A snapshot diff picks up
    files written between launches.

Inotify also would not work here as-is: neither inotifywait nor fswatch is
installed, and the tree is ~6.2 GB across ~9.8k directories.

Output:
  Live    — one line per change, timestamped, as it is detected.
  Summary — unique paths grouped by kind, printed on Ctrl-C / at session end.

Usage:
  ./watch-prefix.py                     # default Fusion + Neutron paths
  ./watch-prefix.py --interval 0.5      # faster polling
  ./watch-prefix.py --inventory         # list tree, no watching
  ./watch-prefix.py --root "$PFX/drive_c/users/steamuser/AppData/Local/Autodesk"
  ./watch-prefix.py --since 15m         # also report what changed recently

Exit: 0 clean, 1 error, 130 interrupted.
"""

from __future__ import annotations

import argparse
import os
import signal
import sys
import time
from collections import Counter
from datetime import datetime, timedelta

# Paths are resolved relative to the prefix at runtime. Neutron Platform is
# nested inside Autodesk, so listing it separately would report every file
# twice; the overlap is collapsed when roots are normalised.
DEFAULT_SUBDIRS = (
    "pfx/drive_c/users/steamuser/AppData/Local/Autodesk",
)

# Directories excluded by default purely for cost. webdeploy/production holds
# the Fusion install payload — 101,484 of 102,810 files, 98.7% of the tree —
# and is written only at install/update time. Scanning it takes 2.8s per pass;
# without it a pass takes 0.12s. Everything here is static install payload,
# not runtime state, so excluding it loses nothing during discovery.
# --include-cache opts back in when tracing an update.
CACHE_HINTS = (
    "/webdeploy/production/",
    "/cer/",
)

KIND_ORDER = ("created", "modified", "deleted")


def default_prefix() -> str:
    """Mirror the installer's prefix resolution."""
    env = os.environ.get("STEAM_COMPAT_DATA_PATH")
    if env:
        return os.path.expanduser(env)
    cfg = os.path.expanduser("~/.config/fusion360-linux/config")
    try:
        with open(cfg, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if line.startswith("#") or "=" not in line:
                    continue
                key, _, val = line.partition("=")
                if key.strip() == "STEAM_COMPAT_DATA_PATH":
                    return os.path.expanduser(val.strip().strip("'\""))
    except OSError:
        pass
    return os.path.expanduser("~/.fusion360-proton2")


def resolve_roots(prefix: str, extra: list[str]) -> list[str]:
    """Build a deduplicated, overlap-collapsed set of watch roots."""
    raw = [os.path.join(prefix, s) for s in DEFAULT_SUBDIRS] + extra
    out: list[str] = []
    for p in raw:
        p = os.path.realpath(os.path.expanduser(p))
        if not os.path.isdir(p):
            print(f"  ! skipping (not a directory): {p}", file=sys.stderr)
            continue
        # Drop a root already covered by a parent we are watching, so a file
        # is never reported twice.
        if any(p == q or p.startswith(q + os.sep) for q in out):
            continue
        out = [q for q in out if not q.startswith(p + os.sep)]
        out.append(p)
    return out


def snapshot(roots: list[str], prune: bool) -> dict[str, tuple[int, int]]:
    """Map path -> (size, mtime_ns).

    Size and mtime together catch rewrites that preserve one of them. A file
    written twice within the same timestamp tick with no size change is the
    one case this misses; ns-resolution mtimes make that vanishingly rare.
    """
    snap: dict[str, tuple[int, int]] = {}
    for root in roots:
        for dirpath, dirnames, filenames in os.walk(root, onerror=lambda _e: None):
            if prune and any(h in (dirpath + "/").lower() for h in CACHE_HINTS):
                dirnames[:] = []
                continue
            for name in filenames:
                full = os.path.join(dirpath, name)
                try:
                    st = os.lstat(full)
                except OSError:
                    continue
                if not os.path.isfile(full):
                    continue
                snap[full] = (st.st_size, st.st_mtime_ns)
    return snap


def diff(old: dict, new: dict) -> list[tuple[str, str]]:
    """Return (kind, path) for each change, in a stable order."""
    events: list[tuple[str, str]] = []
    for path, meta in new.items():
        prev = old.get(path)
        if prev is None:
            events.append(("created", path))
        elif prev != meta:
            events.append(("modified", path))
    for path in old:
        if path not in new:
            events.append(("deleted", path))
    events.sort(key=lambda e: (KIND_ORDER.index(e[0]), e[1]))
    return events


def human_size(n: int) -> str:
    for unit in ("B", "K", "M", "G"):
        if n < 1024 or unit == "G":
            return f"{n:.0f}{unit}" if unit == "B" else f"{n:.1f}{unit}"
        n /= 1024.0
    return f"{n}B"


def parse_since(text: str) -> int:
    """Accept 30s / 15m / 2h and return seconds."""
    text = text.strip().lower()
    mult = {"s": 1, "m": 60, "h": 3600}.get(text[-1:], None)
    if mult is None:
        raise argparse.ArgumentTypeError("expected a duration like 30s, 15m, 2h")
    try:
        return int(float(text[:-1]) * mult)
    except ValueError:
        raise argparse.ArgumentTypeError("expected a duration like 30s, 15m, 2h")


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(
        description="Watch the Fusion prefix for changed files (discovery mode).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Summary prints on Ctrl-C. See module docstring for rationale.",
    )
    ap.add_argument("--prefix", default=None, help="Proton prefix root (default: from config)")
    ap.add_argument(
        "--root",
        action="append",
        default=[],
        metavar="DIR",
        help="extra directory to watch (repeatable)",
    )
    ap.add_argument("--interval", type=float, default=2.0, help="poll seconds (default: 2)")
    ap.add_argument("--inventory", action="store_true", help="list the tree and exit")
    ap.add_argument("--since", type=parse_since, metavar="DUR",
                    help="also report files modified within DUR (e.g. 15m) and exit")
    ap.add_argument("--include-cache", action="store_true",
                    help="also scan webdeploy/CER (2.8s/scan instead of 0.12s)")
    ap.add_argument("--quiet", action="store_true", help="suppress the live stream")
    ap.add_argument("--absolute", action="store_true",
                    help="print full paths instead of paths relative to the prefix")
    args = ap.parse_args(argv)

    prefix = os.path.realpath(os.path.expanduser(args.prefix or default_prefix()))
    if not os.path.isdir(prefix):
        print(f"error: prefix not found: {prefix}", file=sys.stderr)
        return 1

    roots = resolve_roots(prefix, args.root)
    if not roots:
        print("error: no readable watch roots", file=sys.stderr)
        return 1

    def show(path: str) -> str:
        if args.absolute:
            return path
        rel = os.path.relpath(path, prefix)
        return rel if not rel.startswith("..") else path

    print(f"prefix: {prefix}", file=sys.stderr)
    for r in roots:
        print(f"root:   {show(r) if not args.absolute else r}", file=sys.stderr)

    prune = not args.include_cache
    base = snapshot(roots, prune)
    print(f"baseline: {len(base)} files", file=sys.stderr)

    if args.inventory:
        for path in sorted(base):
            print(show(path))
        return 0

    if args.since is not None:
        cutoff = time.time() - args.since
        recent = [(p, m) for p, m in base.items() if m[1] / 1e9 >= cutoff]
        recent.sort(key=lambda pm: pm[1][1], reverse=True)
        since_label = (datetime.now() - timedelta(seconds=args.since)).strftime("%H:%M:%S")
        print(f"\nchanged since {since_label} ({len(recent)} files):")
        for path, (size, mtime) in recent:
            stamp = datetime.fromtimestamp(mtime / 1e9).strftime("%H:%M:%S")
            print(f"  {stamp}  {human_size(size):>7}  {show(path)}")
        return 0

    counts: Counter[str] = Counter()
    seen: dict[str, set[str]] = {k: set() for k in KIND_ORDER}
    started = time.time()
    total_events = 0

    def report(kind: str, path: str, size: int = -1) -> None:
        nonlocal total_events
        total_events += 1
        counts[kind] += 1
        seen[kind].add(path)
        if not args.quiet:
            stamp = datetime.now().strftime("%H:%M:%S")
            sz = f" {human_size(size):>7}" if size >= 0 else ""
            print(f"  {stamp} {kind:<8}{sz}  {show(path)}", flush=True)

    def on_signal(signum, _frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGINT, on_signal)
    signal.signal(signal.SIGTERM, on_signal)

    print("\nwatching — Ctrl-C for summary\n", file=sys.stderr)
    try:
        while True:
            time.sleep(max(args.interval, 0.1))
            try:
                current = snapshot(roots, prune)
            except Exception as exc:  # noqa: BLE001 - keep watching through IO hiccups
                print(f"  ! scan failed: {exc}", file=sys.stderr)
                continue
            for kind, path in diff(base, current):
                report(kind, path, current[path][0] if kind != "deleted" else -1)
            base = current
    except KeyboardInterrupt:
        pass

    elapsed = time.time() - started
    print("\n" + "=" * 60)
    print(f"summary — {elapsed:.0f}s, {total_events} events, "
          f"{sum(len(v) for v in seen.values())} unique paths")
    print("=" * 60)
    if total_events == 0:
        print("no changes detected")
    for kind in KIND_ORDER:
        paths = seen[kind]
        if not paths:
            continue
        print(f"\n{kind} ({len(paths)}):")
        for path in sorted(paths):
            print(f"  {show(path)}")

    if total_events:
        print("\nby directory:")
        for d, n in Counter(os.path.dirname(show(p)) for k in KIND_ORDER
                            for p in seen[k]).most_common(15):
            print(f"  {n:>5}  {d}")

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
