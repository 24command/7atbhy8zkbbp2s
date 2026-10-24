# Continuation status ? October 24, 2026

## Completed in this continuation

- Added an iOS crop/rotate editor for song and chapter covers. The editor uses a fixed aspect window, pinch zoom, pan, and 90? rotation before saving.
- Added multi-select library management: select all, batch export through the iOS share sheet, and batch delete with Trash rollback semantics.
- Added an explicit resource-pack archive picker. It copies packs into `Documents/PhiMod/resources`; it does not claim to apply Android skin/runtime behavior.
- Added a guarded large-image path. `dynamicLargeTextures` is an opt-in setting for image loading, capped at 4096 px / 64 MiB to avoid unbounded memory usage.
- Added disabled, explicit entries for Android-only work that is not yet wired to Unity: skins, unlock animations/rules, mainline unlock, shortcut drawer, RPE video, RPE shader execution, and legacy chart effects.
- Kept the earlier fixes unchanged: chapter-cover sprite fallback, practice entry suppression and pre-start Miss accounting, practice release-to-activate transport buttons, separated live ACC/no-combo settings, and the existing PEC/RPE converter.

## Still not implemented

The disabled entries above are UI declarations only. They do not alter game state. Full Android parity still requires separate Unity/IL2CPP adapters for resource-pack atlas/audio application, unlock rule evaluation and animation/video playback, runtime shader compilation/uniform updates, VideoPlayer/RenderTexture timing, dynamic line-texture atlases, and legacy chart-specific effects.

## Verification

The source-contract suite, MSVC portable core tests, practice/HP syntax shim, and real UnityFramework reference-setter tests pass on Windows. An Apple SDK build and iPad execution are still required before treating the new UIKit files as device-verified.

## Runtime adapter pass - 2026-10-24 (source only)

This pass is intentionally UI-neutral and adds runtime paths for the previously placeholder features:

- Resource packs now use a bounded archive extraction path, install a normalized active pack under `Documents/PhiMod/resources`, persist `active.txt`, and enable the next-level texture adapter. Tap/Drag/Flick/Hold sprites, highlight variants, Hold atlas slicing, and chart-time sprite replacement are wired through Unity IL2CPP objects.
- RPE `extra.json` video entries are read from imported chart extensions and played with Unity `VideoPlayer` + `RenderTexture`, clocked from `ProgressControl.nowTime`, with alpha/dim tracks and pause/seek correction.
- Mainline unlock now clears native song/chapter unlock records when the setting is enabled, and the selector card lock mask is removed after the native chapter selector starts.
- A local unlock-rule evaluator now reads custom rule records from the native `GetSongRecord` path; MP4 unlock animations can be prepared as a fullscreen Unity VideoPlayer overlay when a local entity rule passes.

Still deliberately not claimed as complete:

- Resource-pack replacement audio, hit-FX atlas animation, and custom avatar rendering still need dedicated iOS hook points.
- RPE Shader execution is not enabled: the Android implementation intercepts GLES/GLSL, while this target uses Unity's iOS renderer and needs a Metal-safe adapter rather than copied GLES hooks.
- Legacy Yukifuri display replacement is now source-wired for verified `legacy-effect.txt` markers; it still needs device verification and audio-spectrum parity.
- Full GIF unlock playback, avatar rendering, replacement hit audio, and hit-FX atlas animation remain pending.

Validation on Windows: source-contract and gameplay-hook suites pass. Apple SDK compilation and iPad execution are still required; the new Objective-C++ files have not been device-verified.
