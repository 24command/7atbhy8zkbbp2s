#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$ROOT/build}"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
mkdir -p "$OUT/PhiMod.framework"
xcrun --sdk iphoneos clang++ \
  -arch arm64 -isysroot "$SDK" -miphoneos-version-min=15.0 \
  -std=c++17 -fobjc-arc -fvisibility=hidden -dynamiclib \
  -framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore \
  -Wl,-install_name,@rpath/PhiMod.framework/PhiMod \
  -Wl,-dead_strip \
  "$ROOT"/PhiMod/Sources/*.mm \
  -o "$OUT/PhiMod.framework/PhiMod"
cp "$ROOT/PhiMod/Resources/Info.plist" "$OUT/PhiMod.framework/Info.plist"
/usr/bin/codesign --force --sign - --timestamp=none "$OUT/PhiMod.framework"
echo "Built: $OUT/PhiMod.framework"
