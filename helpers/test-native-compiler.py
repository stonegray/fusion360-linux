#!/usr/bin/env python3
"""Test compiler setup using disposable prefix files, without running Wine."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class CompilerTest(unittest.TestCase):
    def test_backup_idempotence_update_and_opt_out(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app, prefix = root / 'app', root / 'compat'
            source = app / 'd3dcompiler_v2/d3dcompiler_47.dll'
            target = prefix / 'pfx/drive_c/windows/system32/d3dcompiler_47.dll'
            source.parent.mkdir(parents=True)
            target.parent.mkdir(parents=True)
            source.write_bytes(b'native')
            target.write_bytes(b'original')
            env = os.environ | {'FUSION_DIR': str(app), 'STEAM_COMPAT_DATA_PATH': str(prefix),
                                'FUSION_NATIVE_D3DCOMPILER': '1'}

            def prepare(extra=None):
                return subprocess.run(['bash', '-eu', '-c',
                    'source src/runtime/launcher-functions.sh; prepare_native_shader_compiler'],
                    cwd=REPO, env=env | (extra or {}), capture_output=True, text=True, check=True)

            prepare()
            self.assertEqual(target.read_bytes(), b'native')
            backups = list((prefix / 'shader-compiler-backups').glob('*.dll'))
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].read_bytes(), b'original')
            prepare()
            self.assertEqual(len(list((prefix / 'shader-compiler-backups').glob('*.dll'))), 1)
            source.write_bytes(b'updated')
            prepare({'FUSION_NATIVE_D3DCOMPILER': '0'})
            self.assertEqual(target.read_bytes(), b'native')
            prepare()
            self.assertEqual(target.read_bytes(), b'updated')


if __name__ == '__main__':
    unittest.main()
