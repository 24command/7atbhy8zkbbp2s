# Official tracks in Android/iOS chapter packages

Android v3 uses root `officialSongs: [{"id":"nativeSongID"}]`. Root `songs` describes custom charts only, and may be empty for an official-only chapter. `chapter.songs` and `dependencyChapters[].songs` contain ordered IDs. Official IDs are preserved; imported custom IDs are remapped. No official music/chart resources are bundled.

`officialMoves` is a LOCAL library placement map, not a chapter.json field. Android ChapterBundle.importBundle does not import that map: importing a chapter adds references, without removing tracks from their original chapters. iOS follows the same behavior. Moving through the editor records officialMoves locally; exporting writes the reference and chapter ordering, not a destructive move instruction for the recipient.

2026-11-13 audit: existing iOS reference export, ordering/remapping, and reference-only import were already present. Tightened validation to match Android: officialSongs must be an array of object IDs; reject duplicate IDs, custom pm_ IDs, more than2000 references, or IDs absent from the stock chapter catalogue. Use OfficialPlacement.entries-compatible chapter entries, not all internal SongBase records. Export runs the same validation. Existing fields/schema unchanged.

Foundation regressions cover optional/empty references, ordered valid references, malformed/null/duplicate/custom/missing/oversized references, and compact JSON roundtrip with official-only main/dependency chapters. Actual Android/device import retest remains separate from CI.
