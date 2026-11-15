from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
class SelectorDetails(unittest.TestCase):
 def test_initialize_all_before_native_update(self):
  s=(ROOT/'PhiMod/Sources/PMContentRuntime.mm').read_text(encoding='utf-8')
  block=s[s.index('void prepareSelectorItems('):s.index('// Native difficulty bars assume')]
  for text in ('for(int i=0;i<count;++i)','entry.first+1','<PlayableLevelCount>k__BackingField','<SelectorTargetWidth>k__BackingField','"SortSong"'):self.assertIn(text,block)
  hook=(ROOT/'PhiMod/Sources/PMHookBackend.mm').read_text(encoding='utf-8');block=hook[hook.index('void onSelector('):hook.index('void onSelectorOff(')]
  self.assertLess(block.index('prepareSelectorItems'),block.index('orig<VoidFn>'))
 def test_update_offscreen_lock_icons(self):
  s=(ROOT/'PhiMod/Sources/PMUnlockRuntime.mm').read_text(encoding='utf-8')
  block=s[s.index('void refreshListLocks('):s.index('void tick(')]
  for text in ('lastSlot!=slot','for(int i=0;i<count;++i)','"lockMask"','"selectorItemUpside"','"selectorItemDownside"','"unlockType",blocked?0:-1'):self.assertIn(text,block)
 def test_native_scroll_popup_and_isolated_click(self):
  s=(ROOT/'PhiMod/Sources/PMUnlockDetails.inc').read_text(encoding='utf-8')
  for text in ('"CreateMessageBox"','"ScrollRect"','"RectMask2D"','"set_content"','"set_verticalNormalizedPosition"','"Cancel"'):self.assertIn(text,s)
  self.assertNotIn('UIAlertController',s)
  button=s.split('void showRequirementButton(',1)[1].split('void openRequirementPopup(',1)[0]
  self.assertNotIn('"Instantiate"',button)
  self.assertNotIn('"startButton"',button)
  for marker in ('"set_targetGraphic"','"set_raycastTarget"','"set_ignoreParentGroups"','"set_blocksRaycasts"','"get_rect"','"TransformPoint"'):
   self.assertIn(marker,button)
  self.assertIn('\\u67e5\\u770b\\u89e3\\u9501\\u6761\\u4ef6',button)

  u=(ROOT/'PhiMod/Sources/PMUnlockRuntime.mm').read_text(encoding='utf-8');self.assertIn('showRequirementButton(r,tip,details)',u)
  self.assertIn('lockUIDetails=[tips componentsJoinedByString:@"\\n\\n"]',u)
 def test_native_polygon_and_scoped_touch_fallback(self):
  s=(ROOT/'PhiMod/Sources/PMUnlockDetails.inc').read_text(encoding='utf-8')
  self.assertIn('"Lean.Gui","LeanPolygon"',s)
  self.assertIn('float fill=-1,blur=1',s)
  self.assertIn('"get_InverseSlope"',s)
  self.assertIn('"ScreenPointToLocalPointInRectangle"',s)
  self.assertIn('"UnityEngine.Vector2&"',s)
  self.assertIn('r.unbox<RequirementTouch>',s)
  self.assertIn('if(count!=1){requirementTap.reset();return;}',s)
  self.assertIn('requirementTap.finish(',s)
  self.assertIn('requirementTouchItem==lockUIItem&&requirementTouchSlot==lockUISlot',s)
  self.assertIn('activateRequirement(r,"touch-fallback")',s)
  runtime=(ROOT/'PhiMod/Sources/PMUnlockRuntime.mm').read_text(encoding='utf-8')
  self.assertIn('pollRequirementInput(r,(P)selector)',runtime)
 def test_native_popup_is_not_cancelled_by_scroll_enhancement(self):
  s=(ROOT/'PhiMod/Sources/PMUnlockDetails.inc').read_text(encoding='utf-8')
  layout=s.split('void prepareRequirementScroll(',1)[1].split('void pollRequirementDialog(',1)[0]
  self.assertNotIn('r.call(popup,"Cancel")',layout)
  self.assertIn('native dialog retained',layout)
  self.assertIn('r.gchandle_new(task,false)',s)
  self.assertIn('requirementSeenShowing',s)
  self.assertIn('requirementPopupSince>2',s)
  self.assertIn('"ShowOkMessageBox"',s)
  opening=s.split('void openRequirementPopup(',1)[1].split('void activateRequirement(',1)[0]
  self.assertNotIn('prepareRequirementScroll(',opening)
  self.assertNotIn('"RefreshElements"',opening)
 def test_popup_does_not_reparent_native_text_or_duplicate_offsets(self):
  s=(ROOT/'PhiMod/Sources/PMUnlockDetails.inc').read_text(encoding='utf8')
  body=s.split('void prepareRequirementScroll(',1)[1].split('void requestRequirementFallback(',1)[0]
  self.assertIn('Unlock Requirements Body',body)
  self.assertIn('"set_ignoreLayout"',body)
  self.assertNotIn('r.call(stockTr,"SetParent"',s)
  self.assertNotIn('r.call(oldTr,"SetParent"',s)
  self.assertIn('readablePopupSize(width,height)',s)
  self.assertIn('"get_safeArea"',s)
  self.assertIn('requirementBodySize',s)
 def test_modal_blocks_raw_selector_and_background_buttons(self):
  hook=(ROOT/'PhiMod/Sources/PMHookBackend.mm').read_text(encoding='utf8')
  selector=hook.split('void onSelector(',1)[1].split('void onSelectorOff(',1)[0]
  self.assertLess(selector.index('selectorModalUpdate'),selector.index('orig<VoidFn>'))
  self.assertIn('||modal)return;',selector)
  self.assertIn('selectorButtonBlocked(R(),self)',hook.split('bool dispatchModButton(',1)[1].split('void onPress(',1)[0])
  runtime=(ROOT/'PhiMod/Sources/PMUnlockRuntime.mm').read_text(encoding='utf8')
  self.assertIn('selectorModalFrame(true,modal,pointerDown)',runtime)
  self.assertIn('"GetMouseButton"',runtime)
  detail=(ROOT/'PhiMod/Sources/PMUnlockDetails.inc').read_text(encoding='utf8')
  self.assertIn('"nowFingerId",-100',detail)
  self.assertIn('"startFingerPosition",-1000.f',detail)
  self.assertIn('if(!requirementPreviousDisabled)r.put(owner,"disableSongSelector",requirementPreviousDisabled)',detail)
  clear=detail.split('void clearRequirementUI(',1)[1].split('P requirementObject(',1)[0]
  self.assertIn('releaseRequirementInput(r)',clear)
class SparseDifficultyTests(unittest.TestCase):
 def test_repair_after_lock_update_and_restore_buttons(self):
  c=(ROOT/'PhiMod/Sources/PMContentRuntime.mm').read_text(encoding='utf8')
  h=(ROOT/'PhiMod/Sources/PMHookBackend.mm').read_text(encoding='utf8')
  f=h.split('void onSelector(',1)[1].split('void onSelectorOff(',1)[0]
  self.assertLess(f.index('pmunlock::tick'),f.index('selectorDifficultyUI'))
  self.assertIn('availableDifficulty(mask,level)',c)
  self.assertIn('bool enabled=available&&i!=slot',c)
  self.assertIn('sparseButtons.push_back({r.gchandle_new(button,false),previous,enabled})',c)
  self.assertIn('clearSparseButtons(r);',c.split('void selectorLoadingEnd(',1)[1])
  sparse=c.split('void selectorDifficultyUI(',1)[1].split('// Native difficulty bars assume',1)[0]
  self.assertIn('reconcileLogicalRows(r,selector)',sparse)
  rows=(ROOT/'PhiMod/Sources/PMSelectorRowPresentation.inc').read_text(encoding='utf8')
  self.assertIn('if(!present){maskRow(r,binding);continue;}',rows)
  self.assertIn('"HideInfo"',sparse)
  self.assertIn('sparseRevision==revision){maintainSparseSlots(r);reconcileDifficultyButtons(r,selector);return;}',sparse)
 def test_unlock_slot_refreshes_text_and_selection(self):
  s=(ROOT/'PhiMod/Sources/PMUnlockRuntime.mm').read_text(encoding='utf8')
  block=s.split('bool blocked=lockUIBlocked,playable=!blocked;',1)[1].split('P mask=',1)[0]
  self.assertLess(block.index('"unlockType"'),block.index('"SetText"'))
  self.assertIn('blocked?"Hide":"Show"',block)
 def test_compact_details_button(self):
  s=(ROOT/'PhiMod/Sources/PMUnlockDetails.inc').read_text(encoding='utf8')
  self.assertIn('std::clamp(bounds.w,210.f,250.f)',s)
  self.assertIn('bounds.w*.5f+48.f',s)
class LockedPreviewTests(unittest.TestCase):
 def test_preview_guard_survives_modal_and_restores_native_mute(self):
  runtime=(ROOT/'PhiMod/Sources/PMUnlockRuntime.mm').read_text(encoding='utf8')
  detail=(ROOT/'PhiMod/Sources/PMUnlockDetails.inc').read_text(encoding='utf8')
  self.assertIn('guardLockedPreview(r,item,blocked)',runtime)
  modal=runtime.split('bool selectorModalUpdate(',1)[1].split('bool selectorButtonBlocked(',1)[0]
  self.assertLess(modal.index('guardLockedPreview'),modal.index('pollRequirementDialog'))
  acquire=detail.split('void acquireRequirementInput(',1)[1].split('void clearRequirementScroll(',1)[0]
  self.assertLess(acquire.index('guardLockedPreview'),acquire.index('resetRequirementGesture(r,owner)'))
  release=runtime.split('void releaseLockedPreview(',1)[1].split('void guardLockedPreview(',1)[0]
  self.assertIn('lockedPreviewMute',release);self.assertIn('lockedAudioMute',release)
  self.assertNotIn('AudioListener',release)
  self.assertIn('void resetLockUI(Runtime&r){releaseLockedPreview(r)',runtime)
if __name__=='__main__':unittest.main()
