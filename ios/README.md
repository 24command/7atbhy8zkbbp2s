# PhiMod iOS - device fixes + native gameplay modes

Source revision: **2026-10-18**, protocol **PMGameplay-v2 / 61 hooks**,
framework version **0.2.0 (61)**. This revision is newer than framework13.
**It must be rebuilt with the Apple iOS SDK before creating a new test IPA.**

Start with [HP_PRACTICE_20261018.md](HP_PRACTICE_20261018.md) for this revision, [DEVICE_FIX_20261017.md](DEVICE_FIX_20261017.md) for the Chinese
build/test checklist, and [GAMEPLAY_UI_PORT.md](GAMEPLAY_UI_PORT.md) for scope
and safety boundaries. Portable C++ cores were rebuilt and run with local MSVC. Source-contract, metadata, judge-patch, and real-image hook-gate checks have passed on Windows. This revision still needs the macOS Apple SDK build and real-device verification.

## Changes

- Practice result coroutine presentation and navigation-only recovery.
- HP startup no longer adds optional visual assets to the native chart-loading gate. Native SecretChallengeLifeBar and HPDisplay are instantiated asynchronously after chart readiness, with independent resource diagnostics.
- HP failure delay/transition and native floor-buffer capacity repair.
- Real Button.OnPointerClick / OnSubmit paths for the MOD tab and song shortcuts.
- Noise masks and touch blocking; No Noise; unified Tap/Drag/Hold/Flick conversion.
- Noise Hold grace and AutoPlay Hold effect interval, following Android logic.
- Range practice: draggable timeline, paused live note preview, range markers, pause/resume/repeat, looping, three-second count-in, and live rate controls. Crossing Holds are trimmed from restored source data on each rewind.
- The in-game MOD editor now has categorized mode/practice/judgment/noise/UI pages, with a separate HP rules/visuals page.
- Practice controls now mirror Android’s industrial and white panels: three draggable handles, editable timestamps, countdown toggle, rate/flow controls and paused preview.
- Added local library/chapter management with the iOS document picker, ZIP/PEZ safety checks, native v3/PEC/RPE conversion, cover replacement, chapter ordering, multi difficulty groups and original chapter browsing.
- Added Android-style RPE line/note visuals: easing, parent lines, floor integration, custom sizes/alpha, line textures, extended text and fake notes.
- AddressableAudioSource.Update rate mapping and nested judge-window scaling follow the Android playback-rate path.
- Android's JudgeControl.Update floor-buffer capacity guard is restored before the native judge update.
- Save/RKS/reward/unlock protection covers custom judge, AutoPlay, No Noise, full-screen judgment, Accuracy, Unified, range practice, and changed playback rate. HP/AP/FC alone follow the previously requested save policy.

Video playback, shader uniform execution, custom skins and exact pixel-for-pixel Android settings presentation still require additional device-specific work. Library import/export and RPE conversion are implemented in source and require Apple SDK/device validation. The MOD tab
uses a native Unity navigation button with a UIKit editor. Do not call this a
fully verified Android port or a verified normal-signing release.

## Build on GitHub Actions (no local Mac required)

Upload the contents of the clean source package into the repository root, with
both `ios/` and `.github/workflows/build-ios.yml` present. Do not upload game
binaries, dump.cs, metadata, IDA databases or the extracted IPA.

Run the existing `Build PhiMod iOS framework` workflow. The workflow tests the
portable cores, generated ARM64 gateways and source contracts, then builds the
arm64 framework on macOS and checks its protocol markers. Download the artifact
and unpack until `PhiMod.framework/PhiMod` is present.

Equivalent on a Mac:

```bash
bash ios/build_unsigned.sh
```

## Package locally on Windows

Use the NEW framework with the NEW packaging tools and the ORIGINAL extracted
Payload. Merely replacing PhiMod.framework inside an older patched IPA is not
sufficient: the Unity entry gates changed from 37 to 61 and from v1 to v2.
The helper rejects stale frameworks before copying the game. The current source revision requires the 61-hook framework.

```powershell
python ios\tools\package_unsigned_ipa.py `
  --source "G:\games.Pigeon.Phigros_4.0.1_und3fined" `
  --framework "C:\path\to\PhiMod.framework" `
  --output "G:\Phigros_4.0.1_PhiMod_devicefix_unsigned.ipa"
```

The source app is not modified. In a temporary copy, the helper embeds
PhiMod.framework, adds the load dependency to UnityFramework, installs the
UUID/prologue-gated judge patch and 61 gameplay gateways, and removes old
signature data. No runtime executable-page writes or external hook library are
used. Final output is deliberately unsigned.

Signing and installation on an ordinary non-jailbroken device are separate
acceptance steps. A TrollStore test alone is not evidence of normal-signing
compatibility. Keep signing credentials and provisioning files out of the repo.

## Local verification

```bash
bash ios/tests/run_core_tests.sh
python ios/tests/test_source_contracts.py
python ios/tests/test_judge_patch.py
python ios/tests/test_gameplay_hooks.py
python ios/tools/verify_runtime_contracts.py /path/to/dump.cs
python ios/tools/verify_gameplay_contracts.py /path/to/dump.cs
```

The emulator tests require `unicorn==2.1.4`. They also accept `--unity` to audit
the local original UnityFramework without altering it. Dump verification checks
metadata/ABI and source lookup contracts, not in-game execution.
