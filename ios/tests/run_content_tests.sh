#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/phimod-content.XXXXXX")"
trap 'rm -f "$OUT/core" "$OUT/host"; rmdir "$OUT"' EXIT
clang++ -std=c++17 -Wall -Wextra -Werror "$ROOT/tests/PMRPECoreTest.cpp" -o "$OUT/core"
"$OUT/core"
clang++ -std=c++17 -fobjc-arc -framework Foundation "$ROOT/tests/PMContentHostTest.mm" "$ROOT/PhiMod/Sources/PMChartConvert.mm" "$ROOT/PhiMod/Sources/PMArchive.mm" "$ROOT/PhiMod/Vendor/PMZipVendor.cpp" -o "$OUT/host"
"$OUT/host"
