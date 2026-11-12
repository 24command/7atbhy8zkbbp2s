# Chapter-entry crash fix (2026-11-13)

## Confirmed defect
The custom chapter factory appended immutable NSDictionary literals, including immutable songInfo, to the otherwise mutable deserialized chapter list. The official-song reference rewrite then assigned songInfo.songs. This throws the exact __NSDictionaryI setObject:forKeyedSubscript exception in the screenshot. The library command caught NSException and showed it; the ChapterSelector.Start hook caught only std::exception, allowing the same Objective-C failure to escape into Unity.

## Changes
- Production PMNativeChapter factory makes all nested JSON dictionaries/arrays independently mutable; local song records and appended/referenced entries use the same recursive copy. Untouched baseline data is not mutated.
- Variant routing is built separately and swapped after successful content publication. Baseline capture waits for the complete song/chapter snapshot.
- apply converts NSException to the existing C++ error path. Chapter preparation and post-layout callbacks have both exception boundaries; original ChapterSelector.Start runs exactly once even if MOD preparation fails. Selector shortcut/content/unlock work is isolated.
- Bootstrap backend initialization and content pulse catch Objective-C exceptions and retain useful diagnostics.
- Shared generic Instantiate still invokes the native original for every object; optional hit-FX logic runs only in a main-thread note-control scope, not title/chapter UI creation.
- Hook ABI/count remains72. Do not use a pre72 IPA as a base.

## Validation / limitations
Foundation regression uses the actual chapter factory, replaces songInfo.songs, edits nested unlock arrays/records, and verifies immutable input is unchanged. Source contract and metadata tests also run; iOS compile is checked by Actions. No device crash trace is available: this proves the dialog/automatic chapter-entry data failure, not every possible intermittent title-screen crash. If an early crash remains after this build, collect the matching PhiMod diagnostics and iOS .ips crash report (or JetsamEvent for memory termination). Do not clear library or saves to test.

Rebuild framework and package with current tools. No chart reimport or library deletion is needed.
