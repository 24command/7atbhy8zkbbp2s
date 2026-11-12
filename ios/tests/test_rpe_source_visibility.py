from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
class SourceVisibility(unittest.TestCase):
 def test_recovery_uses_world_geometry_not_time_horizon(self):
  s=(ROOT/'PhiMod/Sources/PMContentRuntime.mm').read_text(encoding='utf8')
  recovery=s.split('void recoverSourceNotes(',1)[1].split('void visuals(',1)[0]
  self.assertNotIn('if(start>now+8)',recovery)
  self.assertNotIn('>30)continue',recovery)
  self.assertIn('sourceVisualNear(',recovery)
  self.assertIn('sourceCandidatesReady',recovery)
  self.assertIn('r.at(side,index)!=note',recovery)
  self.assertIn('!r.get<bool>(note,"isJudged")',recovery)
 def test_fake_and_real_share_geometry_gate(self):
  s=(ROOT/'PhiMod/Sources/PMContentRuntime.mm').read_text(encoding='utf8')
  self.assertNotIn('.start-8<=now',s)
  self.assertIn('sourceVisualNear(r,pose->second,f.note',s)
  near=s.split('bool sourceVisualNear(',1)[1].split('void recoverSourceNotes(',1)[0]
  for name in ('pmVisible','pmAlpha','sourceNotesHidden','rpeCovered','rpeGeometry','rpeHorizontalPosition','alphaControl','yControl','sizeControl'):
   self.assertIn(name,near)
 def test_source_time_cache_reset_at_teardown(self):
  s=(ROOT/'PhiMod/Sources/PMContentRuntime.mm').read_text(encoding='utf8')
  self.assertIn('sourceCandidates.clear();sourceCandidatesReady=false;',s)
if __name__=='__main__':unittest.main()
