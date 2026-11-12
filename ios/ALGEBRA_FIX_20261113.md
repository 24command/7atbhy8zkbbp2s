# Algebra rendering fix (2026-11-13)

## Scope and confirmed evidence
- Compared both supplied 2x-speed videos. Audio-envelope alignment peaks at 0.96875 correlation: expected video time = device video time + 1.43 seconds. Compared paired frames at device times 0, 5, 12, 20, 30, 40, 50, 60, 70, 80, 90, 100 and 110 seconds.
- Original and converted chart each contain 282 lines and 2,890 notes, including 990 fake notes. effects.tsv is empty; this case does not implicate Shader rendering.
- Original visibleTime values include -60 (57), -10 (720), -1 (10), and 0 (47): 834 real notes total. All 834 became pmVisible=999999 in the exported chart. These judgement notes should not expose their approach graphics over the fake-note/storyboard artwork. This explains the regular taps over circular artwork and many unwanted notes remaining on screen.
- Signed line-alpha metadata is absent from this older package, but the original has no negative line-alpha events: this is NOT a cause in Algebra.
- Sampled all 282 converted line poses every 0.25 seconds over 265 seconds against current source-event evaluation. Maximum error: 0.401 source X units, 0.270 source Y units, 0.059 degrees; within adaptive subdivision tolerances. This verifies conversion consistency, not every device renderer frame. No speculative parent-transform rewrite.
- Fake renderers always selected normal sprites, although simultaneous fake notes are highlighted in the reference. The renderer now groups source float times once, uses the native chordSupport option and highlighted sprites, then applies the existing skin replacement path. Fake notes remain outside native scoring.

## Changes and regression coverage
- PMChartConvert.mm preserves explicitly authored zero/negative visibleTime. Missing values retain the existing default. No judgement-window or hit-lifetime change.
- PMContentRuntime.mm selects chord sprites for fake notes. No new hook gates.
- PMContentHostTest.mm tests signed visibleTime on both sides, real and fake notes, reveal boundaries, alpha=0, missing-field defaults, and preservation of scoring notes in PMNativeChart.
- Local metadata/source checks: 202 metadata / 72 hooks / 713 source lookups / 6 negative fixtures; 46 source-contract tests; 2 resume-integrity tests passed.

## Device retest
Rebuild/install the framework, then import the ORIGINAL Algebra.zip again. The exported chart.json has irreversibly overwritten the lead times; importing that chart.json again cannot infer the original values. Back up scores/library before replacing the old entry if needed. Compare the arithmetic columns, circular-note artwork, binary section, and simultaneous fake-note outlines. Device validation remains outstanding.

## Continuation note
User asks to examine both videos and both chart archives efficiently, fix demonstrated rendering discrepancies, preserve working behavior, and commit/push by default. Do not repeat the full source inventory. Analysis artifacts and paired frames are at F:/phimod-algebra-audit; originals/backups are in this audit folder. Do not mistake unrelated dirty checkout files for this task's edits.
