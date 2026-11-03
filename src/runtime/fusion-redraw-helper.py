#!/usr/bin/env python3
"""Request Fusion X11 repaints while it is foreground; never inject input."""
import argparse
import ctypes as C
import time
import os
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
target_group = parser.add_mutually_exclusive_group(required=True)
target_group.add_argument('--pid', type=int)
target_group.add_argument('--prefix', type=Path)
parser.add_argument('--parent-pid', type=int)
parser.add_argument('--seconds', type=int, default=0, help='0: until Fusion exits')
parser.add_argument('--interval', type=float, default=0.1)
args = parser.parse_args()
if args.seconds < 0 or not 0.05 <= args.interval <= 1:
    parser.error('seconds must be nonnegative; interval must be 0.05 to 1')

x = C.CDLL('libX11.so.6')
Display = C.c_void_p
Window = C.c_ulong
x.XOpenDisplay.argtypes = [C.c_char_p]
x.XOpenDisplay.restype = Display
x.XQueryTree.argtypes = [Display, Window, C.POINTER(Window), C.POINTER(Window), C.POINTER(C.POINTER(Window)), C.POINTER(C.c_uint)]
x.XFree.argtypes = [C.c_void_p]
x.XFlush.argtypes = [Display]
x.XCloseDisplay.argtypes = [Display]
x.XDefaultRootWindow.argtypes = [Display]
x.XDefaultRootWindow.restype = Window
x.XInternAtom.argtypes = [Display, C.c_char_p, C.c_int]
x.XInternAtom.restype = C.c_ulong
x.XGetWindowProperty.argtypes = [Display, Window, C.c_ulong, C.c_long, C.c_long,
                                C.c_int, C.c_ulong, C.POINTER(C.c_ulong),
                                C.POINTER(C.c_int), C.POINTER(C.c_ulong),
                                C.POINTER(C.c_ulong), C.POINTER(C.POINTER(C.c_ubyte))]

class Expose(C.Structure):
    _fields_ = [('type', C.c_int), ('serial', C.c_ulong), ('send_event', C.c_int),
                ('display', Display), ('window', Window), ('x', C.c_int),
                ('y', C.c_int), ('width', C.c_int), ('height', C.c_int), ('count', C.c_int)]

class Event(C.Union):
    _fields_ = [('expose', Expose), ('pad', C.c_long * 24)]

x.XSendEvent.argtypes = [Display, Window, C.c_int, C.c_long, C.POINTER(Event)]
x.XGetGeometry.argtypes = [Display, Window, C.POINTER(Window), C.POINTER(C.c_int), C.POINTER(C.c_int), C.POINTER(C.c_uint), C.POINTER(C.c_uint), C.POINTER(C.c_uint), C.POINTER(C.c_uint)]
# Windows may disappear during the probe; ignore asynchronous BadWindow errors.
error_handler = C.CFUNCTYPE(C.c_int, Display, C.c_void_p)(lambda *_: 0)
x.XSetErrorHandler.argtypes = [type(error_handler)]
x.XSetErrorHandler(error_handler)
d = x.XOpenDisplay(None)
if not d:
    raise SystemExit('Cannot open X display')

atoms = {name: x.XInternAtom(d, name.encode(), 0) for name in
         ('_NET_CLIENT_LIST', '_NET_WM_PID', '_NET_ACTIVE_WINDOW', '_NET_WM_STATE',
          '_NET_WM_STATE_HIDDEN')}
root_window = x.XDefaultRootWindow(d)

def cardinal_property(window, name):
    actual_type, count, remaining = C.c_ulong(), C.c_ulong(), C.c_ulong()
    fmt, data = C.c_int(), C.POINTER(C.c_ubyte)()
    values = []
    try:
        status = x.XGetWindowProperty(d, window, atoms[name], 0, 4096, 0, 0,
                                     C.byref(actual_type), C.byref(fmt), C.byref(count),
                                     C.byref(remaining), C.byref(data))
        if status == 0 and fmt.value == 32 and data:
            items = C.cast(data, C.POINTER(C.c_ulong))
            values = [items[i] for i in range(count.value)]
    finally:
        if data:
            x.XFree(data)
    return values

def process_identity(pid):
    try:
        proc = Path('/proc') / str(pid)
        if proc.stat().st_uid != os.getuid():
            return None
        cmd = (proc / 'cmdline').read_bytes().split(b'\0')[0]
        if not cmd.lower().endswith(b'fusion360.exe'):
            return None
        # Include start time to avoid attaching to a recycled PID.
        return (proc / 'stat').read_text().rsplit(')', 1)[1].split()[19]
    except OSError:
        return None

def find_fusion():
    if args.pid:
        return args.pid if process_identity(args.pid) else None
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit() or not process_identity(int(proc.name)):
            continue
        try:
            env = dict(e.split(b'=', 1) for e in (proc / 'environ').read_bytes().split(b'\0') if b'=' in e)
            prefix = env.get(b'WINEPREFIX', b'').decode()
            if prefix and Path(prefix).resolve() == args.prefix.resolve():
                return int(proc.name)
        except (OSError, UnicodeError):
            continue
    return None

def windows(pid):
    active = cardinal_property(root_window, '_NET_ACTIVE_WINDOW')
    if not active or cardinal_property(active[0], '_NET_WM_PID') != [pid]:
        return set()
    if atoms['_NET_WM_STATE_HIDDEN'] in cardinal_property(active[0], '_NET_WM_STATE'):
        return set()
    roots = []
    for window in cardinal_property(root_window, '_NET_CLIENT_LIST'):
        if cardinal_property(window, '_NET_WM_PID') == [pid]:
            if atoms['_NET_WM_STATE_HIDDEN'] not in cardinal_property(window, '_NET_WM_STATE'):
                roots.append(window)
    found = set()
    pending = roots[:]
    while pending and len(found) < 1024:
        w = pending.pop()
        if w in found:
            continue
        found.add(w)
        root, parent = Window(), Window()
        children, count = C.POINTER(Window)(), C.c_uint()
        if x.XQueryTree(d, w, C.byref(root), C.byref(parent), C.byref(children), C.byref(count)):
            pending.extend(children[i] for i in range(count.value))
            if children:
                x.XFree(children)
    return found

print('Fusion redraw helper started; no focus or input events.', flush=True)
deadline = time.monotonic() + args.seconds if args.seconds else float('inf')
startup_deadline = time.monotonic() + 180
pid, identity = None, None
targets, next_scan = set(), 0
try:
    while time.monotonic() < deadline:
        now = time.monotonic()
        if args.parent_pid and not Path(f'/proc/{args.parent_pid}').exists():
            break
        if now >= next_scan:
            if pid is None:
                pid = find_fusion()
                if pid:
                    identity = process_identity(pid)
                    print(f'Tracking Fusion PID {pid}', flush=True)
                elif now >= startup_deadline:
                    break
            elif process_identity(pid) != identity:
                break
            targets = windows(pid) if pid else set()
            next_scan = now + 1
        # Recheck focus each tick; no redraws while another app is foreground.
        active = cardinal_property(root_window, '_NET_ACTIVE_WINDOW')
        foreground = active and cardinal_property(active[0], '_NET_WM_PID') == [pid]
        for w in targets if foreground else ():
            root, px, py = Window(), C.c_int(), C.c_int()
            width, height, border, depth = (C.c_uint() for _ in range(4))
            if not x.XGetGeometry(d, w, C.byref(root), C.byref(px), C.byref(py), C.byref(width), C.byref(height), C.byref(border), C.byref(depth)):
                continue
            event = Event()
            event.expose = Expose(12, 0, 1, d, w, 0, 0, width.value, height.value, 0)
            x.XSendEvent(d, w, 0, 1 << 15, C.byref(event))
        x.XFlush(d)
        time.sleep(args.interval)
finally:
    x.XCloseDisplay(d)
    print('Fusion redraw helper stopped.', flush=True)
