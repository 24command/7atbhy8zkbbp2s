# MOD settings and unlock dialog follow-up (2026-11-14)

Runtime marker: `settings-layout-v5-20261114`. Hook count remains 72; no chart, chapter or skin reimport is required.

## Changes

- Mount the MOD frame under the strict common RectTransform ancestor of all three native settings pages. Disable copied template animators before adding native controls, so a hidden Gameplay template cannot keep the new frame hidden. Keep the frame beneath native navigation siblings.
- Use the native wide settings viewport and native item factories. Expand rows across the page instead of reserving Gameplay's preview column.
- Size the original unlock MsgBox to the usable canvas/safe area. Place an independently scrolling, left-aligned text body beside the original Text rather than reparenting the Text used by native layout. Preserve native title and confirmation-button layering.
- Own SongSelector input while the dialog is open: suppress native selector Update and background buttons, clear gesture/inertia, permit dialog controls, then restore the previous input state after touch release. Scene exit and optional-scroll failures have cleanup paths.

## Verification

Focused source checks, portable layout/modal/common-parent regressions and the 4.0.3 metadata contract checks passed locally. Full Apple arm64 build and the complete CI suite are checked on the submitted commit; device acceptance is still required.

On device: open MOD from Gameplay, Audio and Other; return to each stock tab and use Back. Open long unlock conditions, scroll to the end and confirm the song list stays stationary; close and verify selection resumes. Repeat after switching scenes and after screen-size changes if supported.
