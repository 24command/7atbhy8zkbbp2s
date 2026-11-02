#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?output directory required}"
cmake -S "$ROOT/shader-compiler" -B "$OUT/compiler-build" \
 -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_ARCHITECTURES=arm64 \
 -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 -DCMAKE_BUILD_TYPE=Release \
 -DCMAKE_CXX_VISIBILITY_PRESET=hidden -DCMAKE_VISIBILITY_INLINES_HIDDEN=ON
cmake --build "$OUT/compiler-build" --config Release --target pmshadercompiler --parallel 3
mkdir -p "$OUT/compiler-lib"
find "$OUT/compiler-build" -name '*.a' -print0 | xargs -0 xcrun libtool -static -o "$OUT/compiler-lib/libPMShaderCompiler.a"
