from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
class ChallengeAccess(unittest.TestCase):
 def test_chapter_filter_uses_parent_and_membership(self):
  s=(ROOT/'PhiMod/Sources/PMUnlockRuntime.mm').read_text(encoding='utf-8')
  hidden=s[s.index('bool hiddenByChapter('):s.index('uint32_t aggregateOwner=')]
  self.assertIn('chapterBlocked(r,group,subject)',hidden)
  self.assertNotIn('opened(r,subject[@"id"])',hidden)
  access=s[s.index('bool selectorAccess('):s.index('bool blockChallengeButton(')]
  self.assertIn('"RemoveAt"',access);self.assertIn('"Add",{"SongSelectorItem"}',access)
  self.assertIn('restoreChallengeButtons(r)',access)
  self.assertIn('if(r.count(items)==0)',access)
 def test_buttons_recheck_selected_and_all_queued_slots(self):
  s=(ROOT/'PhiMod/Sources/PMUnlockRuntime.mm').read_text(encoding='utf-8')
  guard=s[s.index('bool blockChallengeButton('):s.index('void tick(')]
  for text in ('"selectButton"','"playButton"','"challengeSongItems"','"levelIndex"','"nowLevel"'):self.assertIn(text,guard)
  hook=(ROOT/'PhiMod/Sources/PMHookBackend.mm').read_text(encoding='utf-8')
  block=hook.split('void onSelector(',1)[1].split('void onSelectorOff(',1)[0]
  self.assertIn('access=pmunlock::selectorAccess(R(),self)',block)
  self.assertIn('||!access){pmnativecoordinator::abortSelectorEntry(R());return;}',block)
  self.assertLess(block.index('||!access){pmnativecoordinator::abortSelectorEntry(R());return;}'),block.index('orig<VoidFn>'))
  self.assertIn('if(pmunlock::blockChallengeButton(R(),self))return true;',hook)
  self.assertIn('if(pmunlock::blockChallengeButton(R(),self))return;',hook)
  self.assertIn('if(!dispatchModButton(self))orig',hook)
 def test_navigation_remains_independent(self):
  s=(ROOT/'PhiMod/Sources/PMUnlockRuntime.mm').read_text(encoding='utf-8')
  self.assertIn('r.put(item,"<Unlocked>k__BackingField",true)',s)
  self.assertIn('bool blocked=lockUIBlocked,playable=!blocked;',s)
if __name__=='__main__':unittest.main()
