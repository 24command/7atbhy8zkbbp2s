"""Portable compiler support for the configured compiler or Windows MSVC shim."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest


def compiler_command():
    cxx = os.getenv('CXX') or shutil.which('clang++') or shutil.which('g++')
    if not cxx:
        raise unittest.SkipTest('requires a C++17 compiler')
    return [cxx] + (['c++'] if Path(cxx).stem.lower() == 'zig' else [])


def compile_cpp(code, directory, name='fixture'):
    source = Path(directory) / (name + '.cpp')
    executable = source.with_suffix('.exe')
    # A failed assertion must fail the test, not open a modal Windows CRT dialog.
    quiet = r"""
#ifdef _WIN32
#include <cstdlib>
struct QuietAssertions {
    QuietAssertions() {
        _set_error_mode(_OUT_TO_STDERR);
        _set_abort_behavior(0, _WRITE_ABORT_MSG | _CALL_REPORTFAULT);
    }
} quietAssertions;
#endif
"""
    source.write_text(quiet + code, encoding='utf-8')
    result = subprocess.run(compiler_command() + ['-std=c++17', str(source), '-o', str(executable)],
                            capture_output=True, text=True, timeout=120)
    if result.returncode:
        raise AssertionError('C++ compilation failed:\n' + result.stdout + result.stderr)
    return executable


def run_cpp(case, executable, *args):
    result = subprocess.run([str(executable), *args], capture_output=True, text=True, timeout=30)
    case.assertEqual(result.returncode, 0, result.stdout + result.stderr)
