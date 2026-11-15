from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
def src(name):return (ROOT/'PhiMod/Sources'/name).read_text('utf8')
class SharedATSort(unittest.TestCase):
 def test_at_and_extra_share_list_without_name_filter(self):
  row=src('PMSelectorRowPresentation.inc')
  self.assertIn('context.slot==3?"AT+extra":"native"',row)
  self.assertNotIn('PMMatchingExtraDifficulty',row)
  self.assertNotIn('stockAT.find',row)
  self.assertIn('members->second.at(slot)',row)
  self.assertIn('PMDifficultyRecordLevel(chart)',row)
  self.assertIn('if(!present){maskRow(r,binding);continue;}',row)
 def test_silent_sort_uses_native_identity_and_never_setlevel(self):
  page=src('PMDifficultyPager.inc')
  flush=page.split('void finishDifficultySort(',1)[1].split('void restoreDifficultyBar(',1)[0]
  for token in ('deferredDifficultySort.ready','"fingerOnSongList"','"listMoveSpeed"','"SortSong"','target(r,keep)','"targetSong"','r.gchandle_free(keep)','listRowRefresh.invalidate()'):
   self.assertIn(token,flush)
  self.assertNotIn('"SetLevel"',flush)
  self.assertLess(flush.index('deferredDifficultySort.ready'),flush.index('"SortSong"'))
  bind=page.split('void bindTransport(',1)[1].split('void rebuildDifficultyEntries(',1)[0]
  self.assertIn('if(changed&&r.get<int>(selector,"nowLevel")==3)',bind)
  self.assertIn('deferredDifficultySort.request',bind)
 def test_new_sort_refreshes_rows_and_clears_on_scene_exit(self):
  runtime=src('PMContentRuntime.mm')
  end=runtime.split('void selectorLoadingEnd(',1)[1].split('void refreshVariantRecords(',1)[0]
  self.assertIn('deferredDifficultySort.clear()',end)
  ui=runtime.split('void selectorDifficultyUI(',1)[1].split('// Native difficulty bars assume',1)[0]
  self.assertLess(ui.index('finishDifficultySort'),ui.index('reconcileLogicalRows'))
  records=runtime.split('void refreshVariantRecords(',1)[1].split('void prepareSelectorItems(',1)[0]
  self.assertIn('PMDifficultyRecordLevel(member.second)',records)
 def test_official_lookup_does_not_clone_library_per_frame(self):
  query=src('PMContentRuntime.mm').split('NSDictionary*songFor(',1)[1].split('NSString*groupFor(',1)[0]
  self.assertIn('if(!byID||revision!=current)',query)
  self.assertIn('byID[identifier]',query)
if __name__=='__main__':unittest.main()
