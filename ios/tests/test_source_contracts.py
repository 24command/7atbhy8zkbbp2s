"""Source/protocol consistency guards; these are NOT an Apple SDK build."""
import json,re,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class SourceContracts(unittest.TestCase):
 def test_manifest_cpp_protocol_is_not_stale(self):
  manifest=json.loads((ROOT/'tools/gameplay_hook_manifest.json').read_text(encoding='utf-8'))
  protocol=(ROOT/'PhiMod/Core/PMHookProtocol.hpp').read_text(encoding='utf-8')
  header=(ROOT/'PhiMod/Core/PMHookManifest.hpp').read_text(encoding='utf-8')
  generated=re.findall(r'\{(0x[0-9a-f]+)u,(0x[0-9a-f]+)u\}',header)
  self.assertEqual(len(manifest),37);self.assertEqual(len(generated),37)
  for i,(entry,(site,word)) in enumerate(zip(manifest,generated)):
   self.assertRegex(protocol,r'\b'+re.escape(entry['id'])+'='+str(i)+r',')
   self.assertEqual(int(site,16),entry['rva'])
   self.assertEqual(int(word,16),int.from_bytes(bytes.fromhex(entry['bytes']),'little'))
 def test_no_declared_but_missing_ui_implementation(self):
  header=(ROOT/'PhiMod/Sources/PMSceneUI.hpp').read_text(encoding='utf-8')
  impl=(ROOT/'PhiMod/Sources/PMSceneUI.mm').read_text(encoding='utf-8')
  for name in re.findall(r'\b(?:void|bool)\s+(\w+)\(',header):self.assertRegex(impl,r'\b'+name+r'\(')
  self.assertIn('emptyClick(r,s.button)',impl)
  self.assertIn('"mirrorBackground"',impl)
  self.assertIn('"tabAnimators"',impl)
  self.assertIn('saveRequested',impl)
  self.assertIn('validateSnapshot:self.draft',impl)
 def test_ui_creation_rolls_back_instead_of_retrying_every_frame(self):
  s=(ROOT/'PhiMod/Sources/PMSceneUI.mm').read_text(encoding='utf-8')
  selector=s[s.index('void makeSelector('):s.index('void selectorLayout(')]
  self.assertIn('selectorRoot=r.gchandle_new(self,false);\n  throw;',selector)
  settings=s[s.index('void settingsFrame('):s.index('bool press(')]
  self.assertIn('visible=visible&&layoutReady;',s)
  self.assertIn('if(tabFailed)return;',settings)
  self.assertIn('tabFailed=true;tabButton=tabText=nullptr;dispose(r,tabRoot,true);throw;',settings)
  self.assertLess(settings.index('emptyClick(r,button)'),settings.index('tabButton=button;tabText=text;'))
  self.assertLess(settings.index('validateSnapshot:d'),settings.index('[PMRuntime applyJudgeSettings:'))
 def test_scene_state_avoids_posix_open_name_collision(self):
  s=(ROOT/'PhiMod/Sources/PMSceneUI.mm').read_text(encoding='utf-8')
  self.assertNotRegex(s,r'\bopen\b')
  self.assertIn('modEditorOpen=false',s)
  self.assertIn('modEditorOpen=true',s)
  self.assertIn('if(!modEditorOpen)return;',s)
 def test_ci_shell_scripts_use_lf(self):
  for relative in ('build_unsigned.sh', 'tests/run_core_tests.sh'):
   self.assertNotIn(b'\r', (ROOT/relative).read_bytes(), relative)
 def test_judge_cannot_enable_without_protection(self):
  s=(ROOT/'PhiMod/Sources/PMRuntime.mm').read_text(encoding='utf-8')
  self.assertLess(s.index('[PMHookBackend protectJudgeChange]'),s.index('controller.apply(*patch'))
  hook=(ROOT/'PhiMod/Sources/PMHookBackend.mm').read_text(encoding='utf-8')
  self.assertIn('Gateway manifest mismatch',hook)
  self.assertIn('Entry gate instruction mismatch',hook)
  self.assertIn('__atomic_store_n',hook)
  result=hook[hook.index('P onResultStart('):hook.index('bool onResultMove(')]
  self.assertNotIn('orig<P(*)(P,P)>(h::resultStart)(self,mi);',result.split('inResult=true;')[1])
  self.assertIn('return nullptr',result)
  self.assertIn('if(!options.assisted())',hook)
  self.assertIn('if(!guard.load())',hook)
 def test_unsupported_modes_are_not_claimed_ready(self):
  s=(ROOT/'PhiMod/Sources/PMHookBackend.mm').read_text(encoding='utf-8')
  self.assertIn('@"noiseReady":@NO',s);self.assertIn('@"unifiedReady":@NO',s)
  settings=(ROOT/'PhiMod/Sources/PMSettings.mm').read_text(encoding='utf-8')
  self.assertIn('Noise / Unified / No Noise are not available',settings)
  bootstrap=(ROOT/'PhiMod/Sources/PhiModBootstrap.mm').read_text(encoding='utf-8')
  self.assertIn('row.userInteractionEnabled=supported',bootstrap)
 def test_bridge_checks_value_type_and_size(self):
  s=(ROOT/'PhiMod/Sources/PMIL2CPP.hpp').read_text(encoding='utf-8')
  self.assertIn('class_value_size(c,&alignment)!=sizeof(T)',s)
  self.assertIn('checkClass<T>(class_from_type(field_get_type(f)))',s)
  self.assertIn('checkClass<T>(object_get_class(obj))',s)
if __name__=='__main__':unittest.main()