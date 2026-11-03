#!/usr/bin/env python3
"""Exercise shutdown with real disposable processes, never a user's Wine prefix."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'src/runtime/fusion-session.py'
spec = importlib.util.spec_from_file_location('fusion_session', SOURCE)
session = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = session
spec.loader.exec_module(session)


class ShutdownTest(unittest.TestCase):
    def test_shutdown_reaps_helpers_but_preserves_other_prefix(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            prefix, other = root / 'fusion/pfx', root / 'other/pfx'
            for p in (prefix, other):
                (p / 'drive_c').mkdir(parents=True)
                (p / 'system.reg').touch()
            exe = root / 'Fusion360.exe'
            exe.symlink_to(sys.executable)
            protected = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)'],
                env=os.environ | {'WINEPREFIX': str(other), 'STEAM_COMPAT_DATA_PATH': str(prefix.parent)})
            helper = subprocess.Popen([sys.executable, '-c', 'import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(30)'],
                env=os.environ | {'WINEPREFIX': str(prefix)})
            try:
                # The fake Proton outlives Fusion, just like the observed stuck launcher.
                code = f'import subprocess,time; subprocess.Popen([{str(exe)!r}, "-c", "import time; time.sleep(1)"]); time.sleep(30)'
                result = subprocess.run([sys.executable, str(SOURCE), '--prefix', str(prefix),
                    '--wineserver', str(root / 'missing-wineserver'), '--exit-grace', '0.1',
                    '--', sys.executable, '-c', code], env=os.environ | {'WINEPREFIX': str(prefix)},
                    capture_output=True, text=True, timeout=15)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('main process started', result.stdout)
                self.assertIn('no prefix processes remain', result.stdout)
                helper.wait(timeout=2)
                self.assertIsNone(protected.poll())
            finally:
                for process in (helper, protected):
                    if process.poll() is None:
                        process.kill()
                    process.wait()

    def test_invalid_attach_does_not_clean_prefix(self):
        with tempfile.TemporaryDirectory() as directory:
            prefix = Path(directory) / 'pfx'
            (prefix / 'drive_c').mkdir(parents=True)
            (prefix / 'system.reg').touch()
            helper = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)'],
                env=os.environ | {'WINEPREFIX': str(prefix)})
            try:
                result = subprocess.run([sys.executable, str(SOURCE), '--prefix', str(prefix),
                    '--wineserver', '/missing', '--attach-pid', str(helper.pid)], capture_output=True, timeout=5)
                self.assertEqual(result.returncode, 2)
                self.assertIsNone(helper.poll())
            finally:
                helper.kill()
                helper.wait()


if __name__ == '__main__':
    unittest.main()
