# RPE Metal global shader implementation ? 2026-10-31

## Implemented source path
PMRuntimeFeatures.afterChart -> PMMetalShadersLoad; chart clock -> PMMetalShadersTick; begin/end -> clear.
Parse effects.tsv F/R/K records, preserve effect index ordering and absolute-time parameter sampling. Shader time is absolute chart time, matching Android shaderUniformValues.
Load ten upstream presets or UTF-8 extensions/<shader> source, at most 1 MiB. Translate supported float/vec2/vec4 uniforms, defaults, common GLSL arithmetic and screenTexture samples into Metal source. Compilation and initial pipeline creation run off the game thread.
Intercept the concrete Metal command buffer presentation methods using Objective-C method replacement. Only the selected game's CAMetalLayer/device is processed. Append same-buffer copy + ping-pong full-screen draws before original presentation; no CPU pixel readback, GPU waits or executable-memory patching. Three reusable scratch slots are released by GPU completion. Unretained buffers are skipped. Unsupported effects log and do not prevent gameplay.
No new IL2CPP RVA hooks: remains 68 / 4.0.3.

## Explicit incomplete scope
- Only global=true with no targetRange is rendered. Chart-only and range-specific rendering boundaries remain unimplemented; they are logged/skipped rather than rendered over HUD incorrectly.
- Custom GLSL support is a restricted translation layer, not a general GLSL compiler. Unsupported declarations, extra samplers, matrices and helper functions using globals are rejected; compiler errors are logged. No arbitrary-GLSL parity claim.
- Presentation interception depends on Unity using the discovered concrete command buffer implementation, retainedReferences and a readable drawable. Actual device behavior is unverified.
- No Apple SDK or GPU compilation/execution was available locally. Do not describe this as fully migrated or verified rendering.

## Verification
MSVC PMShaderSourceTest: all 10 presets converted, defaults and keyframe/seek interpolation tested, unsupported matrix declaration rejected.
Source contracts 46 pass; Metal scope/lifecycle checks 2 pass; official-song no-folder guard 1 pass.
Metadata audit 198 / 68 / 562 lookups passes.
Added tests/run_shader_tests.sh and macOS workflow step to compile EVERY generated preset with the real iOS Metal compiler before framework build. This step has not run locally.

## Upload/build
Upload PhiMod/Core/PMShaderSource.hpp, Sources/PMMetalShaders.h/.mm, modified PMRuntimeFeatures.mm, PMSceneUI.mm, Vendor/phira-shaders (including LICENSE/NOTICE), build_unsigned.sh, tests/PMShaderSourceTest.cpp and tests/run_shader_tests.sh; easiest is sync entire ios folder.
Sync local ios/.github/workflows/build-ios.yml to repository-root .github/workflows/build-ios.yml.
Expected diagnostics: Metal presentation hook installed; RPE Metal global shaders ready; RPE Metal shader rendered on game drawable.
First test: a short global grayscale effect with animated factor 0->1, then pause/seek/restart; verify effect ends and original songs remain unchanged. Then test each preset and look for compile/deferred/unsupported messages.
Original modified files preserved in audit/20261031-metal-shaders-232944.
