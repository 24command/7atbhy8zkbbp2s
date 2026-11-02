from pathlib import Path
import unittest
R=Path(__file__).resolve().parents[1]/'PhiMod/Sources'
class ShortHold(unittest.TestCase):
 def test_scope_restores_and_registers_true_time(self):
  s=(R/'PMHookBackend.mm').read_text(encoding='utf-8').split('bool onHold(',1)[1].split('bool onFlick',1)[0]
  self.assertLess(s.index('registerOne(note)'),s.index('duration+.22f'))
  self.assertEqual(s.count('r.put(note,"holdTime",duration);'),2)
  c=(R/'PMContentRuntime.mm').read_text(encoding='utf-8').split('bool shortSourceHold(',1)[1].split('bool customLevel',1)[0]
  self.assertIn('!currentChart||it==extras.end()',c)
  self.assertIn('duration>0&&duration<.22f',c)
 def test_short_tail_boundaries(self):
  for duration in (.01,.075757575757576,.15,.219):
   start=15.303030303030303
   self.assertLess(start+duration-.22,start)
   self.assertAlmostEqual(start+duration+.22-.22,start+duration)
if __name__=='__main__':unittest.main()
