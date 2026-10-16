# PhiMod iOS bootstrap

This directory contains the overlay, IL2CPP bridge, portable gameplay rules,
and a new offline entry-hook backend with song shortcuts / a Settings MOD tab.
The newer source has not yet been compiled with the Apple SDK or device-tested.
Downloaded framework6 only contains the preceding judge-hotfix version.
Read [GAMEPLAY_UI_PORT.md](GAMEPLAY_UI_PORT.md) for exact capability and safety
boundaries. Noise/Unified are unavailable, not silently simulated by AutoPlay.

## What is modified

The source Payload is never modified. Inside a temporary staging copy, the
packaging helper adds one `LC_LOAD_DYLIB` dependency:

```text
@loader_path/../PhiMod.framework/PhiMod
```

For frameworks containing `PMJudgeHook-v1`, packaging also invokes
`tools/patch_judge_windows.py`: three exact, UUID-gated ARM64 stores in
ProgressControl.Update branch to RX stubs in unused TEXT padding. A new
zero-fill section in unused DATA VM padding holds the desired values and
latest engine baseline. No runtime code-page writes or external hook library
are used. With the override disabled the original stores execute unchanged.
Rebuild AND repackage; replacing only the framework in an older IPA is not enough.


For frameworks containing `PMGameplay-v1`, packaging also installs 37 exact
entry gates with `patch_gameplay_hooks.py`. These call PhiMod through RW callback
slots or transparently execute the original prologue when unregistered. The
framework validates the full protocol/metadata/stubs before publishing callbacks.

It also embeds `PhiMod.framework` under `Phigros.app/Frameworks`. The framework's
constructor installs the overlay after the application becomes active.

## Build without a local Mac

The framework must be compiled with an Apple iOS SDK. The repository-root GitHub
Actions workflow `.github/workflows/build-ios.yml` can build the arm64 framework
on a macOS runner. It uploads `PhiMod.framework` as an artifact. Do not upload the
game IPA to CI; only the small, original PhiMod source needs to be in the repo.

On a Mac the equivalent command is:

```bash
bash ios/build_unsigned.sh
```

## Make the unsigned IPA on Windows

After obtaining the compiled framework:

```powershell
python ios\tools\package_unsigned_ipa.py `
  --source "G:\games.Pigeon.Phigros_4.0.1_und3fined" `
  --framework "C:\path\to\PhiMod.framework" `
  --output "G:\Phigros_4.0.1_PhiMod_unsigned.ipa"
```

The source app is copied to a temporary staging directory; it is not patched in
place. The output is deliberately unsigned.

## Signing requirements

Simply zipping `Payload` is not enough for a normal, non-jailbroken iOS device.
Changing a Mach-O load command invalidates its code signature, and adding a
framework introduces another nested code object. A signing tool must:

1. sign `PhiMod.framework/PhiMod`;
2. re-sign `UnityFramework.framework` after its load command changes;
3. sign any other changed nested code;
4. sign the outer `Phigros.app` last with a compatible provisioning profile and
   entitlements;
5. package the signed `Payload` as an IPA.

TrollStore is useful for early functional testing, but a TrollStore installation
does not prove that an ordinary certificate/provisioning-profile installation
will work. Test both paths separately.

## IDA / Il2CppDumper

The iOS metadata-31 dump is at:

```text
G:\games.Pigeon.Phigros_4.0.1_und3fined\Il2CppDumperOutput_v6746
```

Import `ida_with_struct_py3.py` from Il2CppDumper v6.7.46 into the IDA database
opened on `UnityFramework`, and select this output directory's `script.json` and
`il2cpp.h` when requested. Save a backup of the IDA database before importing.

## Portable core tests

```bash
bash ios/tests/run_core_tests.sh
```

The macOS workflow runs these host tests before building the arm64 framework.
Host tests do not validate UIKit, game hooks, signing, or device behavior.
