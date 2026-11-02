#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d "${TMPDIR:-/tmp}/phimod-shader.XXXXXX")"
trap 'rm -rf "$OUT"' EXIT
clang++ -std=c++17 -Wall -Wextra -Werror "$ROOT/tests/PMShaderSourceTest.cpp" -o "$OUT/test"
"$OUT/test" "$OUT"
# Compile every generated preset with the real iOS Metal compiler.
# This catches MSL errors that Windows C++ checks cannot detect.
for shader in "$OUT"/*.metal; do
 xcrun --sdk iphoneos metal -std=ios-metal2.3 -c "$shader" -o "$shader.air"
done
