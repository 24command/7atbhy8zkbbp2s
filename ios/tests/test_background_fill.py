import unittest
from pathlib import Path
class BackgroundFill(unittest.TestCase):
 def test_cover_dimensions_preserve_aspect(self):
  for w,h in ((1920,1080),(1280,720),(512,512),(1080,1920),(2048,512),(4096,2304)):
   ppu=min(w/38.4,h/21.6)
   self.assertGreaterEqual(w/ppu+1e-6,38.4)
   self.assertGreaterEqual(h/ppu+1e-6,21.6)
   self.assertAlmostEqual((w/ppu)/(h/ppu),w/h)
 def test_background_only_routing(self):
  s=(Path(__file__).resolve().parents[1]/'PhiMod/Sources/PMContentRuntime.mm').read_text(encoding='utf-8')
  self.assertIn('bool background=false',s)
  self.assertIn('background?std::min(actualW/38.4f,actualH/21.6f):100.f',s)
  self.assertIn('[lower containsString:@"blur"]?@"blur"',s)
  self.assertIn('image(r,pmunlock::coverPath(r,identifier),[kind isEqualToString:@"blur"])',s)
  self.assertIn('P sprite=image(r,path);',s)
if __name__=='__main__':unittest.main()
