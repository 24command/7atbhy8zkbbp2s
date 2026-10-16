# Current migration status - 2026-10-17

**Current source: PMGameplay-v2 / 54 hooks, framework 0.2.0 (54).**
Downloaded framework7 and the previously packaged framework7 IPA DO NOT contain
this revision. No new framework or game IPA has been built locally for it.

The five reported device issues now have source fixes: practice result flow,
HP-zero transition, native HP effects, settings MOD button clicks, song shortcut
clicks. New source also connects Noise / No Noise / Unified and Hold tuning.

Portable core tests, ARM64 emulator tests against the actual original binary,
metadata/source contract verification and partial stub-only Objective-C++
compilation have passed. There has been **no Apple SDK build or device test of
this revision**. See [DEVICE_FIX_20261017.md](DEVICE_FIX_20261017.md).

Still not ported: custom song import/library/chapter/navigation workflows,
extended RPE transforms/decoration/video/shaders, custom skins/avatars/hitsounds,
and the rest of the Android resource ecosystem. The settings editor uses UIKit;
it is not a pixel-identical Unity reconstruction of the Android editor.

Assisted sessions must not alter best scores, RKS, rewards or unlocks. This is a
safety requirement, not a promise proven by the host tests. Back up saves and
verify persistence isolation on device. Non-jailbroken normal signing remains
unverified separately from TrollStore.
