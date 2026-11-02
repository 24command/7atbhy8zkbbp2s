from pathlib import Path
import unittest
class StoryOrder(unittest.TestCase):
 def test_rank_and_notes_above(self):
  values=[0,-5,0,-5,100,-100]
  order=sorted(range(len(values)),key=lambda i:values[i])
  self.assertEqual(order,[5,1,3,0,2,4])
  ranks={i:3+2*k for k,i in enumerate(order)}
  self.assertGreaterEqual(min(ranks.values()),3)
  for count in (61,374,700,2048):self.assertGreater(max(1028,5+count*2),3+(count-1)*2)
 def test_runtime_no_signed_order_offset(self):
  s=(Path(__file__).resolve().parents[1]/'PhiMod/Sources/PMContentRuntime.mm').read_text(encoding='utf-8')
  self.assertNotIn('int order=base+',s)
  self.assertIn('storyOrders[ordered[rank]]=3+int(rank)*2',s)
  self.assertIn('int order=hold?storyHoldOrder:storyNoteOrder',s)
  self.assertIn('int order=type==3?storyHoldOrder:storyNoteOrder',s)
if __name__=='__main__':unittest.main()
