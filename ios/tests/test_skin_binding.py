from pathlib import Path
import unittest
R=Path(__file__).resolve().parents[1]/'PhiMod/Sources'
class SkinBinding(unittest.TestCase):
 def test_before_native_move_and_independent_visual_path(self):
  s=(R/'PMHookBackend.mm').read_text(encoding='utf-8')
  hold=s.split('void onHoldMove(',1)[1].split('template<h::Index',1)[0]
  self.assertLess(hold.index('beforeNoteMove'),hold.index('orig<VoidFn>(h::holdMove)'))
  self.assertNotIn('pmcontent::noteMoved(R(),self,true);pmfeatures::noteMoved',hold)
  tap=s.split('void onNoteMove(',1)[1].split('void onNormalStart',1)[0]
  self.assertLess(tap.index('beforeNoteMove'),tap.index('orig<VoidFn>(i)'))
 def test_serialized_hold_array_and_once_per_note(self):
  s=(R/'PMRuntimeFeatures.mm').read_text(encoding='utf-8')
  f=s.split('void beforeNoteMove(',1)[1].split('void* noteSprite',1)[0]
  self.assertIn('bound->second==note',f)
  self.assertIn('r.array_new(r.type("UnityEngine","Sprite"),3)',f)
  self.assertIn('r.put(c,"noteImages",replacement)',f)
  self.assertIn('r.put(c,"noteImage",sprite)',f)
  self.assertIn('skinBoundTypes.insert(type).second',f)
  self.assertIn('skinOriginalRoots[original]=r.gchandle_new(original,false)',f)
if __name__=='__main__':unittest.main()
