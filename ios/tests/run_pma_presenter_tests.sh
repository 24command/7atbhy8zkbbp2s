#!/bin/bash
# Real Foundation/ImageIO tests on macOS; UIKit presenter/actions syntax-checked for iOS.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$(uname -s)" != Darwin ]]; then
  echo "PMA native tests require macOS + Xcode; refusing to silently skip." >&2
  exit 1
fi
command -v xcrun >/dev/null
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
export CXX="$(xcrun --sdk macosx --find clang++)"
python3 "$ROOT/tests/test_native_os_frame_sequence.py"
python3 "$ROOT/tests/test_pma_one_shot_presenter.py"
python3 "$ROOT/tests/test_pma_map_clock.py"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun --sdk iphoneos clang++ -std=c++17 -fobjc-arc -fsyntax-only \
  -arch arm64 -isysroot "$SDK" -miphoneos-version-min=15.0 \
  -I"$ROOT/PhiMod/Vendor" \
  "$ROOT/PhiMod/Sources/PMNativeOSFrameSequence.mm" \
  "$ROOT/PhiMod/Sources/PMUnlockMedia.mm" \
  "$ROOT/PhiMod/Sources/PMNativeOSActions.mm" \
  "$ROOT/PhiMod/Sources/PMNativeOSMap.mm" \
  "$ROOT/PhiMod/Sources/PMNativeOSEntryTimeline.mm"
