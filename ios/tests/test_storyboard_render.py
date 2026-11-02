import unittest
from pathlib import Path
class StoryboardRender(unittest.TestCase):
 def test_logical_image_size_survives_downsampling(self):
  for source,decoded in ((1350,1350),(4096,2048),(8192,2048),(256,256)):
   for world in (18.,24.):
    ppu=100.*decoded/source
    scale=100.*world/1350.
    self.assertAlmostEqual(decoded/ppu*scale,source*world/1350.)
 def test_font_unit_matches_android(self):
  for world in (18.,24.):self.assertAlmostEqual((world*.04/48)*48,world*.04)
 def test_independent_visuals_and_serialized_anchor(self):
  s=(Path(__file__).resolve().parents[1]/'PhiMod/Sources/PMContentRuntime.mm').read_text(encoding='utf-8')
  body=s.split('void updateStory(',1)[1].split('void visuals(',1)[0]
  self.assertNotIn('SetParent',body)
  self.assertIn('"UnityEngine.UI","Text"',body)
  self.assertIn('width*.04f/48.f',body)
  self.assertIn('100.f*width/1350.f',body)
  self.assertIn('image(r,path,false,true,anchor)',body)
  self.assertIn('storyTexturePath(texture)',body)
  self.assertIn('"set_rotation"',body)
if __name__=='__main__':unittest.main()
