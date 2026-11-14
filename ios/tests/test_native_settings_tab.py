from pathlib import Path
import unittest
R=Path(__file__).resolve().parents[1]/'PhiMod/Sources'
class NativeSettingsTab(unittest.TestCase):
 def setUp(self):
  self.native=(R/'PMNativeModSettings.inc').read_text('utf8')
  self.scene=(R/'PMSceneUI.mm').read_text('utf8')
 def test_fresh_page_preserves_original_canvas_and_arrays(self):
  s=self.native
  self.assertIn('nativeRectObject(r,"PhiMod Settings Page",canvasTr,false)',s)
  self.assertNotIn('clone(r,',s)
  self.assertNotIn('appendSettingArray',s)
  for name in ('frameAnimators','tabAnimators','tabScrollContents'):
   self.assertNotIn('r.put(setting,"'+name+'"',s)
  self.assertIn('changeNativeTab(r,setting,0)',s)
  self.assertNotIn('changeNativeTab(r,setting,3)',s)
 def test_independent_scroll_uses_distinct_content_and_holder(self):
  s=self.native
  for name in ('Viewport','Content','Items'):self.assertIn('"'+name+'"',s)
  self.assertIn('"itemsHolder",holder',s)
  self.assertNotIn('"itemsHolder",content',s)
  self.assertIn('"RectMask2D"',s)
  self.assertIn('"set_vertical"',s)
  self.assertIn('"set_movementType"',s)
 def test_no_native_diagonal_layout_or_row_position_accumulation(self):
  s=self.native
  for name in ('AddButton','AddToggle','AddSlider'):self.assertIn('"'+name+'"',s)
  self.assertNotIn('"RefreshItems"',s)
  self.assertNotIn('"RefreshPosition"',s)
  self.assertIn('phimod::modSettingsLayout(rect.w,rect.h,heights)',s)
  self.assertIn('nativeTopRect(r,rowRect,box.x,box.y,-2*box.x,box.height)',s)
  self.assertIn('layout.contentHeight',s)
 def test_only_body_branches_can_be_hidden(self):
  s=self.native
  self.assertIn('Cannot hide settings root Canvas',s)
  self.assertIn('Cannot hide settings navigation',s)
  self.assertIn('"StaticFrameContainer"',s)
  press=self.scene.split('bool press(Runtime&r,P button)',1)[1]
  self.assertNotIn('target(r,originalFrames)',press)
  self.assertNotIn('stash(r,hidden,go(r,r.arrayAt(frames',press)
 def test_cleanup_restores_bodies_header_and_previous_native_tab(self):
  block=self.native.split('void clearNativeSettings(',1)[1].split('P nativeTitle(',1)[0]
  self.assertLess(block.index('dispose(r,nativeSettingsRoot,true)'),block.index('restore(r,nativeBodies,"SetActive")'))
  self.assertIn('restore(r,nativeHeaderAnimations,"set_enabled")',block)
  self.assertIn('changeNativeTab(r,owner,previous)',block)
  self.assertIn('nativeHeaderLabels.clear()',block)
  self.assertIn('}catch(...){clearNativeSettings(r);throw;}',self.native)
 def test_original_navigation_slider_drives_mod_selection(self):
  self.assertIn('"sliderController"',self.native)
  self.assertIn('"MoveTo"',self.native)
  self.assertIn('nativeHeaderPlaced',self.native)
  self.assertIn('nativePreviewObjects',self.native)
  self.assertIn('nativePreviewMute',self.native)
  hook=(R/'PMHookBackend.mm').read_text('utf8')
  self.assertIn('if(!pmscene::settingsPreviewSuspended(R(),self))orig<VoidFn>',hook)
  self.assertIn('for(const char*field:{"previewNoteHolder","judgeLine","clickPosition"})',self.native)
  self.assertIn('"judgeLine"',self.native)
  self.assertIn('restore(r,nativePreviewObjects,"SetActive")',self.native)
  self.assertIn('positionNativeHeader(r)',self.native)
  self.assertIn('stash(r,nativeHeaderAnimations,r.arrayAt(tabs,i)',self.native)
 def test_scroll_resize_preserves_scroll_position(self):
  self.assertIn('get_verticalNormalizedPosition',self.native)
  self.assertIn('force?1.f:std::clamp(normalized,0.f,1.f)',self.native)
  self.assertIn('std::fabs(rect.w-nativeLayoutSize.x)<.5f',self.native)
 def test_native_row_titles_are_constrained_to_control_bounds(self):
  for name in ('set_offsetMin','set_offsetMax','set_resizeTextForBestFit','set_resizeTextMinSize','set_resizeTextMaxSize'):
   self.assertIn('"'+name+'"',self.native)
  self.assertIn('row.kind==1?-180.f:-32.f',self.native)
 def test_independent_hit_surface_and_visible_failure(self):
  for marker in ('button=makeModTabHitTarget(r,obj)','PhiModTabHitTarget','"set_raycastTarget"','"set_ignoreParentGroups"','reportModTabFailure(message)'):
   self.assertIn(marker,self.scene)
  for marker in ('pollModTabTouch','RectangleContainsScreenPoint','tabTap.finish','modTabPopupShowing','MOD page stable'):self.assertIn(marker,self.native)
 def test_optional_advanced_editor_does_not_drive_native_page_layout(self):
  press=self.scene.split('bool press(Runtime&r,P button)',1)[1].split('namespace {uint32_t recoveryRoot',1)[0]
  self.assertNotIn('projectTab(r)',press)
  self.assertIn('if(nativeAdvanced){projectTab(r);[editor layoutEditor];}',self.scene)
  self.assertIn('if(nativeAdvanced&&editor.hidden)',self.native)
 def test_external_fourth_tab_routes_before_cleanup(self):
  hook=(R/'PMHookBackend.mm').read_text('utf8')
  self.assertIn('if(pmscene::settingsTabRequest(R(),self,index))return;',hook)
  route=self.scene.split('bool settingsTabRequest(',1)[1].split('void settingsLeave(',1)[0]
  self.assertLess(route.index('SettingsTabRoute::KeepMod'),route.index('settingsLeave('))
  self.assertIn('if(nativeTabSwitch)return;',self.scene)
 def test_qualified_rectangle_and_build_identification(self):
  self.assertIn('sceneimpl::Rect rect=r.unbox<sceneimpl::Rect>',self.native)
  self.assertNotIn('Rect rect=r.unbox<Rect>',self.native)
  self.assertIn('phimod::settingsRevision',self.native)
  self.assertIn('restored exactly once',self.scene)
 def test_original_tab_backdrop_still_extends(self):
  for marker in ('r.get<P>(layout,"background")','tabBackdropPosition.x+=extra*pivot.x','tab.r+std::fabs(area.h)*.27f+12.f'):self.assertIn(marker,self.native)
  self.assertIn('extendTabBackdrop(r)',self.scene)
if __name__=='__main__':unittest.main()
