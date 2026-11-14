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
  self.assertIn('sourceVisualNear(r,pose->second,f.visual',s)
  near=s.split('bool sourceVisualNear(',1)[1].split('void recoverSourceNotes(',1)[0]
  for name in ('rpeVisibleAt','rpeCovered','rpeGeometry','rpeHorizontalPosition','alphaControl','yControl','sizeControl'):
   self.assertIn(name,near)
 def test_source_time_cache_reset_at_teardown(self):
  s=(ROOT/'PhiMod/Sources/PMContentRuntime.mm').read_text(encoding='utf8')
  self.assertIn('sourceCandidates.clear();sourceCandidatesReady=false;',s)
 def test_cached_scheduler_preserves_far_future_and_rewind(self):
  s=(ROOT/'PhiMod/Sources/PMContentRuntime.mm').read_text(encoding='utf8')
  block=s.split('void recoverSourceNotes(',1)[1].split('void visuals(',1)[0]
  self.assertIn('rpeFirstUnexpired(sourceCandidates,now-.25)',block)
  self.assertIn('sourceVisual(n)',block)
  self.assertIn('if(controlObject&&r.get<bool>(controlObject,"isVisible"))continue;',block)
  self.assertIn('int previousCount=r.count(controls)',block)
  near=s.split('bool sourceVisualNear(',1)[1].split('void recoverSourceNotes(',1)[0]
  self.assertNotIn('scalar(',near)
  self.assertNotIn('notePerspectiveWidth(',near)
  self.assertNotIn('trackValue(',near)
  self.assertNotIn('if(start>now+8)',block)
 def test_spatial_index_retains_precise_gate_and_due_notes(self):
  s=(ROOT/'PhiMod/Sources/PMContentRuntime.mm').read_text('utf8')
  recovery=s.split('void recoverSourceNotes(',1)[1].split('void visuals(',1)[0]
  self.assertIn('index.floors.query(low,high,emit);index.due.query(now,now,emit)',recovery)
  self.assertIn('else for(size_t i:index.all)emit(i)',recovery)
  self.assertIn('line.incline==0',recovery)
  self.assertIn('recoveryUnitControl(line.yControl)',recovery)
  self.assertIn('recoveryUnitControl(line.sizeControl)',recovery)
  self.assertIn('sourceVisualNear(',recovery)
  self.assertIn('sourceRecoveryIndexes.clear();sourceRecoveryWork.clear();',s)
  self.assertIn('index.all.back()<firstIndex',recovery)
if __name__=='__main__':unittest.main()
