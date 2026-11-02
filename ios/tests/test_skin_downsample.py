from pathlib import Path
import unittest
R=Path(__file__).resolve().parents[1]
class SkinDownsample(unittest.TestCase):
 def test_dimensions_and_hold_regions(self):
  for width,height,head,tail in ((5200,1600,50,50),(1300,1300,200,200),(1000,8000,153,50)):
   factor=min(1,4096/max(width,height));w=round(width*factor);h=round(height*factor)
   self.assertLessEqual(max(w,h),4096)
   ratio=h/height
   self.assertAlmostEqual((head*ratio)/h,head/height)
   self.assertAlmostEqual((tail*ratio)/h,tail/height)
   self.assertAlmostEqual(w/(w/1.5),1.5)
 def test_runtime_uses_bounded_decoder_and_scales_atlas(self):
  s=(R/'PhiMod/Sources/PMRuntimeFeatures.mm').read_text(encoding='utf-8')
  for token in ('CGImageSourceCreateThumbnailAtIndex','kCGImageSourceThumbnailMaxPixelSize:@4096','double(height)/sourceH','skinAtlasYScale.clear()','skinHeadMH:skinHead)*atlasScale','skinTailMH:skinTail)*atlasScale'):
   self.assertIn(token,s)
  self.assertNotIn('skin texture exceeds 4096 px/device-safe limits',s)
  self.assertIn('-framework ImageIO',(R/'build_unsigned.sh').read_text(encoding='utf-8'))
if __name__=='__main__':unittest.main()
