#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/phimod-core.XXXXXX")"
trap 'rm -f "$OUT/PMGameplayCoreTest" "$OUT/PMJudgeCoreTest"; rmdir "$OUT"' EXIT
"${CXX:-clang++}" -std=c++17 -Wall -Wextra -Werror -pedantic "$ROOT/tests/PMGameplayCoreTest.cpp" -o "$OUT/PMGameplayCoreTest"
"$OUT/PMGameplayCoreTest"

"${CXX:-clang++}" -std=c++17 -Wall -Wextra -Werror -pedantic "$ROOT/tests/PMJudgeCoreTest.cpp" -o "$OUT/PMJudgeCoreTest"
"$OUT/PMJudgeCoreTest"
