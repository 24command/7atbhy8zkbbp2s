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



def rect_fixture(declaration: str) -> str:
    return (
        'struct Rect { short top,left,bottom,right; };\n'
        'namespace sceneimpl { struct Rect { float x,y,w,h; }; }\n'
        'struct Runtime { void* call(void*,const char*) { return nullptr; } '
        'template<class T> T unbox(void*) { return {}; } };\n'
        'namespace pmscene { using namespace sceneimpl; '
        'void probe(Runtime&r,void*tr) { ' + declaration + ' (void)rect; } }\n'
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
    native = (ROOT/'PhiMod/Sources/PMNativeModSettings.inc').read_text(encoding='utf-8')
    rect_match = re.search(r'(?:sceneimpl::)?Rect rect=r\.unbox<(?:sceneimpl::)?Rect>\(r\.call\(tr,"get_rect"\)\);', native)
    if rect_match is None:
        raise SystemExit('Native settings rectangle declaration changed; review regression fixture')
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
        for old in (True, False):
            case = rect_match.group().replace('sceneimpl::Rect', 'Rect') if old else rect_match.group()
            path = Path(tmp)/('old-rect.cpp' if old else 'fixed-rect.cpp')
            path.write_text(rect_fixture(case), encoding='utf-8')
            result = subprocess.run([*args.cxx, *flags, str(path), '-o', str(path.with_suffix('.o'))], capture_output=True, text=True)
            if old:
                if result.returncode == 0 or 'ambiguous' not in result.stderr:
                    raise SystemExit('Expected Apple Rect collision was not reproduced:\n' + result.stderr)
            elif result.returncode != 0:
                raise SystemExit('Qualified rectangle failed C++ lookup regression:\n' + result.stderr)
    print('PASS scene lookup: original open and Apple Rect collisions reproduced; production spellings compile')


if __name__ == '__main__':
    main()
