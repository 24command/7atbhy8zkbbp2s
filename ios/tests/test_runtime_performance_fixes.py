from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
def source(name): return (ROOT/'PhiMod/Sources'/name).read_text(encoding='utf8')
class RuntimePerformanceFixes(unittest.TestCase):
 def test_hit_effect_is_hidden_until_native_placement_finishes(self):
  s=source('PMRuntimeFeatures.mm').split('void skinEffectCreated(',1)[1].split('void styleLine(',1)[0]
  self.assertLess(s.index('"set_enabled"'),s.index('"set_sprite"'))
  self.assertIn('packEffectsPending=true',s)
  fx=source('PMPackEffects.inc').split('void finishPackEffects(',1)[1].split('void updatePackEffects(',1)[0]
  self.assertLess(fx.index('"get_position"'),fx.index('"set_enabled"'))
  self.assertLess(fx.index('"set_localScale"'),fx.index('"set_enabled"'))
  self.assertIn('nativeScale.x*packFxScale',fx)
  self.assertIn('nativeScale.y*packFxScale',fx)
  self.assertIn('r.gchandle_free(e.source);e.source=0',fx)
  update=source('PMPackEffects.inc').split('void updatePackEffects(',1)[1]
  self.assertNotIn('"set_position"',update)
  hook=source('PMHookBackend.mm').split('void onNoteManager(',1)[1].split('P onSkinInstantiate(',1)[0]
  self.assertLess(hook.index('orig<VoidFn>(h::noteManager)'),hook.index('pmfeatures::flushHitEffects'))
 def test_hit_effect_matches_native_sprite_size_without_double_note_scale(self):
  fx=source('PMPackEffects.inc').split('void finishPackEffects(',1)[1].split('void updatePackEffects(',1)[0]
  self.assertIn('(a.w/ap)/(b.w/bp)',fx)
  self.assertIn('visual.x*ratio*packFxScale',fx)
  self.assertIn('visual.y*ratio*packFxScale',fx)
  self.assertNotIn('"noteScale"',fx)
  self.assertLess(fx.index('referenceRenderer'),fx.index('"set_enabled"'))
  self.assertIn('referenceWidth=rect.w/ppu',source('PMRuntimeFeatures.mm'))
 def test_video_avoids_eager_decode_and_repeated_constant_setters(self):
  s=source('PMRuntimeFeatures.mm')
  self.assertIn('std::upper_bound(a.begin(),a.end(),now',s)
  self.assertIn('if(!v.go&&now<v.start-2.)continue;',s)
  self.assertIn('if(!(v.length>0))continue;',s)
  self.assertIn('if(!active&&!v.wasActive)continue;',s)
  self.assertIn('color.a!=v.lastColor.a',s)
  self.assertIn('if(!v.begun||!v.wasActive)',s)
  self.assertIn('now>=v.start+v.length+2.',s)
  self.assertIn('if(v.go)releaseVideo(r,v)',s)
 def test_managed_bridge_retains_checked_abi(self):
  s=source('PMIL2CPP.hpp')
  self.assertIn('gameClassCache.find(name)',s)
  self.assertIn('std::array<P,16> local',s)
  self.assertIn('overflow.assign(args)',s)
  self.assertIn('runtime_invoke(method,self,arguments,&ex)',s)
  self.assertIn('Managed call failed:',s)
  self.assertNotIn('reinterpret_cast<P(*)(P',s)
 def test_shader_discard_requires_preservation(self):
  s=source('PMMetalShaders.mm')
  self.assertIn('if(e.fullCompiler&&e.full.discards)',s)
  self.assertIn('(e.fullCompiler&&e.full.discards)?MTLLoadActionLoad:MTLLoadActionDontCare',s)
  compiler=(ROOT/'PhiMod/Core/PMFullShaderCompiler.cpp').read_text(encoding='utf8')
  self.assertIn('result.msl.find("discard_fragment")',compiler)
 def test_custom_cpu_reduces_repeated_decoding_without_new_culling(self):
  s=source('PMContentRuntime.mm')
  self.assertIn('visualTracks.clear()',s)
  self.assertIn('visualTracks.find(key)',s)
  self.assertIn('controlTrack(d,@"alphaControl")',s)
  near=s.split('bool sourceVisualNear(',1)[1].split('void recoverSourceNotes(',1)[0]
  self.assertNotIn('control(d,',near)
  self.assertIn('controlValue(line.alphaControl,distance)',near)
  self.assertIn('if(!due&&!phimod::rpeVisibleAt',s)
  self.assertIn('f.start,f.type==3,f.below,f.x,worldSpeed',s)
  self.assertIn('RPE CPU split (300 frames)',source('PMHookBackend.mm'))
 def test_metadata_validation_is_cached_only_after_success(self):
  s=source('PMIL2CPP.hpp').split('template<class T> void checkClass(',1)[1].split('template<class T> T get(',1)[0]
  self.assertLess(s.index('Primitive type contract mismatch'),s.index('checkedValueClasses.insert(key)'))
  self.assertIn('static const char typeToken',s)
if __name__=='__main__': unittest.main()
