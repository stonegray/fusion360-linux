#!/usr/bin/env python3
"""Supervise Fusion and reap processes belonging to its dedicated Wine prefix."""
import argparse
from dataclasses import dataclass
import os
from pathlib import Path
import signal
import subprocess
import sys
import time


@dataclass
class Process:
    pid: int
    identity: str
    argv: list
    env: dict


def inspect_process(pid):
    try:
        proc = Path('/proc') / str(pid)
        if proc.stat().st_uid != os.getuid():
            return None
        stat = (proc / 'stat').read_text().rsplit(')', 1)[1].split()
        if stat[0] == 'Z':
            return None
        argv = [os.fsdecode(v) for v in (proc / 'cmdline').read_bytes().split(b'\0') if v]
        env = dict(os.fsdecode(v).split('=', 1) for v in
                   (proc / 'environ').read_bytes().split(b'\0') if b'=' in v)
        return Process(pid, stat[19], argv, env)
    except (OSError, ValueError, IndexError):
        return None


def same_path(value, expected):
    return bool(value) and Path(value).resolve() == expected


def prefix_processes(prefix):
    found = []
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit() or int(proc.name) == os.getpid():
            continue
        item = inspect_process(int(proc.name))
        if not item:
            continue
        wine_prefix = item.env.get('WINEPREFIX')
        # An explicit different WINEPREFIX takes precedence over inherited Steam vars.
        matches = same_path(wine_prefix, prefix) if wine_prefix else same_path(
            item.env.get('STEAM_COMPAT_DATA_PATH'), prefix.parent)
        if matches:
            found.append(item)
    return found


def is_fusion_main(process):
    return bool(process.argv) and process.argv[0].replace('\\', '/').rsplit('/', 1)[-1].lower() == 'fusion360.exe' and not any(
        arg.startswith('--type=') for arg in process.argv[1:])


def signal_process(process, sig):
    current = inspect_process(process.pid)
    if current and current.identity == process.identity:
        try:
            os.kill(process.pid, sig)
        except ProcessLookupError:
            pass


def stop_prefix(prefix, wineserver):
    """Bounded shutdown: prefix-specific Wine server, TERM, then KILL survivors."""
    print(f'Fusion session: shutting down prefix {prefix}', flush=True)
    env = os.environ.copy()
    env['WINEPREFIX'] = str(prefix)
    if wineserver.is_file():
        try:
            subprocess.run([str(wineserver), '-k'], env=env, timeout=5,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except (OSError, subprocess.TimeoutExpired):
            pass
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        remaining = prefix_processes(prefix)
        if not remaining:
            break
        for proc in remaining:
            signal_process(proc, signal.SIGTERM)
        time.sleep(0.2)
    # Rescan to include children created during shutdown; verify identities before killing.
    for _ in range(10):
        remaining = prefix_processes(prefix)
        if not remaining:
            print('Fusion session: no prefix processes remain.', flush=True)
            return True
        for proc in remaining:
            signal_process(proc, signal.SIGKILL)
        time.sleep(0.2)
    remaining = prefix_processes(prefix)
    if remaining:
        print('Fusion session: processes still present: ' + ', '.join(str(p.pid) for p in remaining), file=sys.stderr)
        return False
    print('Fusion session: no prefix processes remain.', flush=True)
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prefix', type=Path, required=True)
    parser.add_argument('--wineserver', type=Path, required=True)
    parser.add_argument('--attach-pid', type=int)
    parser.add_argument('--exit-grace', type=float, default=5)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    prefix = args.prefix.resolve()
    # Refuse broad or accidental targets; cleanup is for an initialized dedicated prefix.
    if prefix == Path.home() or not (prefix / 'system.reg').is_file() or not (prefix / 'drive_c').is_dir():
        parser.error('Expected an initialized, dedicated Wine prefix')
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not args.attach_pid and not command:
        parser.error('Supply a command or --attach-pid')
    if args.exit_grace < 0:
        parser.error('exit-grace must be nonnegative')
    if args.attach_pid:
        attached = inspect_process(args.attach_pid)
        if not attached or not is_fusion_main(attached) or not any(
                p.pid == args.attach_pid for p in prefix_processes(prefix)):
            parser.error('Attach target is not Fusion in the requested prefix')

    def interrupted(signum, _frame):
        raise InterruptedError(signum)

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    child = None
    status = 0
    seen_main = False
    absent_since = None
    startup_deadline = time.monotonic() + 180
    try:
        if args.attach_pid:
            seen_main = True
            print(f'Fusion session: attached to PID {args.attach_pid}', flush=True)
        else:
            child = subprocess.Popen(command, start_new_session=True)
        while True:
            processes = prefix_processes(prefix)
            mains = [p for p in processes if is_fusion_main(p)]
            if mains:
                if not seen_main:
                    print(f'Fusion session: main process started (PID {mains[0].pid})', flush=True)
                seen_main = True
                absent_since = None
            elif seen_main:
                absent_since = absent_since or time.monotonic()
                if time.monotonic() - absent_since >= args.exit_grace:
                    print('Fusion session: main process exited; cleaning up background processes.', flush=True)
                    if child and child.poll() is not None:
                        status = child.returncode
                    break
            elif child and child.poll() is not None:
                status = child.returncode
                break
            elif time.monotonic() >= startup_deadline:
                print('Fusion session: startup timed out.', file=sys.stderr)
                status = 1
                break
            time.sleep(0.5)
    except InterruptedError:
        status = 130
    except OSError as exc:
        print(f'Fusion session: {exc}', file=sys.stderr)
        status = 1
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        if not stop_prefix(prefix, args.wineserver):
            status = status or 1
        if child:
            try:
                child.wait(timeout=3)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
    return 128 - status if status < 0 else status


if __name__ == '__main__':
    sys.exit(main())
