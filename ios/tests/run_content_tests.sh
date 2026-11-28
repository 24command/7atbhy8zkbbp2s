#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/phimod-content.XXXXXX")"
trap 'rm -f "$OUT/core" "$OUT/host" "$OUT/unlock" "$OUT/text" "$OUT/cover" "$OUT/pcm" "$OUT/compact" "$OUT/trash" "$OUT/opacity" "$OUT/framecache" "$OUT/visibility" "$OUT/export" "$OUT/cachedtrack" "$OUT/difficulties" "$OUT/selection" "$OUT/arrows" "$OUT/modlayout" "$OUT/recoveryindex" "$OUT/contentio" "$OUT/selectorrows" "$OUT/selectorsort" "$OUT/chaptervm" "$OUT/checkpoint" "$OUT/doorrun" "$OUT/chapter-checkpoint.plist" "$OUT/chapter-checkpoint.lock"; rmdir "$OUT"' EXIT
clang++ -std=c++17 -fobjc-arc -DPMOS_CHECKPOINT_HOST_TEST -framework Foundation -framework CoreFoundation \
  "$ROOT/tests/PMOSCheckpointTest.mm" "$ROOT/PhiMod/Sources/PMOSCheckpoint.mm" -o "$OUT/checkpoint"
# Each phase is a new process sharing only the temporary on-disk store.
for phase in write resume consume; do
  "$OUT/checkpoint" "$OUT" "$phase"
done
clang++ -std=c++17 -fobjc-arc -DPMDOOR_RUN_HOST_TEST -framework Foundation -framework CoreFoundation \
  "$ROOT/tests/PMDoorRunTest.mm" "$ROOT/PhiMod/Sources/PMDoorRun.mm" "$ROOT/PhiMod/Sources/PMOSAuthorProgress.mm" -o "$OUT/doorrun"
"$OUT/doorrun"
# Compile the C VM once for both the portable and Foundation host suites.
(
  cd "$OUT"
  trap 'rm -f ./*.o ./chaptercover ./chapterlife ./c8waveform ./nativemap ./mapflash' EXIT
  clang -std=c99 -O2 -c "$ROOT"/PhiMod/Vendor/lua54/*.c "$ROOT/PhiMod/Core/PMChapterVM.c"
  clang -std=c99 -O2 "$ROOT/tests/PMChapterVMTest.c" ./*.o -o chaptervm
  ./chaptervm
  clang -std=c99 -O2 -UNDEBUG "$ROOT/tests/PMChapterNumericTracksTest.c" ./*.o -o chaptervm
  ./chaptervm
  clang -std=c99 -O2 -UNDEBUG "$ROOT/tests/PMChapterPMAOneShotTest.c" ./*.o -o chaptervm
  ./chaptervm
  clang -std=c99 -O2 -UNDEBUG "$ROOT/tests/PMChapterAudioTest.c" ./*.o -o chaptervm
  ./chaptervm
  clang -std=c99 -O2 -UNDEBUG "$ROOT/tests/PMChapterInterruptionTest.c" ./*.o -o chaptervm
  ./chaptervm
  clang -std=c99 -O2 -UNDEBUG "$ROOT/tests/PMChapterEnterSceneTest.c" ./*.o -o chaptervm
  ./chaptervm
  clang -std=c99 -O2 -UNDEBUG "$ROOT/tests/PMChapterBlendTest.c" ./*.o -o chaptervm
  ./chaptervm
  clang++ -std=c++17 -O2 -UNDEBUG "$ROOT/tests/PMNativeOSNumericTracksTest.cpp" ./*.o -o nativemap
  ./nativemap
  clang -std=c99 -O2 "$ROOT/tests/PMChapterSongVisibilityTest.c" ./*.o -o chaptervm
  ./chaptervm
  clang -std=c99 -O2 "$ROOT/tests/PMChapterC8WaveformTest.c" ./*.o -o c8waveform
  ./c8waveform
  python3 "$ROOT/tests/test_native_os_c8_waveform.py"
  clang -std=c99 -O2 "$ROOT/tests/PMChapterC9RouteTest.c" ./*.o -o chaptervm
  ./chaptervm
  clang -std=c99 -O2 -UNDEBUG "$ROOT/tests/PMChapterEntryTransitionTest.c" ./*.o -o chaptervm
  ./chaptervm
  python3 "$ROOT/tests/test_native_os_c9_route.py"
  clang++ -std=c++17 -O2 "$ROOT/tests/PMNativeOSMapTest.cpp" ./*.o -o nativemap
  ./nativemap
  clang++ -std=c++17 -O2 "$ROOT/tests/PMNativeOSMapReadinessTest.cpp" -o nativemap
  ./nativemap
  clang++ -std=c++17 -O2 "$ROOT/tests/PMNativeOSEntryTimelineTest.cpp" -o nativemap
  ./nativemap
  clang++ -std=c++17 -O2 "$ROOT/tests/PMNativeOSMapFlashTest.cpp" -framework CoreGraphics -o mapflash
  ./mapflash
  clang -std=c99 -O2 "$ROOT/tests/PMChapterLifeTest.c" ./*.o -o chapterlife
  ./chapterlife
  clang++ -std=c++17 -fobjc-arc -DPMDOOR_RUN_HOST_TEST -framework Foundation -framework CoreFoundation \
    "$ROOT/tests/PMChapterCoverTest.mm" "$ROOT/PhiMod/Sources/PMDoorRun.mm" \
    "$ROOT/PhiMod/Sources/PMOSAuthorProgress.mm" ./*.o -o chaptercover
  ./chaptercover
  clang++ -std=c++17 -fobjc-arc -DPMDOOR_RUN_HOST_TEST -framework Foundation -framework CoreFoundation \
    "$ROOT/tests/PMDoorReturnFlowTest.mm" "$ROOT/PhiMod/Sources/PMDoorRun.mm" \
    "$ROOT/PhiMod/Sources/PMOSAuthorProgress.mm" ./*.o -o chaptercover
  ./chaptercover
)
python3 "$ROOT/tests/test_song_interruption_timeline.py"
python3 "$ROOT/tests/test_song_interruption_glitch.py"
clang++ -std=c++17 -O2 "$ROOT/tests/PMNativeOSAudioTimelineTest.cpp" -o "$OUT/core"
"$OUT/core"
clang++ -std=c++17 -fobjc-arc -DPM_NATIVE_OS_AUDIO_HOST_TEST -framework Foundation -framework AVFoundation "$ROOT/tests/PMNativeOSAudioTest.mm" -o "$OUT/core"
"$OUT/core"
python3 "$ROOT/tests/test_native_os_frame_sequence.py"
python3 "$ROOT/tests/run_chapter_puzzle.py" clang -O2
python3 "$ROOT/tests/test_story_sequence.py"
python3 "$ROOT/tests/test_story_native_start.py"
python3 "$ROOT/tests/test_secret_course_native.py"
clang++ -std=c++17 -Wall -Wextra -Werror "$ROOT/tests/PMRPECoreTest.cpp" -o "$OUT/core"
clang++ -std=c++17 -Wall -Wextra -Werror "$ROOT/tests/PMCoverGeometryTest.cpp" -o "$OUT/cover"
"$OUT/cover"
clang++ -std=c++17 -Wall -Wextra -Werror "$ROOT/tests/PMRPETextTest.cpp" -o "$OUT/text"
"$OUT/text"
clang++ -std=c++17 "$ROOT/tests/PMPCMImportTest.cpp" "$ROOT/PhiMod/Vendor/PMZipVendor.cpp" -o "$OUT/pcm"
"$OUT/pcm" "$OUT"
clang++ -std=c++17 -fobjc-arc -framework Foundation -framework AVFoundation "$ROOT/tests/PMImportCompactionTest.mm" "$ROOT/PhiMod/Sources/PMContentIO.mm" -o "$OUT/compact"
"$OUT/compact"
"$OUT/core"
clang++ -std=c++17 -fobjc-arc -framework Foundation "$ROOT/tests/PMContentHostTest.mm" "$ROOT/PhiMod/Sources/PMChartConvert.mm" "$ROOT/PhiMod/Sources/PMArchive.mm" "$ROOT/PhiMod/Vendor/PMZipVendor.cpp" -o "$OUT/host"
"$OUT/host" "$@"
clang++ -std=c++17 -fobjc-arc -framework Foundation "$ROOT/tests/PMUnlockProgressTest.mm" "$ROOT/PhiMod/Sources/PMUnlockProgress.mm" -o "$OUT/unlock"
"$OUT/unlock"

clang++ -std=c++17 -fobjc-arc -framework Foundation "$ROOT/tests/PMTrashStoreTest.mm" -o "$OUT/trash"
"$OUT/trash"

clang++ -std=c++17 -fobjc-arc -framework Foundation "$ROOT/tests/PMOpacitySettingsTest.mm" "$ROOT/PhiMod/Sources/PMSettings.mm" -o "$OUT/opacity"
"$OUT/opacity"

clang++ -std=c++17 -Wall -Wextra -Werror "$ROOT/tests/PMFrameCacheTest.cpp" -o "$OUT/framecache"
"$OUT/framecache"

clang++ -std=c++17 -Wall -Wextra -Werror "$ROOT/tests/PMRPEVisibilityTest.cpp" -o "$OUT/visibility"
"$OUT/visibility"

clang++ -std=c++17 -fobjc-arc -framework Foundation "$ROOT/tests/PMExportArchiveTest.mm" "$ROOT/PhiMod/Sources/PMArchive.mm" "$ROOT/PhiMod/Vendor/PMZipVendor.cpp" -o "$OUT/export"
"$OUT/export"

clang++ -std=c++17 -Wall -Wextra -Werror "$ROOT/tests/PMCachedRPETrackTest.cpp" -o "$OUT/cachedtrack"
"$OUT/cachedtrack"
python3 "$ROOT/tests/test_high_refresh_package.py"

clang++ -std=c++17 -fobjc-arc -framework Foundation "$ROOT/tests/PMDifficultyMetadataTest.mm" -o "$OUT/difficulties"
"$OUT/difficulties"
python3 "$ROOT/tests/test_extra_difficulty_routing.py"

clang++ -std=c++17 -Wall -Wextra -Werror "$ROOT/tests/PMSelectionLifecycleTest.cpp" -o "$OUT/selection"
"$OUT/selection"

clang++ -std=c++17 -Wall -Wextra -Werror "$ROOT/tests/PMDifficultyArrowGeometryTest.cpp" -o "$OUT/arrows"
"$OUT/arrows"

clang++ -std=c++17 -Wall -Wextra -Werror "$ROOT/tests/PMModSettingsLayoutTest.cpp" -o "$OUT/modlayout"
"$OUT/modlayout"

clang++ -std=c++17 -O2 -Wall -Wextra -Werror "$ROOT/tests/PMRecoveryIndexTest.cpp" -o "$OUT/recoveryindex"
"$OUT/recoveryindex"

clang++ -std=c++17 -fobjc-arc -framework Foundation "$ROOT/tests/PMContentIOTest.mm" "$ROOT/PhiMod/Sources/PMContentIO.mm" -o "$OUT/contentio"
"$OUT/contentio"
python3 "$ROOT/tests/test_content_memory_contracts.py"

python3 "$ROOT/tests/test_chapter_picker_page.py"
python3 "$ROOT/tests/test_dense_effects_regression.py"
python3 "$ROOT/tests/test_bridge_metadata_cache.py"
python3 "$ROOT/tests/test_logical_rows_and_zero_skew.py"

clang++ -std=c++17 -O2 -Wall -Wextra -Werror "$ROOT/tests/PMSelectorRowRefreshTest.cpp" -o "$OUT/selectorrows"
"$OUT/selectorrows"
python3 "$ROOT/tests/test_selector_refresh_cost.py"

clang++ -std=c++17 -O2 -Wall -Wextra -Werror "$ROOT/tests/PMSelectorSortTest.cpp" -o "$OUT/selectorsort"
"$OUT/selectorsort"
python3 "$ROOT/tests/test_shared_at_sort.py"
python3 "$ROOT/tests/test_import_picker_lifecycle.py"

(
  trap 'rm -f "$OUT/authorprogress"' EXIT
  clang++ -std=c++17 -fobjc-arc -framework Foundation -framework CoreFoundation \
    "$ROOT/tests/PMOSAuthorProgressTest.mm" "$ROOT/PhiMod/Sources/PMOSAuthorProgress.mm" -o "$OUT/authorprogress"
  "$OUT/authorprogress"
)

python3 "$ROOT/tests/test_song_interruption.py"
python3 "$ROOT/tests/test_song_interruption_gameplay.py"
python3 "$ROOT/tests/test_song_interruption_lifecycle.py"
python3 "$ROOT/tests/test_native_os_enter_scene.py"
python3 "$ROOT/tests/test_native_os_blend.py"
