#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/phimod-content.XXXXXX")"
trap 'rm -f "$OUT/core" "$OUT/host" "$OUT/unlock" "$OUT/text" "$OUT/cover" "$OUT/pcm" "$OUT/compact" "$OUT/trash"; rmdir "$OUT"' EXIT
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
