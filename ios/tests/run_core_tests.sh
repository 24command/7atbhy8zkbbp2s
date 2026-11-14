#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/phimod-core.XXXXXX")"
trap 'rm -f "$OUT/PMGameplayCoreTest" "$OUT/PMJudgeCoreTest" "$OUT/PMFlowCoreTest" "$OUT/PMModeCoreTest" "$OUT/PMUIInteractionTest" "$OUT/PMSettingsTabRouteTest" "$OUT/PMUILayoutModalTest"; rmdir "$OUT"' EXIT
"${CXX:-clang++}" -std=c++17 -Wall -Wextra -Werror -pedantic "$ROOT/tests/PMGameplayCoreTest.cpp" -o "$OUT/PMGameplayCoreTest"
"$OUT/PMGameplayCoreTest"

"${CXX:-clang++}" -std=c++17 -Wall -Wextra -Werror -pedantic "$ROOT/tests/PMJudgeCoreTest.cpp" -o "$OUT/PMJudgeCoreTest"
"$OUT/PMJudgeCoreTest"

python3 "$ROOT/tests/test_scene_state_lookup.py" --cxx "${CXX:-clang++}"

"${CXX:-clang++}" -std=c++17 -Wall -Wextra -Werror -pedantic "$ROOT/tests/PMFlowCoreTest.cpp" -o "$OUT/PMFlowCoreTest"
"$OUT/PMFlowCoreTest"

"${CXX:-clang++}" -std=c++17 -Wall -Wextra -Werror -pedantic "$ROOT/tests/PMModeCoreTest.cpp" -o "$OUT/PMModeCoreTest"
"$OUT/PMModeCoreTest"

"${CXX:-clang++}" -std=c++17 -Wall -Wextra -Werror -pedantic "$ROOT/tests/PMUIInteractionTest.cpp" -o "$OUT/PMUIInteractionTest"
"$OUT/PMUIInteractionTest"

"${CXX:-clang++}" -std=c++17 -Wall -Wextra -Werror -pedantic "$ROOT/tests/PMSettingsTabRouteTest.cpp" -o "$OUT/PMSettingsTabRouteTest"
"$OUT/PMSettingsTabRouteTest"

"${CXX:-clang++}" -std=c++17 -Wall -Wextra -Werror -pedantic "$ROOT/tests/PMUILayoutModalTest.cpp" -o "$OUT/PMUILayoutModalTest"
"$OUT/PMUILayoutModalTest"
