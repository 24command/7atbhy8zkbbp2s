#!/usr/bin/env python3
"""Create an unsigned PhiMod IPA from an extracted Payload and PhiMod.framework.

The result is intentionally unsigned. A real signing tool must recursively sign
PhiMod.framework, UnityFramework.framework, and the main app with a compatible
certificate/profile before a non-jailbroken device can install it.
"""
from __future__ import annotations
import argparse
import plistlib
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

DEPENDENCY = "@loader_path/../PhiMod.framework/PhiMod"


def find_app(payload: Path) -> Path:
    apps = list(payload.glob("*.app"))
    if len(apps) != 1:
        raise RuntimeError(f"expected exactly one app under Payload, found {len(apps)}")
    return apps[0]


def strip_signatures(app: Path) -> None:
    for signature in app.rglob("_CodeSignature"):
        if signature.is_dir():
            shutil.rmtree(signature)
    for provision in app.rglob("embedded.mobileprovision"):
        provision.unlink()


def zip_tree(root: Path, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(root.rglob("*")):
            if path.is_file():
                name = path.relative_to(root).as_posix()
                entry = zipfile.ZipInfo.from_file(path, name)
                entry.create_system = 3
                executable = path.name in ("Phigros", "UnityFramework", "PhiMod")
                entry.external_attr = (0o100755 if executable else 0o100644) << 16
                entry.compress_type = zipfile.ZIP_DEFLATED
                with path.open("rb") as source, archive.open(entry, "w", force_zip64=True) as target:
                    shutil.copyfileobj(source, target, 1024 * 1024)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path, help="directory containing Payload")
    parser.add_argument("--framework", required=True, type=Path, help="compiled PhiMod.framework")
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    source_payload = args.source / "Payload"
    if not source_payload.is_dir():
        raise RuntimeError(f"missing Payload: {source_payload}")
    if not (args.framework / "PhiMod").is_file():
        raise RuntimeError(f"missing framework executable: {args.framework / 'PhiMod'}")

    binary = (args.framework / "PhiMod").read_bytes()
    if b"PMGameplay-v1" in binary or any(marker not in binary for marker in (b"PMJudgeHook-v1", b"PMGameplay-v2", b"PMGameplay-contract-v2-57")):
        raise RuntimeError("Stale framework: requires PMGameplay-v2 with all 57 gates; rebuild the new sources first")

    tools = Path(__file__).resolve().parent
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="phimod-ipa-", dir=args.output.parent) as temporary:
        stage = Path(temporary)
        shutil.copytree(source_payload, stage / "Payload", symlinks=True,
                        ignore=shutil.ignore_patterns("UnityFramework.id0", "UnityFramework.id1",
                            "UnityFramework.id2", "UnityFramework.nam", "UnityFramework.til",
                            "UnityFramework.i64", "UnityFramework.idb", "*.before-phimod", "*.before-judge", "*.before-gameplay"))
        app = find_app(stage / "Payload")
        info = plistlib.loads((app / "Info.plist").read_bytes())
        if info.get("MinimumOSVersion") and float(info["MinimumOSVersion"].split(".")[0]) < 15:
            print("warning: target app supports older iOS versions; PhiMod currently targets iOS 15+", file=sys.stderr)

        destination = app / "Frameworks" / "PhiMod.framework"
        if destination.exists():
            shutil.rmtree(destination)
        shutil.copytree(args.framework, destination, symlinks=True)

        unity = app / "Frameworks" / "UnityFramework.framework" / "UnityFramework"
        if not unity.is_file():
            raise RuntimeError(f"missing UnityFramework executable: {unity}")
        subprocess.run([sys.executable, str(tools / "inject_load_dylib.py"), str(unity), DEPENDENCY, "--no-backup"], check=True)
        if b"PMJudgeHook-v1" in (destination / "PhiMod").read_bytes():
            subprocess.run([sys.executable, str(tools / "patch_judge_windows.py"), str(unity), "--no-backup"], check=True)
        if b"PMGameplay-v2" in (destination / "PhiMod").read_bytes():
            subprocess.run([sys.executable, str(tools / "patch_gameplay_hooks.py"), str(unity), "--no-backup"], check=True)
        strip_signatures(app)
        zip_tree(stage, args.output)

    print(f"Unsigned IPA created: {args.output}")
    print("It must be recursively re-signed before installation on a normal device.")

if __name__ == "__main__":
    main()
