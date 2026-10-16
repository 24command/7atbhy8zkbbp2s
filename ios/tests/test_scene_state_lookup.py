#!/usr/bin/env python3
"""Compile the scene state declaration beside POSIX open; no Apple SDK needed.

This is a targeted C++ name-lookup regression, NOT an Objective-C++/UIKit build.
The original broken spelling must fail and the current source spelling must pass.
"""
from __future__ import annotations
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def fixture(declaration: str, name: str) -> str:
    return (
        'extern "C" int open(const char *, int, ...);\n'
        'namespace sceneimpl { ' + declaration + ' }\n'
        'namespace pmscene {\n'
        'using namespace sceneimpl;\n'
        'void probe() { ' + name + '=true; if (' + name + ') '
        + name + '=false; }\n'
        '}\n'
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cxx', nargs='+', default=[os.environ.get('CXX', 'clang++')])
    args = parser.parse_args()
    source = (ROOT/'PhiMod/Sources/PMSceneUI.mm').read_text(encoding='utf-8')
    match = re.search(r'\bbool built=false[^;]*;', source)
    if match is None or 'modEditorOpen=false' not in match.group():
        raise SystemExit('Scene editor state declaration changed; review regression fixture')
    declaration = match.group()
    flags = ['-std=c++17', '-Wall', '-Wextra', '-Werror', '-pedantic', '-c']
    with tempfile.TemporaryDirectory(prefix='phimod-name-lookup-') as tmp:
        for old in (True, False):
            name = 'open' if old else 'modEditorOpen'
            case = declaration.replace('modEditorOpen', name)
            path = Path(tmp)/('old.cpp' if old else 'fixed.cpp')
            path.write_text(fixture(case, name), encoding='utf-8')
            result = subprocess.run([*args.cxx, *flags, str(path), '-o', str(path.with_suffix('.o'))], capture_output=True, text=True)
            if old:
                if result.returncode == 0 or 'ambiguous' not in result.stderr:
                    raise SystemExit('Expected original open collision was not reproduced:\n' + result.stderr)
            elif result.returncode != 0:
                raise SystemExit('Fixed scene state failed C++ lookup regression:\n' + result.stderr)
    print('PASS scene state lookup: original open collision reproduced; renamed source compiles')


if __name__ == '__main__':
    main()
