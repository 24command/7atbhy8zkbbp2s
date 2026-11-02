import unittest
from pathlib import Path
class HoldIdentity(unittest.TestCase):
 def test_source_binding_precedes_native_information(self):
  root=Path(__file__).resolve().parents[1]/'PhiMod/Sources'
  h=(root/'PMHookBackend.mm').read_text(encoding='utf-8')
  block=h.split('void onLevelInformation(',1)[1].split('void onAssetCtor',1)[0]
  self.assertLess(block.index('pmcontent::beforeInformation'),block.index('orig<VoidFn>(h::levelInfo)'))
  c=(root/'PMContentRuntime.mm').read_text(encoding='utf-8')
  post=c.split('void afterChart(',1)[1].split('void beforeInformation',1)[0]
  self.assertIn('for(const auto&entry:extras)',post)
  self.assertNotIn('real[j]',post)
  self.assertIn('[source[@"type"] intValue]==3',post)
  self.assertIn('liveHold&&!r.get<bool>(controlObject,"missed")',c)
  self.assertIn('_holdHeadIsDestroyed',c)
 def test_reordered_notes_keep_own_duration(self):
  mapping={'long':8.0,'short':0.5,'medium':3.0}
  reordered=['short','medium','long']
  self.assertEqual([mapping[x] for x in reordered],[0.5,3.0,8.0])
if __name__=='__main__':unittest.main()
