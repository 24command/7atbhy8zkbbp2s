"""Run the isolated puzzle host suite. Optional argv: compiler and its flags."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    ios = Path(__file__).resolve().parents[1]
    compiler = sys.argv[1:] or [os.environ.get("CC", "cc")]
    sources = [*sorted((ios / "PhiMod/Vendor/lua54").glob("*.c")),
               ios / "PhiMod/Core/PMChapterVM.c", ios / "tests/PMChapterPuzzleTest.c"]
    with tempfile.TemporaryDirectory(prefix="pm-puzzle-") as temp:
        exe = Path(temp) / ("puzzle.exe" if os.name == "nt" else "puzzle")
        subprocess.run([*compiler, "-std=c99", "-UNDEBUG", *sources, "-lm", "-o", exe], check=True, cwd=temp)
        subprocess.run([exe], cwd=temp, check=True)


if __name__ == "__main__":
    main()
