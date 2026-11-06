from pathlib import Path
import unittest
R=Path(__file__).resolve().parents[1]/'PhiMod/Sources'
class ShortHold(unittest.TestCase):
 def test_scope_restores_and_registers_true_time(self):
  s=(R/'PMHookBackend.mm').read_text(encoding='utf-8').split('bool onHold(',1)[1].split('bool onFlick',1)[0]
  self.assertLess(s.index('registerOne(note)'),s.index('plan.adjustedDuration'))
  self.assertEqual(s.count('r.put(note,"holdTime",duration);'),2)
  c=(R/'PMContentRuntime.mm').read_text(encoding='utf-8').split('bool shortSourceHold(',1)[1].split('bool customLevel',1)[0]
  self.assertIn('!currentChart||it==extras.end()',c)
  self.assertIn('duration>0&&duration<.22f',c)
 def test_short_tail_boundaries(self):
  for duration in (.01,.075757575757576,.125,.219):
   grace=min(.08,duration)
   self.assertAlmostEqual(duration+.22-grace-.22,duration-grace)
   self.assertGreaterEqual(duration-grace,0)
if __name__=='__main__':unittest.main()
