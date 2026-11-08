from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
class MergedSelector(unittest.TestCase):
 def test_locked_difficulty_cannot_lock_navigation(self):
  s=(ROOT/'PhiMod/Sources/PMUnlockRuntime.mm').read_text(encoding='utf-8')
  self.assertNotIn('r.put(item,"<Unlocked>k__BackingField",!lockUIBlocked)',s)
  self.assertNotIn('r.put((P)item,"<Unlocked>k__BackingField",open)',s)
  self.assertIn('bool blocked=lockUIBlocked,playable=!blocked;',s)
  self.assertIn('"set_interactable",{"System.Boolean"},{&playable}',s)
  gate=s[s.index('bool beforeStart('):s.index('NSString*requirementName(')]
  self.assertIn('!opened(r,id)',gate)
  self.assertIn('Unlock start blocked',gate)
 def test_records_follow_each_chart_save_id(self):
  s=(ROOT/'PhiMod/Sources/PMContentRuntime.mm').read_text(encoding='utf-8')
  refresh=s[s.index('void refreshVariantRecords('):s.index('// Native difficulty bars assume')]
  self.assertIn('member.second[@"id"]',refresh)
  self.assertIn('"GetSongRecord",{"System.String","System.String"}',refresh)
  self.assertIn('"set_Item",{"System.Int32","LevelRecord"},{&slot,value}',refresh)
  self.assertNotIn('SetSongRecord',refresh)
  self.assertIn('r.call(selector,"SetText")',refresh)
  self.assertIn('recordRevision!=revision',s)
  cleanup=s[s.index('void selectorLoadingEnd('):s.index('void refreshVariantRecords(')]
  self.assertIn('recordSelector=recordItem=nullptr',cleanup)
if __name__=='__main__':unittest.main()
