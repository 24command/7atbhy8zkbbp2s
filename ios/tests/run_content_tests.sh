#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/phimod-content.XXXXXX")"
trap 'rm -f "$OUT/core" "$OUT/host" "$OUT/unlock" "$OUT/text" "$OUT/cover" "$OUT/pcm" "$OUT/compact" "$OUT/trash" "$OUT/opacity" "$OUT/framecache" "$OUT/visibility" "$OUT/export" "$OUT/cachedtrack" "$OUT/difficulties" "$OUT/selection" "$OUT/arrows"; rmdir "$OUT"' EXIT
clang++ -std=c++17 -Wall -Wextra -Werror "$ROOT/tests/PMRPECoreTest.cpp" -o "$OUT/core"
clang++ -std=c++17 -Wall -Wextra -Werror "$ROOT/tests/PMCoverGeometryTest.cpp" -o "$OUT/cover"
"$OUT/cover"
clang++ -std=c++17 -Wall -Wextra -Werror "$ROOT/tests/PMRPETextTest.cpp" -o "$OUT/text"
"$OUT/text"
clang++ -std=c++17 "$ROOT/tests/PMPCMImportTest.cpp" "$ROOT/PhiMod/Vendor/PMZipVendor.cpp" -o "$OUT/pcm"
"$OUT/pcm" "$OUT"
clang++ -std=c++17 -fobjc-arc -framework Foundation -framework AVFoundation "$ROOT/tests/PMImportCompactionTest.mm" -o "$OUT/compact"
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
