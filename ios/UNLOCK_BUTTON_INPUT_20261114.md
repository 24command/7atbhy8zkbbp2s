# Unlock details input and native polygon (2026-11-14)

## Scope
Follow-up to a9980b0: the device still did not react to the details button; no new device log was supplied. Fix both weak paths without touching chart rendering, judgement or hooks.

## Native appearance and input
- Render the body with the game's `Lean.Gui.LeanPolygon`, not a rectangular Image or cloned Start hierarchy. Use `Phigros.UI.MsgBox.InverseSlope` and normalized quad anchors. Filled polygons require negative Thickness; the 4.0.3 implementation treats zero as an empty body. Caption remains `查看解锁条件`.
- Keep the existing native Button handler. Add a narrowly scoped Unity touch fallback only while this locked-song button is visible. Convert the real touch position through the button's actual canvas/camera and RectTransform; hit-test the same slanted quad, not its bounding rectangle.
- Require a single touch beginning and ending inside, no drag beyond slop, and unchanged song/difficulty. Cancel on multitouch, cancelled touches, hiding/navigation, or media presentation. Existing native MsgBox dialogs block the fallback. Deduplicate native/fallback activations.
- Do not use SongSelector.isMoving as a blanket click veto; actual drag distance and selection identity decide whether the touch is a tap.

## Native dialog lifecycle
- Create and show the original PhigrosUI MsgBox first; root its returned UniTask while it is active.
- Add the vertical ScrollRect after the native box is showing, with a canvas layout pass before measuring text height.
- If optional scroll setup fails, restore the stock content and retain the visible original dialog instead of cancelling it. Critical Show errors/timeouts request the game's stock ShowOkMessageBox, with diagnostic messages.
- Handle quick closing and failed-show timeouts so a stale popup handle cannot permanently suppress further clicks.

## Checks and device test
Local source checks, the executable polygon/tap tests (including every integer point in a 420x64 quad), and 4.0.3 metadata checks pass: 202 contracts, 72 hooks, 764 source lookups, 6 negative fixtures. Apple compilation is checked through Actions; local tests cannot establish real-device acceptance.

Test: select a locked difficulty with long conditions; tap the button once; scroll and close the native message box; reopen it; swipe across the button and change difficulties without accidental dialogs.
Relevant log prefixes: `Unlock details v3`, `touch began inside native polygon`, `activate: source=`, `native Show dispatched`, `native scroll ready`. If still unresponsive, capture these and any `Unlock details input` errors.

No chart/skin reimport, no new hooks. Prior rendering/CPU changes are untouched.
