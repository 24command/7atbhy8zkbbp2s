# Native tab / unlock details / measured CPU follow-up (2026-11-14)

## Evidence and scope
- The supplied 1,342-byte tab log is the same C8B9449A session from 2026-11-13 23:56:43, not proof of a new failure after the null-Canvas correction. Preserve that correction; do not reintroduce UIKit projection into the native page path.
- The larger log records 300-frame averages: native 2.12 ms, custom 70.19 ms, peak combined 310.82 ms. This is CPU evidence, **not a GPU measurement**. `native` includes nested hooked NoteMove calls.
- Reference: Android v0.1.5-v4 `native/settings.inc` keeps page visibility/navigation separate from its projected overlay. The iOS 4.0.3 `Setting.ChangeTab` implementation selects registered animator/content arrays; it does not hardcode a three-tab limit.

## Changes
- Native MOD page: validate selected index and active hierarchy after native ChangeTab; restore the cloned root CanvasGroup interaction state. Optional preview muting cannot roll back a successfully constructed page. New diagnostic marker: `MOD settings revision 20261114-b: native tab=3 active; no Canvas projection`.
- Long unlock requirements: replace the entire cloned Start/Select hierarchy with an independent native Button, clean light Image and caption `查看解锁条件`. Use the actual tip rectangle, fixed readable button height, an explicit raycast target and independent CanvasGroup. No stretched/cropped Start sprite or copied native callbacks. Existing PhigrosUI.CreateMessageBox remains the dialog, with a masked vertical ScrollRect for long text.
- Rendering CPU: cache compiled visual-event tracks and exact successful IL2CPP type/ABI validations; resolve distance-control tracks once per line rather than per future note; cache fake-note type/X; reject only authored alpha/visibility-ineligible non-due notes before expensive recovery work. No arbitrary future-time cutoff, resolution reduction or new shader culling.
- Preserve due-note judgement, negative visibility, stopped/reverse speed, parent transforms, hold geometry, rewind and shader/video output. Periodic heartbeat I/O slows to every four seconds after initial calls; important errors and miss diagnostics remain.
- CPU log now splits `fx`, `modes`, `recovery`, `visuals` every 300 frames to identify remaining cost without per-note logging.

## Verification and device checklist
- Focused source/metadata checks and portable RPE timing, visibility, skew, text, rewind/cache tests run locally. The arm64 Apple build is validated by GitHub Actions, not by the Windows compiler.
- Check MOD from all original tabs and return; open long lock details, scroll, close, and switch to an unlocked difficulty.
- Replay the same long custom chart; copy both CPU profile lines after 300 frames. Compare actual device FPS and verify stopped notes/hidden notes/storyboard lines. No device FPS improvement is claimed without this test.
- Hook count stays 72; existing charts, chapters and skins need no reimport. Use a newly built complete framework/artifact, not an older similarly named ZIP.
