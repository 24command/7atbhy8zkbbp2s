#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$ROOT/build}"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
REVISION="${GITHUB_SHA:-$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo local)}"
[[ "$REVISION" =~ ^[a-zA-Z0-9._-]+$ ]] || REVISION=local
echo "PhiMod source revision: $REVISION (settings-route-v4-20261114)"
mkdir -p "$OUT/PhiMod.framework"
bash "$ROOT/tools/build_shader_compiler.sh" "$OUT"
echo "PhiMod build: explicit ImageIO + CoreMedia linkage (2026-10-25)"
xcrun --sdk iphoneos clang++ \
  -arch arm64 -isysroot "$SDK" -miphoneos-version-min=15.0 \
  -std=c++17 -fobjc-arc -fvisibility=hidden -dynamiclib \
  -DPM_BUILD_REVISION="\"$REVISION\"" \
  -framework UIKit \
  -framework Foundation \
  -framework CoreGraphics \
  -framework CoreImage \
  -framework QuartzCore \
  -framework Metal \
  -framework AVFoundation \
  -framework CoreMedia \
  -framework ImageIO \
  -framework UniformTypeIdentifiers \
  -Wl,-install_name,@rpath/PhiMod.framework/PhiMod \
  -Wl,-dead_strip \
  "$ROOT"/PhiMod/Sources/*.mm \
  "$ROOT"/PhiMod/Vendor/PMZipVendor.cpp \
  "$ROOT"/PhiMod/Vendor/PMVorbisVendor.cpp \
  "$OUT/compiler-lib/libPMShaderCompiler.a" \
  -I"$ROOT/PhiMod/Vendor" \
  -o "$OUT/PhiMod.framework/PhiMod"
cp "$ROOT/PhiMod/Resources/Info.plist" "$OUT/PhiMod.framework/Info.plist"
/usr/bin/codesign --force --sign - --timestamp=none "$OUT/PhiMod.framework"
echo "Built: $OUT/PhiMod.framework"
