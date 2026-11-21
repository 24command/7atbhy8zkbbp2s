"""Run the portable handoff test, plus exact door/progress integration on macOS."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

TESTS = Path(__file__).resolve().parent
SRC = TESTS.parent / 'PhiMod' / 'Sources'

class StorySequence(unittest.TestCase):
    def test_handoff(self):
        with tempfile.TemporaryDirectory() as d:
            src = str(TESTS / 'PMStorySequenceHandoffTest.cpp')
            if os.name == 'nt':
                cmd = [os.environ.get('CXX', 'cl'), '/nologo', '/EHsc', '/std:c++17', src, '/Fe:test.exe']
                exe = 'test.exe'
            else:
                cmd = [os.environ.get('CXX', 'c++'), '-std=c++17', '-Wall', '-Wextra', '-Werror', src, '-o', 'test']
                exe = 'test'
            subprocess.run(cmd, cwd=d, check=True)
            subprocess.run([Path(d) / exe], cwd=d, check=True)

    @unittest.skipUnless(sys.platform == 'darwin', 'requires Apple Foundation')
    def test_exact_door_sequence(self):
        with tempfile.TemporaryDirectory() as d:
            exe = Path(d) / 'sequence'
            subprocess.run(['clang++','-std=c++17','-fobjc-arc','-DPMDOOR_RUN_HOST_TEST',
                            '-framework','Foundation','-framework','CoreFoundation',
                            TESTS/'PMStorySequenceTest.mm', SRC/'PMDoorRun.mm', SRC/'PMStorySequence.mm',
                            SRC/'PMOSAuthorProgress.mm','-o',exe], cwd=d, check=True)
            subprocess.run([exe], cwd=d, check=True)

if __name__ == '__main__':
    unittest.main()
