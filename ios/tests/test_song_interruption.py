"""Compile and run the production portable owner. No UIKit/string-only substitute."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SongInterruptionRuntime(unittest.TestCase):
    def test_production_owner(self):
        compiler = os.environ.get('CXX') or shutil.which('clang++') or shutil.which('g++') or shutil.which('cl')
        vcvars = Path('D:/Program Files (x86)/Microsoft Visual Studio/2019/Community/VC/Auxiliary/Build/vcvars64.bat')
        if not compiler and not (os.name == 'nt' and vcvars.is_file()):
            self.skipTest('C++17 compiler unavailable')
        # Never put build products/cache in the source checkout or on C:/F:.
        base = Path(os.environ.get('PM_INTERRUPTION_TEST_TMP', 'G:/PhiMod-package30/interruption-tests' if os.name == 'nt' else '/tmp/interruption-tests'))
        if os.name == 'nt' and base.resolve().drive.upper() not in ('D:', 'G:'):
            self.fail('Interruption test scratch must be on D: or G:')
        base.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='cpu-', dir=base) as folder:
            folder = Path(folder)
            output = folder / ('owner.exe' if os.name == 'nt' else 'owner')
            source = ROOT / 'tests/PMSongInterruptionTest.cpp'
            is_msvc = not compiler or Path(compiler).name.lower() in ('cl', 'cl.exe')
            if is_msvc:
                command = [compiler or 'cl', '/nologo', '/std:c++17', '/EHsc', '/W4', '/WX', '/utf-8',
                           str(source), '/Fe:' + str(output), '/Fo:' + str(folder / 'owner.obj')]
            else:
                command = [compiler, '-std=c++17', '-Wall', '-Wextra', '-Werror', str(source), '-o', str(output)]
            if not compiler:
                script = folder / 'build.cmd'
                script.write_text('@echo off\ncall "' + str(vcvars) + '" >nul\nif errorlevel 1 exit /b %errorlevel%\n' +
                                  subprocess.list2cmdline(command) + '\n', encoding='utf-8')
                command = ['cmd.exe', '/d', '/c', str(script)]
            env = dict(os.environ, TEMP=str(folder), TMP=str(folder), PYTHONDONTWRITEBYTECODE='1')
            result = subprocess.run(command, cwd=folder, env=env, capture_output=True, text=True, errors='replace', timeout=120)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run([str(output)], cwd=folder, env=env, capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('18 groups passed', result.stdout)
            print(result.stdout.strip())


if __name__ == '__main__':
    unittest.main()
