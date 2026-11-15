from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
def src(name):return (ROOT/'PhiMod/Sources'/name).read_text('utf8')
class SelectorRefreshCost(unittest.TestCase):
 def test_steady_frames_do_not_visit_full_list(self):
  rows=src('PMSelectorRowPresentation.inc')
  self.assertIn('r.get<int>(context.items,"_version")',rows)
  branch=rows.split('if(logicalChanged){',1)[1]
  steady=branch.split('}else{',1)[1]
  self.assertNotIn('i<context.count',steady)
  self.assertIn('dirty.insert(context.selectedItem)',steady)
  self.assertIn('listRowRefresh.previousSelected()',steady)
  self.assertIn('for(P item:dirty)update(item)',steady)
  restore=rows.split('void restoreSelectorRowVisibility(',1)[1]
  self.assertLess(restore.index('if(!nativeRefresh&&!listRowRefresh.full(context.key))return'),restore.index('restoreRowMask'))
 def test_unlock_updates_invalidate_changed_rows_and_preserve_offscreen_state(self):
  unlock=src('PMUnlockRuntime.mm');body=unlock.split('void refreshListLocks(',1)[1].split('void tick(',1)[0]
  self.assertIn('lastVersion!=version',body)
  self.assertIn('lastSceneEpoch!=listLockSceneEpoch',body)
  self.assertIn('time-lastTime>=1',body)
  self.assertIn('for(auto&pair:cache)',body)
  self.assertIn('if(changed)paint(item,entry)',body)
  self.assertIn('pmcontent::invalidateSelectorRow(item)',body)
  self.assertIn('cache.find(selectedItem)',body)
  self.assertEqual(body.count('for(int i=0;i<count;++i)'),1)
 def test_library_queries_use_index_and_sparse_bar_uses_selected_song(self):
  unlock=src('PMUnlockRuntime.mm')
  entity=unlock.split('NSDictionary*entity(',1)[1].split('NSDictionary*ruleFor(',1)[0]
  self.assertIn('unlockEntities[id]',entity);self.assertIn('unlockSongGroups[id]',entity)
  self.assertNotIn('db[@"songs"]',entity)
  chapter=unlock.split('bool chapterBlocked(',1)[1].split('bool chartBlocked(',1)[0]
  self.assertIn('unlockChaptersBySong[group]',chapter)
  self.assertNotIn('unlockLibrary()[@"chapters"]',chapter)
  runtime=src('PMContentRuntime.mm');ui=runtime.split('void selectorDifficultyUI(',1)[1].split('// Native difficulty bars assume',1)[0]
  self.assertNotIn('for(int j=0;j<count',ui)
  prepare=runtime.split('void prepareSelectorItems(',1)[1].split('// Reassert sparse-slot',1)[0]
  self.assertNotIn('initializedSlot==slot',prepare)
if __name__=='__main__':unittest.main()
