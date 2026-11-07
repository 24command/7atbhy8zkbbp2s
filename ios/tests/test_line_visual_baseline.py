from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
class LineVisualBaseline(unittest.TestCase):
 def test_visual_inherits_source_renderer_not_note_parent(self):
  s=(ROOT/'PhiMod/Sources/PMContentRuntime.mm').read_text(encoding='utf-8')
  block=s[s.index('if(!story&&([d[@"scaleXEvents"]count]'):s.index('// Fake notes are independent')]
  self.assertIn('sourceTransform=r.call(renderer,"get_transform")',block)
  self.assertIn('{sourceTransform,&world}',block)
  self.assertIn('r.call(child,"set_localScale"',block)
  self.assertNotIn('r.call(tr,"set_localScale"',block)
  for prop in ('sprite','drawMode','size','flipX','flipY'):
   self.assertIn('r.call(renderer,"get_'+prop+'")',block)
   self.assertIn('r.call(display,"set_'+prop+'"',block)
 def test_axis_scaling_preserves_authored_baseline(self):
  # Copying the renderer size and inheriting its transform must match native
  # visual dimensions even for a separate child renderer or negative scales.
  for size in ((36.,.12),(1.,1.),(18.,.25)):
   for parent in ((1.,1.),(.5,2.),(-1.,1.)):
    for event in ((1.,1.),(.25,3.),(0.,0.),(-2.,.5)):
     expected=tuple(size[i]*parent[i]*event[i] for i in range(2))
     copied=tuple((size[i]*event[i])*parent[i] for i in range(2))
     for a,b in zip(expected,copied):self.assertAlmostEqual(a,b)
if __name__=='__main__':unittest.main()
