from pathlib import Path
import unittest
R=Path(__file__).resolve().parents[1]/'PhiMod/Sources'
class NativeSettingsTab(unittest.TestCase):
 def test_preserves_native_hierarchy(self):
  s=(R/'PMNativeModSettings.inc').read_text(encoding='utf8')
  self.assertIn('clone(r,go(r,sourceFrame),transform(r,staging),nativeSettingsRoot)',s)
  for field in ('viewport','content','itemsHolder'):
   self.assertIn('r.get<P>(original,"'+field+'")',s)
   self.assertIn('followSettingsPath(r,cloneTransform,templatePaths',s)
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
  self.assertIn('phimod::settingsRevision',native)
  scene=(R/'PMSceneUI.mm').read_text(encoding='utf8')
  self.assertIn('MOD optional preview mute:',scene)
 def test_external_fourth_tab_routes_before_cleanup(self):
  s=(R/'PMHookBackend.mm').read_text(encoding='utf8')
  hook=s.split('void onSettingTab(',1)[1].split('void onSettingBack(',1)[0]
  self.assertIn('if(pmscene::settingsTabRequest(R(),self,index))return;',hook)
  self.assertNotIn('pmscene::settingsLeave',hook)
  scene=(R/'PMSceneUI.mm').read_text(encoding='utf8')
  route=scene.split('bool settingsTabRequest(',1)[1].split('void settingsLeave(',1)[0]
  self.assertLess(route.index('SettingsTabRoute::KeepMod'),route.index('settingsLeave('))
  self.assertIn('owner==target(r,settingRoot)',route)
 def test_touch_fallback_and_loaded_build_identification(self):
  native=(R/'PMNativeModSettings.inc').read_text(encoding='utf8')
  for marker in ('pollModTabTouch','RectangleContainsScreenPoint','tabTap.finish','modTabPopupShowing','MOD page stable'):
   self.assertIn(marker,native)
  scene=(R/'PMSceneUI.mm').read_text(encoding='utf8')
  self.assertIn('MOD page leave reason=',scene)
  hook=(R/'PMHookBackend.mm').read_text(encoding='utf8')
  self.assertIn('reportRuntimeBuild()',hook)
  self.assertIn('image.dli_fname',hook)
  self.assertIn('MOD settings update failed:',hook)
 def test_diagnostic_rect_does_not_collide_with_apple_rect(self):
  native=(R/'PMNativeModSettings.inc').read_text(encoding='utf8')
  self.assertIn('sceneimpl::Rect rect=r.unbox<sceneimpl::Rect>',native)
  self.assertNotIn('Rect rect=r.unbox<Rect>',native)
 def test_mod_page_does_not_inherit_hidden_gameplay_pose(self):
  native=(R/'PMNativeModSettings.inc').read_text(encoding='utf8')
  self.assertIn('sourceIsRootCanvas=sameNativeTransform',native)
  self.assertIn('nativeRectRegion(r,cloneTransform,bodyRegion)',native)
  self.assertLess(native.index('copiedAnimators=r.children'),native.index('P addButton='))
  self.assertIn('for(int index:{1,2})',native)
  self.assertIn('"get_content")==expectedContent',native)
  self.assertIn('if(scrollTransform!=cloneTransform)',native)
  self.assertIn('if(viewport==cloneTransform)',native)
  self.assertIn('for(P item:{content,holder})',native)
  self.assertIn('nativeManualLayout(r,cloneTransform)',native)
  self.assertIn('restoreNativePageGraphics(r)',native)
  self.assertNotIn('rowItems=r.children',native)
  self.assertIn('nativePageGraphics.push_back',native)
 def test_frame_is_attached_above_all_original_tabs(self):
  native=(R/'PMNativeModSettings.inc').read_text(encoding='utf8')
  self.assertIn('phimod::settingsFrameHost(frameTransforms',native)
  self.assertNotIn('Shared native settings frame host not found',native)
  self.assertIn('sameNativeTransform(r,a,b)',native)
  self.assertNotIn('if(!rectHost)',native)
  self.assertNotIn('set_renderMode',native)
  self.assertIn('cloneGraphics=r.children',native)
  self.assertIn('get_rootCanvas',native)
  self.assertIn('PhiMod Settings Frame',native)
  self.assertIn('frameLayer=std::min(frameLayer,path.back()+1)',native)
  self.assertIn('"SetSiblingIndex"',native)
  self.assertNotIn('sourceTransform=transform(r,sourceFrame),parent=r.call(sourceTransform,"get_parent")',native)
 def test_original_backdrop_extends_to_mod_tab(self):
  native=(R/'PMNativeModSettings.inc').read_text(encoding='utf8')
  self.assertIn('r.get<P>(layout,"background")',native)
  self.assertIn('tabBackdropPosition.x+=extra*pivot.x',native)
  self.assertIn('tab.r+std::fabs(area.h)*.27f+12.f',native)
  scene=(R/'PMSceneUI.mm').read_text(encoding='utf8')
  self.assertIn('extendTabBackdrop(r)',scene)
  self.assertIn('clearTabBackdrop(r);dispose(r,tabRoot,true)',scene)
 def test_mapping_precedes_clone_and_callback_mutation(self):
  s=(R/'PMNativeModSettings.inc').read_text(encoding='utf8')
  self.assertLess(s.index('templatePaths;'),s.index('root=clone(r,go(r,sourceFrame)'))
  self.assertLess(s.index('active(r,staging,false)'),s.index('root=clone(r,go(r,sourceFrame)'))
  self.assertIn('index<0||index>=count',s)
  self.assertIn('std::vector<uint32_t>oldRows',s)
  self.assertLess(s.index('oldRows.push_back'),s.index('for(uint32_t saved:oldRows)'))
 def test_root_canvas_clone_preserves_native_scaler_and_content_width(self):
  native=(R/'PMNativeModSettings.inc').read_text(encoding='utf8')
  self.assertIn('sourceIsRootCanvas?r.call(transform(r,canvasRoot),"get_parent")',native)
  self.assertIn('bool enable=sourceIsRootCanvas&&sameNativeTransform',native)
  self.assertIn('if(!keep)active(r,go(r,branch),false)',native)
  self.assertLess(native.index('if(!keep)active(r,go(r,branch),false)'),native.index('active(r,root,true)'))
  self.assertIn('else{nativeManualLayout(r,cloneTransform);nativeRectRegion',native)
  self.assertIn('V2 min{0,1},max{1,1}',native)
  self.assertNotIn('set_anchorMax",{"UnityEngine.Vector2"},{&topLeft}',native)
  self.assertIn('contentRect.w<=0||holderRect.w<=0',native)
  self.assertIn('"get_sortingOrder"))+1',native)
if __name__=='__main__':unittest.main()
