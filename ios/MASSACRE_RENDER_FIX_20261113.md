# MassacrE stopped-scroll performance rendering (2026-11-13)

Compared supplied original/converted chart and actual/reference videos. Original and conversion both have22lines and1630real notes; all note type/source time/X/side identities match. No fake notes, shader events, or non-positive visibleTime in this chart. Line6 stops its floor integral from50.25 to60.6seconds while moving vertically as far as-4500source units. Notes judged at60.6seconds and later are used for earlier visual performances. Audio alignment estimates actual=reference+0.81seconds; paired actual10/reference9.19frames show empty vs populated note display.

The old source recovery only examined the next8seconds and discarded notes more than30local world units away from the judge line. This wrongly discards valid on-screen notes when the line itself is far outside the screen. Android scheduleRpeNotes/rpeVisualNear instead transforms source geometry into world position and uses viewport bounds, with a2second near-judgement scheduling fallback. Phira renders the source geometry after its line transform too.

Changes:
- Capture immutable native note identity/index/time/type/X once per chart binding, then use source geometry and actual line transform for recovery. No8second or local-distance cutoff. Preserve judgement status and native source-side index validation.
- Cache each line transform basis and source floor for the pass; only build the live-controller lookup when a candidate qualifies. Include Hold head/tail viewport crossings, below notes, control curves, signed line alpha, note alpha/visibleTime, cover and incline.
- Fake-note allocation uses the same spatial gate, removing its fixed8second horizon. Existing cached sprites remain reusable; no-cover post-hit fake lifetime preserved. Real notes remain native judgement controllers.
- Respect native post-hit fade for non-Holds instead of overwriting it with source opacity; source pre-hit opacity and active Hold geometry stay supported.

Regression: portable geometry tests for large offset cancellation, rotation/below, offscreen rejection and crossing Holds; source contracts ensure no fixed time/local-distance cutoff and real/fake share the gate. Verify source identity/cache teardown including practice chart rebinding. iOS build via Actions. No device validation or FPS guarantee.

Install updated framework/IPA and retest the50..61second passage, including practice seek/countdown. This fix is runtime-only and the supplied converted MassacrE chart retains all necessary data: no reimport required. The earlier Algebra visibleTime conversion fix still requires reimport for packages that already lost those values. Hook ABI/count remains72.
