"""Run entry-transition VM behavior and portable regressions, never native hosts.
Optional argv: C compiler and its flags (same convention as run_chapter_puzzle.py).
All compiler output stays in a temporary directory outside the source tree.
"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    ios = Path(__file__).resolve().parents[1]
    compiler = sys.argv[1:] or [os.environ.get("CC", "cc")]
    sources = [*sorted((ios / "PhiMod/Vendor/lua54").glob("*.c")),
               ios / "PhiMod/Core/PMChapterVM.c"]
    tests = ["PMChapterEntryTransitionTest", "PMChapterVMTest", "PMChapterC9RouteTest",
             "PMChapterSongVisibilityTest", "PMChapterC8WaveformTest",
             "PMChapterPuzzleTest", "PMChapterLifeTest"]
    with tempfile.TemporaryDirectory(prefix="pm-entry-vm-") as temp:
        # One explicit object per source also works with Zig's Windows COFF driver.
        objects = []
        for source in sources:
            obj = Path(temp) / (source.stem + ".o")
            subprocess.run([*compiler, "-std=c99", "-O1", "-UNDEBUG", "-c", source,
                            "-o", obj], check=True, cwd=temp)
            objects.append(obj)
        for test in tests:
            exe = Path(temp) / (test + (".exe" if os.name == "nt" else ""))
            subprocess.run([*compiler, "-std=c99", "-O1", "-UNDEBUG",
                            ios / f"tests/{test}.c", *objects, "-lm", "-o", exe], check=True, cwd=temp)
            print(f"RUN {test}", flush=True)
            subprocess.run([exe], check=True, cwd=temp)
    print(f"Passed {len(tests)} portable VM suites.", flush=True)


if __name__ == "__main__":
    main()
