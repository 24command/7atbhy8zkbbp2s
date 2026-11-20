from pathlib import Path
import unittest
class SelectorImages(unittest.TestCase):
 def test_preparation_cache_is_bounded_and_invalidated(self):
  s=(Path(__file__).resolve().parents[1]/'PhiMod/Sources/PMContentRuntime.mm').read_text(encoding='utf-8')
  image=s.split('P image(',1)[1].split('P audio(',1)[0]
  for text in ('totalCostLimit=24*1024*1024','countLimit=16','NSFileSize','NSFileModificationDate','PMContentStore.shared.revision','UIImageOrientationUp','sourceW<=maxSide','sourceH<=maxSide','if(directPNG)encoded=original;'):
   self.assertIn(text,image)
  self.assertIn('bool directPNG=!chapterBlur&&',image)
  self.assertIn('PMContentStore.shared.revision,chapterBlur]',image)
  self.assertLess(image.index('img=PMBlurCover('),image.index('encoded=UIImagePNGRepresentation(img)'))
  self.assertIn('if(prepared){encoded=prepared[@"data"]',image)
  self.assertIn('sourceW=[prepared[@"width"] doubleValue]',image)
  self.assertIn('background?std::min(actualW/38.4f,actualH/21.6f)',image)
if __name__=='__main__':unittest.main()
