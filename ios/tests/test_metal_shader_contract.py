from pathlib import Path
import unittest
R=Path(__file__).resolve().parents[1]
class MetalShaderContract(unittest.TestCase):
 def test_backend_is_wired_and_scoped(self):
  source=(R/'PhiMod/Sources/PMMetalShaders.mm').read_text(encoding='utf-8')
  features=(R/'PhiMod/Sources/PMRuntimeFeatures.mm').read_text(encoding='utf-8')
  self.assertIn('metal.layer!=gameLayer',source)
  self.assertIn('buffer.retainedReferences',source)
  self.assertIn('if(!e.global||e.range)',source)
  self.assertIn('params.clock[0]=float(now)',source)
  self.assertIn('token!=generation.load()',source)
  self.assertNotIn('waitUntilCompleted',source)
  self.assertNotIn('getBytes:',source)
  for op in ('copyFromTexture:','setFragmentBytes:','drawPrimitives:','addCompletedHandler:'):
   self.assertIn(op,source)
  self.assertIn('PMMetalShadersLoad(folder)',features)
  self.assertIn('PMMetalShadersClear()',features)
  self.assertIn('PMMetalShadersTick(',features)
  self.assertIn('-framework Metal',(R/'build_unsigned.sh').read_text(encoding='utf-8'))
 def test_host_shader_check_in_ci(self):
  self.assertIn('run_shader_tests.sh',next(p for p in (R.parent/'.github/workflows/build-ios.yml',R/'.github/workflows/build-ios.yml') if p.is_file()).read_text(encoding='utf-8'))
  self.assertIn('xcrun --sdk iphoneos metal',(R/'tests/run_shader_tests.sh').read_text(encoding='utf-8'))
 def test_large_uniform_storage_is_reused_only_after_gpu_completion(self):
  s=(R/'PhiMod/Sources/PMMetalShaders.mm').read_text(encoding='utf-8')
  self.assertIn('scratch->uniformBuffers[e.index]',s)
  self.assertIn('uniformBuffer.length<bytes.size()',s)
  self.assertIn('memcpy(uniformBuffer.contents,bytes.data(),bytes.size())',s)
  self.assertIn('scratch->busy=false',s)
  self.assertIn('compare_exchange_strong(expected,true)',s)
  self.assertNotIn('newBufferWithBytes:bytes.data()',s)
if __name__=='__main__':unittest.main()
