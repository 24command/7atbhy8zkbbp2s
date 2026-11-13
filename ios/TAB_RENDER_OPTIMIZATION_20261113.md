# MOD tab input and RPE scheduling - 2026-11-13

## Scope
Fix the reported non-responsive native MOD tab and reduce CPU/allocation overhead
in long/dense RPE charts. Preserve the prior MassacrE spatial visibility correction.
No new hook (72), no conversion change, no chart reimport required.

## Native MOD tab
The old clone relied on the third tab's animated/masked decorative Graphic for
input. The fourth tab now has a dedicated transparent Unity Image/Button hit
surface, independent of those animation bindings and inherited CanvasGroups.
The owning Setting's leave state still controls interactivity; inactive hierarchy
still disables input. Native SettingTabController.Refresh positions the tab.
Native SettingItemsManager factories/layout and ChangeTab remain the page path.
Click/page-creation messages enter diagnostics; creation errors display a dialog
instead of silently consuming the click. Without device logs, the precise failing
prefab state is not proven; the explicit hit surface addresses that input path,
and the dialog distinguishes a remaining construction failure.

## Rendering
- Follow Android's immutable candidate identities and Phira's cached traversal.
- Cache numeric source-note visibility/geometry inputs at binding, not per frame.
- Cache line alpha/cover/control flags/incline/perspective once per line/pass.
- Skip redundant recovery geometry for already-visible native controllers.
- Sort real/fake lifetimes and binary-seek past finished notes. Backwards practice
  seeking works; this is not a future-time cutoff. Distant, reversed and stopped
  scroll performances still use transformed world-space visibility.
- Check appended controllers after CreateNote, avoiding quadratic full-list scans
  for batches of newly visible notes; retain a fallback for a native reuse path.
- Reuse large shader uniform buffers per in-flight scratch slot, only after GPU
  completion. Create texture descriptors on resize/allocation rather than per
  frame. No resolution/frame-rate reduction; shader order and discard stay intact.

## Validation and device checklist
Source/metadata checks and portable C++ visibility/lifetime regressions are run
locally. Actual Apple arm64 compile is validated by Actions, not Windows.
No device FPS or visual acceptance claim is made from source checks.
1. Enter MOD from each native tab, scroll/toggle, go back, reopen.
2. Compare MassacrE's distant performances, and long shader/storyboard charts.
3. Seek practice backward/forward; verify fake notes disappear/reappear correctly.
4. If MOD still fails, copy the new MOD settings dialog and diagnostics.
Native controller rendering and GPU shader load still impose costs; this removes
identified redundant work rather than guaranteeing constant FPS on all charts.
