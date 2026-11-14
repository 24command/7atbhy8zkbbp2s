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
  self.assertIn('custom=frozenDifficulty(r,song)?:songFor(id,slot)',source)
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
  self.assertIn('Quad{cut,0,1,1},Quad{0,0,1,0}',page)
  hook=(ROOT/'PhiMod/Sources/PMHookBackend.mm').read_text('utf8')
  update=hook.split('void onSelector(',1)[1].split('void onSelectorOff(',1)[0]
  self.assertLess(update.index('difficultyInput'),update.index('orig<VoidFn>'))
  self.assertIn('if(!difficultyTouch)orig<VoidFn>',update)
if __name__=='__main__':unittest.main()
