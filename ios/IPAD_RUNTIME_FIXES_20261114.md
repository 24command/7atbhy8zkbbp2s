# Native MOD tab, hit effects, and iPad CPU/GPU overhead - 2026-11-14

## Confirmed MOD failure
Device diagnostics show native page creation succeeded, followed by
`Null call: get_worldCamera`. Optional UIKit anchor projection threw and the
press handler rolled back the correctly created native page. Native MOD no
longer calls that projection; advanced UIKit projection tolerates missing Text
or Canvas. Native page factories, arrays, and ChangeTab are unchanged.

## Hit effect first frame and size
The Instantiate hook executes BEFORE the game's caller sets the returned effect's
position/scale. The separate custom SpriteRenderer used to be visible at origin
until a later Update copied its position, and never inherited native scale.
It is now created disabled, then positioned/scaled after native NoteMove or
NoteUpdateManager returns, before publishing frame zero. Native world scale is
multiplied by hitFxScale, matching Android's parent/child scale composition.
The completed effect is anchored to the emission point (Phira behavior), owns its
lifetime, and removes the hidden stock effect. No per-frame position chasing.
One diagnostic line records the resulting scale for device comparisons.

## Performance changes without reducing visual quality
- Cache Assembly-CSharp class lookups instead of rescanning assemblies per note.
- Use stack storage for up to 16 runtime_invoke arguments; retain heap fallback,
  checked metadata access, managed exception reporting and the same ABI.
- Skip skin post-processing when no skin is active.
- Full GLSL compilation classifies generated MSL discard operations. Non-discard
  passes skip the redundant full-screen preservation blit and use DontCare load.
  Discard shaders retain the original copy/load behavior. Resolution, pass order,
  sampling, scope and shader uniforms are unchanged.
- Prepare videos near their start, rather than allocating all future decoders at
  chart entry. Keep the existing video size/aspect/clock and hardware playback.
  Cache prepared duration, binary-search sorted tracks, avoid unchanged color
  writes and skip inactive players. Retry unavailable duration; reentry seeks.
  Release completed decoder/textures after two seconds, retaining timing metadata
  for backwards practice seeks; long charts no longer retain every past video.
- Every 300 custom-chart frames, diagnostics report native/custom CPU times and
  peak CPU time. These measurements exclude GPU and are not FPS guarantees.

## Safety and validation
No change to note visibility, source geometry, line displacement, lifetime
scheduling or judgement. No hook additions: 72. No chart/resource-pack reimport.
Portable extracted-production tests compare 50,000 old/new video samples and
runtime_invoke argument transport for 0/3/16/17 arguments. Metadata and source
regressions check MOD null-Canvas, effect publication ordering, native scale,
video states, shader preservation, and existing note/hold behavior. Actions must
build the actual arm64 framework and run full shader/discard fixtures.
Device acceptance still required: MOD open/back/reopen; first effect at note
position; note-size and hitFxScale changes; long video/shader chart playback.
If still slow, send new diagnostics containing `RPE CPU profile`; complex GPU
shaders can still exceed the iPad6 budget, and no guaranteed FPS is claimed.
