# Continuation update ? 2026-10-25

## Source changes

- Practice transport now hides the full practice panel after start/resume; during count-in it shows only the countdown digit. Pre-start notes are marked on `ChartNote.isJudged` and `isJudgedForFlick`, their renderers/controllers are hidden, and `NoteMove` is skipped to prevent hit/miss effects. Crossing Holds are clipped and reset safely between repeats.
- Chapter/song import accepts Android chapter format v3 and the previous iOS v1 manifest. Chapter export now writes v3 fields, array-based SHA-256 inventory, official-song references, selections, and Android-style song resources.
- Song conversion/export now emits `conversion.json`, `extras.tsv`, `format.txt`, `source-audio.json`, `audio.source.*`, and preserves `source.rpe.json` / `source.pec` when present.
- RPE/PEC conversion now preserves Android-style note counts/metadata, supports late RPE event bounds, hides `attachUI` lines, uses Android tick rounding for Hold speed, and accepts Android-compatible finite note sizes.
- Added sidecar export for line alpha, rank, UI attachment, texture, control tracks, color/text/decor tracks where source metadata is available.

## Verification

- `test_source_contracts.py`: 44 tests passed.
- `test_gameplay_hooks.py`: 3 tests passed.
- `verify_runtime_contracts.py dump.cs`: 8 contracts plus 3 negative fixtures passed.
- UTF-8/garbled-text scan passed for modified files.

## Remaining validation

Windows cannot run the Apple SDK build. A fresh macOS GitHub build and iPad test are still required. Dependency-chapter unlock-rule remapping and full Android shader/GIF/avatar/hit-audio parity are not claimed complete by this pass.
