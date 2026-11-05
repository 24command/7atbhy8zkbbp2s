# Current target ? 2026-10-31

Supplied iOS Phigros **4.0.3**, **68 hooks**, build marker `PMGameplay-contract-v2-68-ios403`. See `ADAPTATION_4.0.3.md`. Earlier entries below are historical and do not describe the current target.

# Latest content fix - 2026-10-22

Current source now requires **63 hooks / build 63**. See [CONTENT_FIX_20261022.md](CONTENT_FIX_20261022.md) for the framework16 device report fixes and validation limits. Rebuild and repackage; previous 61-hook binaries are incompatible with this packager.

# Latest update - 2026-10-20

See [MIGRATION_AUDIT_20261020.md](MIGRATION_AUDIT_20261020.md) for the Android comparison, startup fix, UI changes, remaining gaps and test checklist. Current work is source-only; requires a fresh Apple SDK build and device verification. The framework14 IPA does not contain these fixes.

# Current migration status - 2026-10-18

Current source: **PMGameplay-v2 / 61 hooks, framework 0.2.0 (61)**. New sources are in G:\Phimod-ios\ios. See [HP_PRACTICE_20261018.md](HP_PRACTICE_20261018.md) for implementation details and testing.

HP startup now leaves the game's LevelStartInfo.levelMods untouched. IDA confirmed LevelControl.Start waits for levelModCount >= levelMods.Count before chart loading. MOD-only native HP visuals are requested asynchronously after chartLoaded, with independent completion/error reporting and cleanup. The Android floor-array capacity guard is also restored. These source changes require device confirmation; the reported freeze is not yet proven resolved.

Range practice has Android-style industrial and white touch panels with a draggable timeline and live paused note preview, start/end markers, seek, pause/resume/repeat, whole-song playback, looping, optional three-second count-in, and live rate controls. Rewinding restores original chart timing and handles crossing Holds; counters, HP state, note caches and noise blocks reset. AudioSource pitch is read back; requested rate can differ from effective rate. The in-game MOD settings editor and floating mode page have been reorganized into categories, retaining unsaved inputs while switching pages.

Verification: 21 source-contract tests; 184 dump metadata / 61 hook contracts; source lookup and negative-fixture checks; real-image ARM64 gateway emulation; judge-patch simulation. Four portable C++ test programs were rebuilt and passed using MSVC on Windows. HP/practice/preview C++ syntax also passed against a local Runtime shim. This does **not** substitute for an Apple SDK Objective-C++ build or device execution. Neither has run for this revision.

Local chart library/chapter import/export, native v3/PEC/RPE conversion, multi-difficulty grouping, system file picker, RPE line/note geometry, line textures, extended text and fake-note visuals are now implemented in source. Video playback, shader uniform execution, skins and exact Android asset styling remain for a later pass. Android-specific slanted drawing, covers and animations are not pixel-identical on UIKit.

Save protection follows the requested scope: judge, AutoPlay, clear original noise, full-screen judgment, Accuracy, Unified, plus range practice and changed rate. HP/noise/AP/FC alone retain native score behavior. TrollStore and ordinary signing remain separate device acceptance paths.


# Continuation update ? 2026-10-24

This pass continues from the existing source state; it does not replace the earlier chapter-cover, practice, ACC/no-combo, or PEC/RPE changes.

Implemented source-side additions:

- Chapter/song cover editing now has a UIKit crop-and-rotate controller. Chapter covers use the chapter aspect ratio; song covers use a wide aspect ratio. The saved result is normalized before being written to the local asset folder.
- The local chart library has multi-select mode, select-all, batch export through the iOS share sheet, and batch deletion into the existing trash directory.
- Resource-pack import now validates ZIP/PEZ size, extracts safely through the existing archive guard, checks the required `click.png`, `drag.png`, `flick.png`, and `hold.png` entries, and copies the validated archive to `Documents/PhiMod/resources`. It deliberately does not pretend to apply Android skin runtime behavior.
- The large-image path is opt-in through `dynamicLargeTextures`; it raises the cover-image cap to 4096 px and 64 MiB encoded input. It is not a complete Android `LargeLineTextures`/skin atlas implementation.
- The settings page contains explicit, disabled entries for Android-only adapters that are still absent: skins/resource-pack application, unlock rules/animation, mainline unlock, shortcut drawer ordering, RPE video, RPE shader execution, and legacy chart effects. These entries are intentionally non-interactive until their IL2CPP/runtime adapters exist.

Validation after this pass:

- 52 Python source/protocol tests pass; 4 binary tests are skipped when no local Apple/Unity fixture is requested.
- MSVC portable tests pass: gameplay core, judge core, flow core, and mode/noise/Hold checks.
- Practice/HP/preview syntax checks pass against the local runtime shim; the existing HP warning remains non-fatal.
- The real local UnityFramework reference-setter test passes.
- No Apple SDK build or iPad execution was performed on Windows. The new Objective-C++ files still require the normal macOS GitHub workflow before an IPA can be produced.

Remaining Android parity gaps are now explicit rather than hidden behind enabled switches: actual skin atlas/audio application, unlock rule evaluation and animation/video playback, shortcut drawer persistence/order, RPE VideoPlayer/RenderTexture timing, shader compilation/uniform updates, dynamic line-texture atlases, and legacy chart-specific effects.


## Runtime adapter pass (2026-10-24)

The source now contains UI-neutral runtime adapters for bounded resource-pack installation and note sprite replacement, RPE `extra.json` video playback through Unity VideoPlayer/RenderTexture, mainline catalog unlock clearing, and local unlock-rule/MP4 animation preparation. These are source-level changes and require a fresh framework build plus device testing. Resource-pack audio/hit-FX, avatar rendering, Metal-safe RPE shaders, and GIF unlock playback are still not complete. Verified-marker legacy Yukifuri display replacement is source-wired but still needs device verification.
