from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
class ExtraDifficultyRouting(unittest.TestCase):
 def test_plain_managed_items_do_not_use_unity_liveness(self):
  page=(ROOT/'PhiMod/Sources/PMDifficultyPager.inc').read_text('utf8')
  self.assertNotIn('r.alive(item)',page)
  self.assertIn('if(!item||!r.alive(bar)||!r.alive(slider))return;',page)
 def test_course_uses_frozen_chart_for_play_and_access(self):
  source=(ROOT/'PhiMod/Sources/PMContentRuntime.mm').read_text('utf8')
  unlock=(ROOT/'PhiMod/Sources/PMUnlockRuntime.mm').read_text('utf8')
  self.assertIn('frozenDifficulty(r,song)?:songFor(id,slot)',source)
  self.assertIn('subject=pmcontent::difficultyForSong(r,song,slot)',unlock)
  page=(ROOT/'PhiMod/Sources/PMDifficultyPager.inc').read_text('utf8')
  self.assertIn('queuedSongs.count(target(r,it->root))',page)
  self.assertIn('r.arrayPutFloat(cloned,slot,number)',page)
 def test_no_expansion_of_native_slot_arrays_or_shader_changes(self):
  page=(ROOT/'PhiMod/Sources/PMDifficultyPager.inc').read_text('utf8')
  self.assertIn('if(slot<0||slot==3)',page)
  self.assertIn('difficultyEntries.size(),difficultyPage',page)
  self.assertIn('members.count(slot)?members[slot]:nil',page)
  self.assertIn('r.call(slider,"JumpToLevel"',page)
  self.assertIn('r.call(info,"UpdatePosition"',page)
  self.assertIn('PMDifficultyRecordLevel(chart)',page)
  self.assertIn('@"%@ Lv.%@"',page)
  label=page.split('void difficultyGameplayLabel(',1)[1]
  self.assertIn('"set_text"',label)
  for setter in ('set_localScale','set_position','set_color','set_material'):
   self.assertNotIn(setter,label)
 def test_selection_and_exit_restore_native_state(self):
  page=(ROOT/'PhiMod/Sources/PMDifficultyPager.inc').read_text('utf8')
  transaction=page.split('void selectExistingDifficulty(',1)[1].split('void restoreDifficultyBar(',1)[0]
  self.assertLess(transaction.index('"levelNum"'),transaction.index('"SetLevel"'))
  self.assertLess(transaction.index('"fingerOnSongList",false'),transaction.index('"SetLevel"'))
  self.assertIn('"fingerOnSongList",finger',transaction)
  self.assertIn('restoreDifficultyBar(r,previousOwner)',page)
  self.assertIn('r.call(bar,"UpdateInfoImmediately"',page)
  self.assertIn('r.call(info,"SetActive"',page)
 def test_touch_is_scoped_and_does_not_drag_song_list(self):
  page=(ROOT/'PhiMod/Sources/PMDifficultyPager.inc').read_text('utf8')
  self.assertIn('RectangleContainsScreenPoint',page)
  self.assertIn('difficultyTap.finish',page)
  self.assertIn('difficultyTouchEntry=-1',page)
  self.assertIn('Quad{cut,0,0,1},Quad{0,0,1,1},Quad{-cut,0,1,0}',page)
  hook=(ROOT/'PhiMod/Sources/PMHookBackend.mm').read_text('utf8')
  update=hook.split('void onSelector(',1)[1].split('void onSelectorOff(',1)[0]
  self.assertLess(update.index('difficultyInput'),update.rindex('orig<VoidFn>'))
  self.assertIn('if(!difficultyTouch)orig<VoidFn>',update)
  # Covered initialization calls a separate deferred trampoline with raw input disabled.
  coordinator=(ROOT/'PhiMod/Sources/PMNativeOSCoordinator.mm').read_text('utf8')
  staged=coordinator.split('bool stageSelector(',1)[1].split('void detach(',1)[0]
  self.assertLess(staged.index('r.put(owner,"disableSongSelector",true)'),staged.index('if(nativeUpdate)nativeUpdate()'))
  self.assertNotIn('difficultyInput(',staged)
  self.assertGreater(staged.index('pmcontent::difficultyTransitionLabel'),staged.index('if(nativeUpdate)nativeUpdate()'))

 def test_transition_and_result_display_use_metadata_not_numeric_transport(self):
  page=(ROOT/'PhiMod/Sources/PMDifficultyPager.inc').read_text('utf8')
  transition=page.split('void difficultyTransitionLabel(',1)[1].split('void difficultyResultLabel(',1)[0]
  self.assertIn('r.get<P>(selector,"level"),PMDifficultyName',transition)
  self.assertIn('r.get<P>(selector,"difficulty"),PMDifficultyText',transition)
  self.assertNotIn('PMDifficultyNumber',transition)
  hook=(ROOT/'PhiMod/Sources/PMHookBackend.mm').read_text('utf8')
  start=hook.split('void onNormalStart(',1)[1].split('using MainlineCheckFn',1)[0]
  self.assertEqual(start.count('difficultyTransitionLabel'),2)
  selector=hook.split('void onSelector(',1)[1].split('void onSelectorOff(',1)[0]
  self.assertGreater(selector.index('difficultyTransitionLabel'),selector.rindex('orig<VoidFn>'))
 def test_current_chart_reconciles_cached_button_restoration(self):
  source=(ROOT/'PhiMod/Sources/PMContentRuntime.mm').read_text('utf8')
  self.assertIn('maintainSparseSlots(r);reconcileDifficultyButtons(r,selector);return;',source)
  page=(ROOT/'PhiMod/Sources/PMDifficultyPager.inc').read_text('utf8')
  self.assertIn('void restoreDifficultyBar(Runtime&r,P selector){\n clearSparseButtons(r);',page)
  reconcile=page.split('void reconcileDifficultyButtons(',1)[1].split('void selectExistingDifficulty(',1)[0]
  self.assertIn('nativeDifficultyMask(r,r.at(items,index))',reconcile)
  self.assertIn('i!=slot',reconcile)
 def test_automatic_selection_is_silent_and_defers_sort_until_release(self):
  page=(ROOT/'PhiMod/Sources/PMDifficultyPager.inc').read_text('utf8')
  selection=page.split('void selectExistingDifficulty(',1)[1].split('void finishDifficultySort(',1)[0]
  self.assertIn('deferredDifficultySort.request',selection)
  self.assertIn('bool userInitiated',selection)
  self.assertEqual(selection.count('"SetLevel"'),1)
  self.assertIn('if(userInitiated){r.put(selector,"fingerOnSongList",false);try{r.call(selector,"SetLevel"',selection)
  self.assertNotIn('"SortSong"',selection)
  self.assertIn('selectExistingDifficulty(r,selector,item,slot,true)',page)
  self.assertIn('clearDifficultyPager(r,false);clearSparseButtons(r)',page)
 def test_variant_cover_uses_native_transition_only_after_settling(self):
  source=(ROOT/'PhiMod/Sources/PMContentRuntime.mm').read_text('utf8')
  frame=source.split('void selectorLoadingFrame(',1)[1].split('P sparseSelector=',1)[0]
  self.assertLess(frame.index('selectionChangedAt<.30'),frame.index('updateVariantCover'))
  cover=source.split('void updateVariantCover(',1)[1].split('void completeSelectorAsset(',1)[0]
  self.assertIn('"SetImageWithTransition"',cover)
  self.assertIn('chart[@"id"]',cover)
  self.assertIn('state->appliedKey',cover)
  self.assertIn('r.get<P>(cover,"newCode")',cover)
  self.assertNotIn('r.put(item,"coverBlurAssetCode"',cover)
  self.assertIn('clearVariantCovers(r)',source.split('void selectorLoadingEnd(',1)[1])
if __name__=='__main__':unittest.main()
