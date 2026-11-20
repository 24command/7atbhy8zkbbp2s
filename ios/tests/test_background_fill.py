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
  self.assertIn('background?std::min(actualW/38.4f,actualH/21.6f):lineTexture?100.f*actualW/sourceW:100.f',s)
  self.assertIn('[lower containsString:@"blur"]?@"blur"',s)
  self.assertIn('obj=image(r,path,chapterBlur||[kind isEqualToString:@"blur"],false,{.5f,.5f},chapterBlur)',s)
  self.assertIn('sprite=image(r,path,false,true,anchor);',s)
 def test_chapter_blur_uses_the_card_mask_and_active_background(self):
  s=(Path(__file__).resolve().parents[1]/'PhiMod/Sources/PMContentRuntime.mm').read_text(encoding='utf-8')
  assign=s.split('void applyCachedChapterCover(',1)[1].split('void syncChapterCoverFallbacks',1)[0]
  self.assertLess(assign.index('fitChapterCardCover(r,loader)'),assign.index('if(!strcmp(loaderField,"cover"))'))
  ready=s.split('void chapterReady(',1)[1].split('void*loadSkinAudio',1)[0]
  for text in ('/chapterBlur@','"_nowChapterIndex"','"_nowBackgroundIndex"','r.arrayAt(backgrounds,active)','r.get<P>(card,"coverBlurAssetCode")','r.call(loader,"set_Code"'):
   self.assertIn(text,ready)
if __name__=='__main__':unittest.main()
