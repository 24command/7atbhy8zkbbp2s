# Custom chart / chapter fixes (framework16 report)

Source: G:\Phimod-ios\ios. Protocol: PMGameplay-v2, **63 hooks**, build 63.
Upload the complete updated ios folder, including tools/tests/Core, before building.
The packager now rejects older 61-hook frameworks. Existing IPA/ZIP files are unchanged.

## Evidence and changes

1. logs.txt reports LoadRawTextureData UnityException for both Illustration and
   IllustrationBlur. The code uploaded only width*height*4 bytes to a default
   Texture2D constructor. It now explicitly requests RGBA32 (dump enum value 4),
   with mipmaps disabled. Sprite allocation is checked. A chapter without its own
   cover can use the first contained song's cover.
2. The chart load succeeds, but no subsequent audio preparation or chart-loaded
   state is recorded. Archived LevelControl.Start decompilation calls
   AssetRef.ReleaseAll immediately after parsing the chart. The iOS machine code
   confirms ReleaseAll calls ReleaseResource directly, bypassing the existing
   Release hook. Added the missing ReleaseResource hook, mirroring the Android
   implementation, so custom TextAssets never enter native Addressables handle
   cleanup. Ordinary official assets still use the original function. Duplicate
   release cannot remove a newer dictionary entry for the same key.
3. Hidden chapters previously had their songs emptied. This is removed: all
   chapter data stays available to native lookups; only presentation is hidden.
4. Added ChapterSelector.Start hook. Before native Start, clone an active native
   ChapterInfo template for custom chapters, set chapter/cover keys, filter hidden
   cards and reorder siblings. This follows Android prepareChapterCards rather
   than assuming adding a Chapter to the database creates a card. The original
   Start still performs its own discovery and button wiring. Afterwards, refresh
   custom labels, disable play for empty chapters, and adjust panel width for
   hidden cards. Failed preparation rolls back clones/visibility best-effort.
5. Native chart export now excludes MOD-only visual keys and always supplies the
   expected collection fields. Full visual data stays in chart.json. Added
   explicit chart-text, custom-release and chapter lifecycle diagnostics.

## Supplied sample

Testify IN Lv.16(new).zip passes ZIP CRC verification. Its file named
14072798.json actually contains PEC text: offset 425, 1803 note commands and line
indices through 169. All command names are supported by the current converter.
This inspection is not a full conversion/gameplay test. The existing importer
detects format from content rather than the file extension.

The Apple host conversion test now accepts this ZIP as an optional argument:

```sh
bash ios/tests/run_content_tests.sh '/path/to/Testify IN Lv.16(new).zip'
```

The supplied music/art/chart are not copied into the source upload or CI fixtures.

## Verification and limits

- 36 source regression tests passed.
- 193 metadata / 63 hook contracts, 515 source lookups, six negative fixtures passed.
- All 63 actual-image ARM64 gateways passed emulation, plus judge/reference tests.
- All five portable C++ suites passed, including 3019 RPE checks.
- IDA MCP refused connections during this session. Hook signatures were checked
  against dump.cs; entry bytes and native release flow were inspected directly in
  the original iOS Mach-O using Capstone and existing decompilation records.
- No Apple SDK compilation, full sample conversion or iPad execution was possible
  on this Windows host. The release-path defect is confirmed; whether it accounts
  for the entire reported loading stall remains to be verified on the device.

## Test after rebuilding and repackaging

Back up local saves/charts. Do not uninstall the only copy of your data.

1. Confirm startup logs show hooks=63. Open an already imported song: check cover
   and music preview. Existing imported files need not be deleted for these fixes.
2. Start Testify. Expect Content custom release (ReleaseResource), subsequent music
   asset load, SetCodeForNote/SetInformation and a progressing playback clock.
3. Hide MainStory5 and Apply: its card should disappear, not turn Locked. Restore
   it from the management page and confirm its songs remain intact.
4. Create/apply an empty custom chapter: the card should appear but Play remains
   disabled. Add a chart, apply again, verify title/cover/order and song navigation.
5. Return from gameplay/settings repeatedly and test one unmodified official song.
   If loading still stalls, export the new full session log; keep the old log too.
