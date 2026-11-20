from pathlib import Path
import unittest,json
ROOT=Path(__file__).resolve().parents[1]
def source(name):return (ROOT/'PhiMod/Sources'/name).read_text(encoding='utf-8')
class ManagementResources(unittest.TestCase):
 def test_export_callbacks_only_remove_internal_copies(self):
  ui=source('PMContentUI.mm');store=source('PMTrashStore.inc')
  self.assertIn('share.completionWithItemsHandler=',ui)
  self.assertIn('self.pendingExports=@[url];p.delegate=self',ui)
  self.assertIn('if(self.pendingExports)',ui)
  self.assertIn('path.stringByDeletingLastPathComponent isEqualToString:base',store)
 def test_search_dismisses_whole_picker(self):
  s=source('PMUnlockEditor.mm');self.assertIn('container=self.navigationController?:self',s)
  self.assertIn('[presenter dismissViewControllerAnimated:YES completion:',s)
 def test_low_opacity_is_session_only(self):
  s=source('PMSettings.mm');self.assertIn('@"opacity":@[@0,@1]',s)
  self.assertIn('if(opacity&&[opacity doubleValue]<0.15)',s)
  snapshot=s[s.index('- (NSDictionary *)snapshot'):s.index('- (BOOL)validateSnapshot')]
  self.assertNotIn('setObject:',snapshot)
 def test_native_settings_use_game_factories(self):
  s=source('PMNativeModSettings.inc')
  for name in ('AddToggle','AddSlider','AddButton'):self.assertIn('"'+name+'"',s)
  self.assertIn('UnityEngine.Events.UnityAction<System.Boolean>[]',s)
 def test_skin_extras_really_have_hooks(self):
  manifest=json.loads((ROOT/'tools/gameplay_hook_manifest.json').read_text())
  self.assertEqual(len(manifest),74)
  self.assertEqual({x['id'] for x in manifest[68:72]},{'skinInstantiate','skinSoundHit','skinSoundNA','skinSoundUnity'})
  fx=source('PMPackEffects.inc');runtime=source('PMRuntimeFeatures.mm')
  self.assertIn('PlayOneShot',runtime);self.assertIn('skinEffectCreated',runtime)
  self.assertIn('updatePackEffects(r)',runtime);self.assertIn('PMConvertAudioResource',fx)
  self.assertIn('line.png',fx);self.assertIn('styleLine(r,renderer)',source('PMContentRuntime.mm'))
  self.assertIn('clearPackExtras(r)',runtime)
if __name__=='__main__':unittest.main()
