# Current migration status - 2026-10-18

Current source: **PMGameplay-v2 / 61 hooks, framework 0.2.0 (61)**. New sources are in G:\Phimod-ios\ios. See [HP_PRACTICE_20261018.md](HP_PRACTICE_20261018.md) for implementation details and testing.

HP startup now leaves the game's LevelStartInfo.levelMods untouched. IDA confirmed LevelControl.Start waits for levelModCount >= levelMods.Count before chart loading. MOD-only native HP visuals are requested asynchronously after chartLoaded, with independent completion/error reporting and cleanup. The Android floor-array capacity guard is also restored. These source changes require device confirmation; the reported freeze is not yet proven resolved.

Range practice has Android-style industrial and white touch panels with a draggable timeline and live paused note preview, start/end markers, seek, pause/resume/repeat, whole-song playback, looping, optional three-second count-in, and live rate controls. Rewinding restores original chart timing and handles crossing Holds; counters, HP state, note caches and noise blocks reset. AudioSource pitch is read back; requested rate can differ from effective rate. The in-game MOD settings editor and floating mode page have been reorganized into categories, retaining unsaved inputs while switching pages.

Verification: 21 source-contract tests; 184 dump metadata / 61 hook contracts; source lookup and negative-fixture checks; real-image ARM64 gateway emulation; judge-patch simulation. Four portable C++ test programs were rebuilt and passed using MSVC on Windows. HP/practice/preview C++ syntax also passed against a local Runtime shim. This does **not** substitute for an Apple SDK Objective-C++ build or device execution. Neither has run for this revision.

Local chart library/chapter import/export, native v3/PEC/RPE conversion, multi-difficulty grouping, system file picker, RPE line/note geometry, line textures, extended text and fake-note visuals are now implemented in source. Video playback, shader uniform execution, skins and exact Android asset styling remain for a later pass. Android-specific slanted drawing, covers and animations are not pixel-identical on UIKit.

Save protection follows the requested scope: judge, AutoPlay, clear original noise, full-screen judgment, Accuracy, Unified, plus range practice and changed rate. HP/noise/AP/FC alone retain native score behavior. TrollStore and ordinary signing remain separate device acceptance paths.
