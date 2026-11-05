miniz: 3.1.2 (richgel999/miniz), MIT license in miniz/LICENSE.
stb_vorbis: 1ee679ca2ef753a528db5ba6801e1067b40481b8 (nothings/stb), MIT/public domain in stb/LICENSE.

Shader compiler dependencies (vendored source, no build-time fetch):
- glslang 15.1.0: KhronosGroup/glslang commit 1062752a891c95b2bfeed9e356562d88f9df84ac, source in glslang-src; see glslang-src/LICENSE.txt and per-file notices.
- SPIRV-Cross vulkan-sdk-1.4.304.0: KhronosGroup/SPIRV-Cross commit ebe2aa0cd80f5eb5cd8a605da604cacf72205f3b, source in spirv-cross-src; see spirv-cross-src/LICENSE and LICENSES/.
- Both are built statically by shader-compiler/CMakeLists.txt. SPIRV-Tools optimization, HLSL frontend, CLI and upstream tests are disabled. The local test executable retains assertions in Release.
- Do not copy the audit/unused-git-* or audit/cmake-tool directories into the product; they are not dependencies.
