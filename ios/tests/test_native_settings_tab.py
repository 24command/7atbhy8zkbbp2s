from pathlib import Path
import unittest
R=Path(__file__).resolve().parents[1]/'PhiMod/Sources'
class NativeSettingsTab(unittest.TestCase):
 def test_preserves_native_hierarchy(self):
  s=(R/'PMNativeModSettings.inc').read_text(encoding='utf8')
  self.assertIn('clone(r,go(r,sourceFrame),parent,nativeSettingsRoot)',s)
  for field in ('viewport','content','itemsHolder'):
   self.assertIn('mappedTransform(r,sourceTransform,cloneTransform,r.get<P>(original,"'+field+'"))',s)
  self.assertIn('"itemsHolder",holder',s)
  self.assertNotIn('"itemsHolder",content',s)
  self.assertIn('content==holder||viewport==holder',s)
  self.assertIn('get_childCount',s)
  self.assertNotIn('keepWorld',s)
 def test_registers_native_fourth_tab(self):
  s=(R/'PMNativeModSettings.inc').read_text(encoding='utf8')
  for field in ('frameAnimators','tabAnimators','tabScrollContents'):
   self.assertIn('r.put(setting,"'+field+'",appendSettingArray',s)
  self.assertIn('changeNativeTab(r,setting,nativeTabIndex)',s)
  self.assertIn('"RefreshPosition"',s)
  self.assertIn('"RefreshItems"',s)
 def test_exit_restores_original_arrays_before_destroy(self):
  s=(R/'PMNativeModSettings.inc').read_text(encoding='utf8')
  block=s.split('void clearNativeSettings(',1)[1].split('bool childPath(',1)[0]
  self.assertLess(block.index('changeNativeTab(r,setting,nativePreviousTab)'),block.index('r.put(setting,"frameAnimators"'))
  self.assertLess(block.index('r.put(setting,"tabScrollContents"'),block.index('dispose(r,nativeSettingsRoot,true)'))
  scene=(R/'PMSceneUI.mm').read_text(encoding='utf8')
  self.assertIn('if(nativeTabSwitch)return;',scene)
  self.assertIn('target(r,originalFrames)',scene)
  self.assertIn('restore(r,hidden,"SetActive");clearNativeSettings(r)',scene)
 def test_paths_resolved_before_removing_template_children(self):
  s=(R/'PMNativeModSettings.inc').read_text(encoding='utf8')
  self.assertLess(s.index('for(const char*field:{"previewNoteHolder"'),s.index('r.call(holder,"get_childCount")'))
 def test_independent_hit_surface_and_visible_failure(self):
  s=(R/'PMSceneUI.mm').read_text(encoding='utf8')
  self.assertIn('button=makeModTabHitTarget(r,obj)',s)
  self.assertIn('PhiModTabHitTarget',s)
  self.assertIn('"set_raycastTarget"',s)
  self.assertIn('"set_ignoreParentGroups"',s)
  self.assertIn('"set_maskable"',s)
  self.assertIn('reportModTabFailure(message)',s)
  self.assertIn('MOD tab click received',s)
 def test_optional_uikit_anchor_cannot_close_native_page(self):
  s=(R/'PMSceneUI.mm').read_text(encoding='utf8')
  press=s.split('bool press(Runtime&r,P button)',1)[1].split('namespace {uint32_t recoveryRoot',1)[0]
  self.assertNotIn('projectTab(r)',press)
  self.assertIn('if(!r.alive(canvas))return;',s)
  self.assertIn('if(nativeAdvanced){projectTab(r);[editor layoutEditor];}',s)
 def test_native_selection_readback_and_optional_preview_isolation(self):
  native=(R/'PMNativeModSettings.inc').read_text(encoding='utf8')
  self.assertIn('"currentTab")!=nativeTabIndex',native)
  self.assertIn('"get_activeInHierarchy"',native)
  self.assertIn('MOD settings revision 20261114-b',native)
  scene=(R/'PMSceneUI.mm').read_text(encoding='utf8')
  self.assertIn('MOD optional preview mute:',scene)
if __name__=='__main__':unittest.main()
