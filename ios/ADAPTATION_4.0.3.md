# Phigros iOS 4.0.3 adaptation ? 2026-10-31

Target source: G:/Phimod-ios/ios
Target game: G:/games.Pigeon.Phigros_v4.0.3_und3fined (Info.plist: 4.0.3)
Original 4.0.1 sources/core/tools/workflow are preserved in audit/20261031-v403/before.

## Changes
- Mapped all 68 entry hooks by exact type/method/argument signature from the new dump; matched shared AssetRef generic entries separately. All first-instruction bytes remain the same.
- Updated C++ expected-entry manifest, JSON patch manifest and UUID gate to 70f666eb6f4e325e9e8a75b568085f26.
- Updated the three ProgressControl.Update judgment stores to 0x1593578, 0x15935ec, 0x1593600; encodings/register roles unchanged.
- Added build marker PMGameplay-contract-v2-68-ios403 to framework, CI and packager. Packager validates target UUID before copying Payload and rejects a 4.0.1 framework.
- Build 40368. Source targets only supplied 4.0.3; not a combined 4.0.1/4.0.3 framework.
- Fake note optimizations, real Hold behavior, official-song resource fix and user changes to practice/conversion are untouched.
- Fixed synthetic judge test's overlapping page mapping after sites moved. Removed local Android path dependency from source tests for macOS CI.

## Validation
- New dump.cs produced with Il2CppDumper v6.7.46, metadata 31. Optional structure/script generation failed due to host memory pressure; dump.cs is complete enough for all successful contract checks. Do not claim a complete Dumper export.
- IDA MCP verified current IDB is the 4.0.3 UnityFramework, awaited completed autoanalysis, checked six critical entry boundaries/bytes, decompiled ProgressControl.Update. Evidence: ida-critical.json.
- 198 metadata / 68 hook contracts + 554 lookups / 6 negative fixtures pass. Additional all-.mm literal lookup check: 574.
- 8 runtime contracts + 3 negative fixtures pass.
- Source contracts 46 pass; resume integrity 2 pass.
- ARM64 judge simulation 2 tests pass; gameplay gate simulation 3 tests pass (separate processes to avoid host memory exhaustion).
- Actual 4.0.3 binary judge + gameplay patch chain succeeded on a local audit copy; load-dylib injection also succeeded. Input game binary unchanged.
- No Apple SDK build or device test performed. Rebuild on macOS and repackage from clean 4.0.3 Payload; do not reuse an older IPA/framework.

## Files to upload
Upload the entire ios directory into repository ios/, including PhiMod/Core and tools.
Use ios/.github/workflows/build-ios.yml as the template for repository-root .github/workflows/build-ios.yml; nested .github is not automatically discovered by GitHub.
Keep dump.cs, raw game binaries, IDB and audit files local.
